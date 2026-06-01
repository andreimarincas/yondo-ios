//
//  IAPManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 31.12.2025.
//

import SwiftUI
import Observation
import Combine

@MainActor
/// Manages in-app purchases and user entitlements.
/// Coordinates with SecureCreditStore for persistent state management.
final class IAPManager: NSObject, ObservableObject {
    let serviceType: IAPServiceType = .revenueCat
    
    static let shared = IAPManager(creditStore: SecureCreditStore())
    
    // MARK: - Dependencies
    private(set) var processor: PurchaseProcessor
    let creditStore: SecureCreditStore
    let syncService: SyncService
    
    @Published var purchasingProductID: String?
    
    var isEconomyUIActive: Bool {
        return purchasingProductID != nil || isAnimatingCelebration || isSyncSafetyLockActive
    }
    
    @Published var isSyncSafetyLockActive: Bool = false
    private var syncSafetyTask: Task<Void, Never>?
    private var syncSafetyToken: UUID?
    
    var isAnimatingCelebration: Bool = false
    
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(Error)
        
        var debugDescription: String {
            switch self {
            case .idle: return "idle"
            case .loading: return "loading"
            case .loaded: return "loaded"
            case .error(let error): return "error(\(error.localizedDescription))"
            }
        }
    }
    
    // MARK: - UI-specific published state
    @Published var products: [PurchaseType: any YondoProduct] = [:]
    
    @Published var loadingState: LoadingState = .idle {
        didSet {
            Log.debug("🛍️ IAPManager: State changed from [\(oldValue.debugDescription)] to [\(loadingState.debugDescription)]")
        }
    }
    
    @Published var lastFetchDate: Date? = nil
    
    let networkMonitor = NetworkMonitor()
    var networkTask: Task<Void, Never>?
    
    let retryBackoffInterval: TimeInterval = 300 // 5 minutes
    let refreshInterval: TimeInterval = 1800    // 30 minutes
    
    @ObservationIgnored var skUpdateTask: Task<Void, Never>?
    
    var lastCustomerInfoRequestDate: Date?
    
    private var activeNetworkHydrationTask: Task<Void, Never>?
    
    /// Tracks the exact time a purchase or restore successfully finished.
    @Published private(set) var lastPurchaseDate: Date?
    
    private var lastRefreshDate: Date?
    
    private init(creditStore: SecureCreditStore, syncService: SyncService? = nil) {
        Log.debug("🛍️ IAPManager INIT: Starting initialization with creditStore: \(creditStore)")
        self.creditStore = creditStore
        self.processor = PurchaseProcessor(store: creditStore)
        self.syncService = syncService ?? FirebaseSyncService.shared
        
        super.init()
        
        Log.debug("🛍️ IAPManager INIT: Setting up transaction updates listener")
        // Listen for transaction updates (StoreKit) in a detached task
        observeTransactionUpdate()
        Log.debug("🛍️ IAPManager INIT: Transaction updates listener configured")
        
        Log.debug("🛍️ IAPManager INIT: Setting up network observer")
        // Listen for network recovery
        observeNetwork()
        Log.debug("🛍️ IAPManager INIT: Network observer configured. Initialization complete")
    }
    
    deinit {
        skUpdateTask?.cancel()
        syncSafetyTask?.cancel()
    }
    
    func start(userId: String? = nil) async {
        Log.debug("🛍️ IAPManager: Starting for user \(userId ?? "anonymous")")
        
        // Identity Change Safety
        // If we were mid-purchase celebration for User A and User B logs in,
        // we MUST kill the timer and the lock immediately.
        syncSafetyTask?.cancel()
        syncSafetyTask = nil
        syncSafetyToken = nil
        isSyncSafetyLockActive = false
        
        // Let's interpret nil as "local" or "anonymous" to keep it 1:1 with ImageStore
        let normalizedUID = userId ?? "anonymous"
        
        // 1. AWAIT LOCAL STATE (Fast)
        // We MUST await this so the rest of the app knows the user's cached balances
        if creditStore.userId != normalizedUID {
            // Tell the store to switch identities.
            // Views observing iapManager.creditStore will stay linked.
            Log.debug("🛍️ IAPManager: Switching identity to \(normalizedUID)")
            await creditStore.updateIdentity(userId: normalizedUID)
        } else {
            await creditStore.waitForInitialization()
        }
        
        // 🛑 Cancel any previous hydration task before spawning a new one!
        activeNetworkHydrationTask?.cancel()
        
        // 2. FIRE AND FORGET NETWORK STATE (Slow)
        // Spawn a Task to fetch prices and entitlements in the background.
        // This immediately returns control to AuthManager.bootstrap()!
        activeNetworkHydrationTask = Task {
            Log.debug("🛍️ IAPManager: ☁️ Spawning background task to hydrate products and entitlements.")
            
            // Check for cancellation before expensive operations
            guard !Task.isCancelled else { return }
            
            // 🚀 The Smart Valve:
            // This checks if 30 mins have passed or if the products array is empty!
            if shouldRefresh() {
                Log.debug("🛍️ IAPManager: 🛰️ Cache expired or empty. Hitting network.")
                await fetchProducts()
                
                guard !Task.isCancelled else { return }
                _ = await refreshEntitlements()
            } else {
                Log.debug("🛍️ IAPManager: ✅ Cache is fresh (< 30 mins). Skipping network hydration.")
            }
        }
    }
    
    func startSyncSafetyTimer() {
        Log.debug("🛡️ IAPManager: Starting Sync Safety Lock (3s).")
        
        syncSafetyTask?.cancel()
        isSyncSafetyLockActive = true
        
        let token = UUID()
        self.syncSafetyToken = token
        
        // We use a detached task so it survives even if the calling view disappears
        self.syncSafetyTask = Task.detached(priority: .userInitiated) { [weak self, token, syncService] in
            // 3 seconds is usually enough for RC -> Firebase updates
            try? await Task.sleep(for: .seconds(3.0))

            guard !Task.isCancelled else {
                Log.debug("🛡️ IAPManager: Safety Task cancelled; skipping flush.")
                return
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }

                guard self.syncSafetyToken == token else {
                    Log.debug("🛡️ IAPManager: Ignoring stale safety timer flush.")
                    return
                }

                self.isSyncSafetyLockActive = false

                // Trigger one final flush now that we are sure the lock is off
                Log.debug("🛡️ IAPManager: Sync Safety Lock released. Triggering final flush.")
                Task {
                    await syncService.flushBuffers()
                }
            }
        }
    }
    
    /// A window where we assume the backend might still be syncing.
    /// A 90-second window is the 'Goldilocks' zone.
    /// Long enough for a RevenueCat retry, short enough to not feel like a hang.
    var wasPurchaseMadeRecently: Bool {
        guard let lastPurchase = lastPurchaseDate else { return false }
        return Date().timeIntervalSince(lastPurchase) < 90
    }
    
    func recordSuccessfulPurchase() {
        self.lastPurchaseDate = Date()
        Log.debug("🛍️ IAPManager: Purchase recorded at \(Date()). Sync window active.")
    }
    
    var hasSpendableCreditsProducts: Bool {
        products.keys.contains { $0.isConsumable }
    }
    
    var numberOfConsumableProducts: Int {
        products.keys.filter(\.isConsumable).count
    }
    
    func prepareForModalPresentation() {
        let isOffline = !networkMonitor.isConnected
        Log.debug("🛍️ IAPManager: UI preparing modal. Products count: \(products.count), Offline: \(isOffline)")
        
        if products.isEmpty || shouldRefresh() {
            if isOffline && !products.isEmpty {
                Log.debug("🛍️ IAPManager: UI offline but cached products exist. Skipping reset to .idle to prevent blank screens.")
            } else {
                Log.debug("🛍️ IAPManager: Resetting state to .idle for modal presentation.")
                loadingState = .idle
            }
        }
    }
    
    func fetchProducts() async {
        let isConnected = networkMonitor.isConnected
        Log.debug("🛍️ IAPManager: fetchProducts() requested. Network Connected: \(isConnected), Current State: \(loadingState.debugDescription)")
        
        // 🛑 THE PURCHASE LOCK
        // If the user is actively buying something, NEVER refresh the products array
        // or change the UI to a loading state. Wait until the purchase finishes.
        guard purchasingProductID == nil else {
            Log.debug("🛍️ IAPManager: 🛑 Fetch blocked. A purchase is currently in progress for [\(purchasingProductID!)].")
            return
        }
        
        // Allow if idle OR already loaded (for background refresh)
        // If we are in .error, we want the user to use retryFetch() instead.
        guard loadingState == .idle || loadingState == .loaded else {
            Log.debug("🛍️ IAPManager: 🛑 Fetch blocked. State is neither .idle nor .loaded.")
            return
        }
        
        if !isConnected && !products.isEmpty {
            Log.debug("🛍️ IAPManager: ⚠️ Device offline but cache exists. Yielding cache instead of fetching.")
        }
        
        await performFetch()
    }
    
    func retryFetch() async {
        let isConnected = networkMonitor.isConnected
        Log.debug("🛍️ IAPManager: retryFetch() requested manually. Network Connected: \(isConnected)")
        
        // If we are already loading, don't start a second fetch
        guard loadingState != .loading else {
            Log.debug("🛍️ IAPManager: 🛑 Retry blocked because another fetch is already loading.")
            return
        }
        
        // DON'T clear self.products = [:] here.
        // If we have old products, keep them in memory as a fallback.
//            self.products = [:]
        
        self.loadingState = .idle
        
        await performFetch()
    }
    
    @MainActor
    func finalizeFetch(fetchedProducts: [PurchaseType: any YondoProduct], error: Error?, updateDate: Bool) {
        let cacheStatus = self.products.isEmpty ? "Empty" : "Has \(self.products.count) items"
        Log.debug("🛍️ IAPManager: Completing fetch. Fetched items: \(fetchedProducts.count), Error: \(error?.localizedDescription ?? "None"), Local Cache Status: \(cacheStatus)")
        
        // 1. SUCCESS: We got new products.
        if !fetchedProducts.isEmpty {
            Log.debug("🛍️ IAPManager: ✅ Fetch Succeeded. Hydrating \(fetchedProducts.count) products.")
            self.products = fetchedProducts
            if updateDate { self.lastFetchDate = Date() }
            self.loadingState = .loaded
            return
        }
        
        // 2. BACKGROUND FAILURE: We have an error, but we already have products in memory.
        if let error = error, !self.products.isEmpty {
            Log.error("IAPManager: ⚠️ Background fetch failed but fallback cache exists. Error: \(error). Implementing back-off.")
            
            // We advance the lastFetchDate to 25 minutes ago (30 - 5).
            // This ensures shouldRefresh() returns false for the next 5 minutes.
            self.lastFetchDate = Date().addingTimeInterval(-(refreshInterval - retryBackoffInterval)) // 1800s (30m) - 300s (5m)
            
            // Keep the UI in .loaded state so the user isn't interrupted
            self.loadingState = .loaded
            return
        }

        // 3. HARD FAILURE: No products and no cache.
        if let error = error {
            Log.error("IAPManager: ❌ Hard Fetch Failure (No Cache). Error: \(error)")
            self.loadingState = .error(error)
        } else {
            // Successful fetch but empty (Regional issue)
            Log.error("IAPManager: ❌ Region Empty issue. No products returned from StoreKit/RevenueCat.")
            self.products = [:]
            if updateDate { self.lastFetchDate = Date() }
            
            // Explicitly pass the region error so PurchaseModalView knows to show the Map Pin
            self.loadingState = .error(StoreError.emptyRegion)
        }
    }
    
    func consumeCredit() async throws {
        Log.debug("🛍️ IAPManager.consumeCredit() called")
        try await creditStore.consumeCredit()
    }
    
    func shouldRefresh() -> Bool {
        // 1. Always refresh if we haven't even tried yet
        guard let lastFetch = lastFetchDate else {
            Log.debug("🛍️ IAPManager: shouldRefresh -> true (No previous fetch date)")
            return true
        }
        
        let timePassed = Date().timeIntervalSince(lastFetch)
        
        // 2. Handle Error states with nuance
        if case .error(let error) = loadingState {
            if let storeError = error as? StoreError {
                switch storeError {
                case .networkIssue:
                    // Network is transient. If they open the store,
                    // we should always try to fix this.
                    Log.debug("🛍️ IAPManager: shouldRefresh -> true (Retrying transient network error)")
                    return true
                case .emptyRegion:
                    // Regional empty is "Terminal" for this session.
                    // Only retry once every 24 hours (86,400 seconds)
                    // to prevent constant spinners.
                    let allowRetry = timePassed > 86400
                    Log.debug("🛍️ IAPManager: shouldRefresh -> \(allowRetry) (Regional block, time since last check: \(timePassed)s)")
                    return allowRetry
                default:
                    break
                }
            }
            Log.debug("🛍️ IAPManager: shouldRefresh -> true (Default fallback for unknown errors)")
            return true // Default for unknown errors
        }

        // 3. Handle the "Loaded but Empty" edge case
        // (If it reached .loaded but products is empty, treat it like a regional issue)
        if products.isEmpty {
            let allowRetry = timePassed > 86400
            Log.debug("🛍️ IAPManager: shouldRefresh -> \(allowRetry) (Products empty but marked loaded. Cooling off.)")
            return allowRetry
        }

        // 4. Standard Success: Refresh every 30 minutes to keep prices/metadata fresh.
        let standardRefresh = timePassed > refreshInterval
        Log.debug("🛍️ IAPManager: shouldRefresh -> \(standardRefresh) (Normal cache check. Time elapsed: \(Int(timePassed))s / limit: \(Int(refreshInterval))s)")
        return standardRefresh
    }
    
    // MARK: - Generic Methods
    
    func purchase(_ type: PurchaseType) async throws -> PurchaseResult {
        Log.debug("🛍️ IAPManager: 🛒 Purchase attempted for type: \(type)")
        
        if !networkMonitor.isConnected {
            Log.error("IAPManager: Device is offline.")
        }
        
        let result: PurchaseResult
        if serviceType == .revenueCat {
            result = try await purchaseViaRevenueCat(type)
        } else {
            result = try await purchaseViaStoreKit(type)
        }
        
        if result == .success {
            recordSuccessfulPurchase()
            startSyncSafetyTimer()
        }
        
        return result
    }
    
    private func performFetch() async {
        Log.debug("🛍️ IAPManager: 🛰️ performFetch() initiated using provider: [\(serviceType)]")
        
        if serviceType == .revenueCat {
            await fetchRevenueCatProducts()
        } else {
            await fetchStoreKitProducts()
        }
    }
    
    func refreshEntitlements(force: Bool = false) async -> Bool {
        // Only refresh if more than 5 minutes have passed
        if let last = lastRefreshDate, Date().timeIntervalSince(last) < 300, !force {
            Log.debug("🛍️ IAPManager: ⏩ Refresh throttled. Using cached state.")
            return creditStore.premiumDestinationsUnlocked
        }
        
        lastRefreshDate = Date()
        Log.debug("🛍️ IAPManager: 🔄 refreshEntitlements() requested using: [\(serviceType)], force: \(force)")
        
        let premiumBeforeRefresh = creditStore.premiumDestinationsUnlocked
        Log.debug("🛍️ IAPManager: 🔄 refreshEntitlements() requested. Current state: \(premiumBeforeRefresh)")
        
        // Ask the SDK (RevenueCat/StoreKit)
        let sdkReportedPremium: Bool
        if serviceType == .revenueCat {
            sdkReportedPremium = await refreshRevenueCatEntitlements()
        } else {
            sdkReportedPremium = await refreshStoreKitEntitlements()
        }
        
        // ⏳ Add a small buffer to let RevenueCat's REST API catch up
        try? await Task.sleep(for: .seconds(1.5))
        
        // Fallback Healer: If SDK is unsure OR to ensure Firestore is synced
        // We try the server check. If it fails (network etc.), we don't throw;
        // we just rely on whatever the SDK found.
        do {
            Log.debug("🛍️ IAPManager: 🔄 Refreshing server truth...")
            _ = try await syncService.verifyPremiumWithServer(allowDowngrade: force)
        } catch {
            Log.warning("IAPManager: ⚠️ refreshEntitlements server check failed: \(error)")
        }
        
        // The "Single Source of Truth" check
        // Instead of comparing local variables, we check the actual data store
        // that the UI is observing. This covers all bases.
        let isNowPremium = self.creditStore.premiumDestinationsUnlocked
        
        // 🔍 THE HEALER LOG:
        // This triggers if the SDK thought it was false, but the Server fixed it to true.
        if !sdkReportedPremium && isNowPremium {
            Log.debug("🎯 IAPManager: ✅ HEALER SUCCESS! SDK missed premium, but Server confirmed it.")
        }
        
        // 🔍 IDEMPOTENCY CHECK:
        // Only "Record" if this is a fresh discovery (False -> True transition).
        if !premiumBeforeRefresh && isNowPremium {
            Log.debug("🎯 IAPManager: New Premium discovery during refresh. Recording success.")
            recordSuccessfulPurchase()
        } else if isNowPremium {
            Log.debug("🛍️ IAPManager: Premium confirmed, but already known. No re-recording needed.")
        }
        
        Log.debug("🛍️ IAPManager: ✅ refreshEntitlements() finished. Premium: \(isNowPremium)")
        return isNowPremium // TODO: Double-check if we are returning the correct value here
    }
    
    func restorePurchases() async throws -> Bool {
        Log.debug("🛍️ IAPManager: ⏳ restorePurchases() requested using: [\(serviceType)]")
        
        // 1. Start the UX clock
        let startTime = Date()
        let minimumWaitTime: TimeInterval = 1.5
        
        // 2. Run the potentially heavy Auth sync FIRST
        try await ensureAuthenticated()
        
        // 3. Calculate elapsed time and sleep ONLY the difference
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < minimumWaitTime {
            let remainingSleep = minimumWaitTime - elapsed
            Log.debug("🧘‍♂️ IAPManager: Auth was fast (\(elapsed)s). Sleeping \(remainingSleep)s for UX.")
            try await Task.sleep(for: .seconds(remainingSleep))
        } else {
            Log.debug("🏃‍♂️ IAPManager: Auth took \(elapsed)s. Skipping UX sleep to avoid lag.")
        }
        
        do {
            // 1. Ask the SDK to check local receipts
            let sdkFound: Bool
            if serviceType == .revenueCat {
                sdkFound = try await restoreRevenueCatPurchases()
            } else {
                sdkFound = try await restoreStoreKitPurchases()
            }
            
            if sdkFound {
                // 🎉 IDEMPOTENCY CHECK:
                // If the SDK finds a purchase, but our local Store already knew about it,
                // the Processor returns 'false'. We return 'true' here ONLY if this was
                // a *new* discovery for this device, which triggers the celebration UI.
                Log.debug("🎉 IAPManager: SDK verified. Celebrating and returning early to UI.")
                recordSuccessfulPurchase()
                
                // 🔥 NON-BLOCKING SYNC:
                // We trigger the backend verify in a detached Task so the UI unblocks
                // immediately. We trust the SDK's local receipt for the initial 'Success'.
                Task {
                    try? await Task.sleep(for: .seconds(2.0))
                    
                    // This 'pokes' the server to update Firestore to 'true'
                    // Do not allow premium downgrade here, restore should always be a level-up change, if any
                    _ = try? await syncService.verifyPremiumWithServer(allowDowngrade: false)
                    Log.debug("☁️ IAPManager: Background server-sync completed.")
                }
                
                return true // UI is unblocked instantly
            }
            
            // If we reach here, either SDK found nothing (False)
            // OR the user was already premium and the processor returned False (Idempotency).
            let wasPremiumBefore = self.creditStore.premiumDestinationsUnlocked
            
            // 2. SDK found NOTHING.
            // Go to the server immediately. No extra sleep needed.
            Log.debug("🛍️ IAPManager: SDK found nothing. Checking server immediately as last resort...")
            // Do not throw error for server hiccups, we finish successfully with no purchases found instead
            // Do not allow premium downgrade here, restore should always be a level-up change, if any
            _ = try? await syncService.verifyPremiumWithServer(allowDowngrade: false)
            
            let isNowPremium = self.creditStore.premiumDestinationsUnlocked
            if isNowPremium && !wasPremiumBefore {
                recordSuccessfulPurchase()
                return true
            }
            
            // No purchases found to restore, already up to date
            return false
            
        } catch {
            Log.error("IAPManager: ❌ restorePurchases() failed with error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Debug
    
#if DEBUG
    /// Allows simulating different failure scenarios in development.
    enum DebugScenario: String, CaseIterable {
        case none = "None (Normal)"
        case storeFetchError = "Simulate StoreKit Error"
        case slowNetwork = "Simulate Slow Network"
        case keychainFailure = "Simulate Keychain Error"
        case resetAllPurchases = "Reset All Purchases"
    }
    
    @Published var activeDebugScenario: DebugScenario = .none {
        didSet {
            simulateScenario(activeDebugScenario)
        }
    }
    
    private func simulateScenario(_ scenario: DebugScenario) {
        Log.debug("🛍️ IAPManager: 🛠️ Triggering debug scenario -> [\(scenario.rawValue)]")
        
        // Use a task to ensure the change happens on the next run loop
        Task { @MainActor in
            // 1. Give the UI a moment to breathe (closes the menu)
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            Log.debug("🛍️ IAPManager: ⚙️ Executing scenario block for: [\(scenario.rawValue)]")
            
            switch scenario {
            case .storeFetchError:
                // Force the UI into the error state
                Log.debug("🛍️ IAPManager: 🛠️ Debug Scenario - Forcing loadingState to .error")
                self.loadingState = .error(NSError(domain: "Debug", code: 0, userInfo: [NSLocalizedDescriptionKey: "The App Store is temporarily unavailable."]))
                
            case .none:
                // Clear the error and trigger a REAL fetch
                Log.debug("🛍️ IAPManager: 🛠️ Debug Scenario - Normalizing. Clearing error and retrying fetch.")
                await self.retryFetch()
                
            case .slowNetwork:
                Log.debug("🛍️ IAPManager: 🛠️ Debug Scenario - Simulating slow network by retrying fetch.")
                await self.retryFetch()
                
            case .keychainFailure:
                // Handle other debug cases here
                Log.debug("🛍️ IAPManager: 🛠️ Debug Scenario - Keychain Failure (Placeholder logic required)")
                break
                
            case .resetAllPurchases:
                Log.debug("🛍️ IAPManager: 🛠️ Debug Scenario - Resetting all local purchase data.")
                Task {
                    await creditStore.resetAll()
                    Log.debug("🛍️ IAPManager: 🛠️ Debug Scenario - Local purchase data reset complete.")
                }
            }
        }
    }
#endif
}

extension IAPManager.LoadingState {
    static func == (lhs: IAPManager.LoadingState, rhs: IAPManager.LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case let (.error(le), .error(re)):
            // If they are both StoreErrors, use our custom Equatable
            if let lse = le as? StoreError, let rse = re as? StoreError {
                return lse == rse
            }
            // Fallback for generic errors
            let l = le as NSError
            let r = re as NSError
            return l.domain == r.domain && l.code == r.code
        default:
            return false
        }
    }
    
    var idValue: String {
        switch self {
        case .idle: return "idle"
        case .loading: return "loading"
        case .loaded: return "loaded"
        case .error(let error):
            let ns = error as NSError
            return "error-\(ns.domain)-\(ns.code)"
        }
    }
    
//    var isRetryable: Bool {
//        switch self {
//        case .idle:
//            return true
//        case .error(let error):
//            // Only retry automatically if it's a network issue
//            if let storeError = error as? StoreError {
//                switch storeError {
//                case .networkIssue: return true
//                case .emptyRegion: return false
//                default: break
//                }
//            }
//            return true // Default for unknown errors
//        default:
//            return false
//        }
//    }
}
