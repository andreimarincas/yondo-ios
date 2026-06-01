//
//  SecureCreditStore.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.01.2026.
//

import Foundation
import Observation
import Combine

struct CreditStoreState: Codable {
    var version: Int = 2
    var credits: Int = 0
    var processedTransactionIDs: Set<String> = []
    var premiumDestinationsUnlocked: Bool = false
    var hasPurchasedCredits: Bool = false
    var hasGrantedFreeCredits: Bool = false
}

/// Main-thread isolated store for credit and premium data.
/// Uses @Observable for modern SwiftUI integration and offloads persistence
/// to the KeychainStore actor in the background.
@Observable
@MainActor
final class SecureCreditStore: CreditStore {

    // MARK: - Identity
    private(set) var userId: String?
    
    private var stateKey: String {
        let suffix = userId ?? "anonymous"
        return "yondo.state.blob.v2.\(suffix)"
    }
//    private let stateKey = "yondo.state.blob.v1"
    
    // MARK: - Dependencies
    private let keychain = KeychainStore.shared
    private let initialFreeAmount = 0 // 3
    
    // MARK: - Observable States
    
    private(set) var credits: Int = 0 {
        didSet { creditsSubject.send(credits) }
    }
    
    private(set) var premiumDestinationsUnlocked: Bool = false {
        didSet { premiumSubject.send(premiumDestinationsUnlocked) }
    }
    
    private(set) var hasPurchasedCredits: Bool = false
    private(set) var hasGrantedFreeCredits: Bool = false
    private(set) var isSyncing: Bool = false
    
    @ObservationIgnored private(set) var processedTransactionIDs: Set<String> = []
    
    @ObservationIgnored private(set) var initializationTask: Task<Void, Never>!
    
    /// Returns true if the store is currently performing a background save
    /// or initialization, meaning buttons should be disabled.
    var isBusy: Bool {
        isSyncing || isInitializing
    }
    
    private var isInitializing: Bool = true
    
    @ObservationIgnored private var pendingSaveTask: Task<Void, Error>?
    @ObservationIgnored private var lastSaveOperationID: UUID?
    
    // Internal Subjects to bridge to Combine
    private let creditsSubject = CurrentValueSubject<Int, Never>(0)
    private let premiumSubject = CurrentValueSubject<Bool, Never>(false)
    
    // MARK: - Init
    init(userId: String? = nil) {
        self.userId = userId
        Log.debug("🔑 CreditStore: init() triggered for user -> [\(userId ?? "anonymous")]")
        
        // Initialize the task here instead of lazily
        self.initializationTask = Task { @MainActor in
            await self.initialize()
        }
    }
    
    // MARK: - Publishers
    var creditsPublisher: AnyPublisher<Int, Never> {
        creditsSubject
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    var premiumPublisher: AnyPublisher<Bool, Never> {
        premiumSubject
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    private func initialize() async {
        isInitializing = true
        
        Log.debug("🔑 CreditStore: 🏁 Loading standard initialization protocols.")
        await loadInitialState()
        
//        if userId != nil && !hasGrantedFreeCredits {
//            try? await grantInitialFreeCredits()
//        }
        isInitializing = false
        
        Log.debug("🔑 CreditStore: ✅ Initialization complete. Verified Current Credits: \(credits)")
    }
    
    func updateIdentity(userId: String?) async {
        guard userId != self.userId else {
            Log.debug("🔑 CreditStore: updateIdentity() skipped. No identity shift required for [\(userId ?? "anonymous")].")
            return
        }
        
        Log.debug("🔑 CreditStore: 👤 Identity shifting from [\(self.userId ?? "anonymous")] to [\(userId ?? "anonymous")].")
        
        // Wait for any existing save/init to finish to avoid data corruption
        Log.debug("🔑 CreditStore: Identity shift waiting for ongoing saves & initialization task to finish to prevent data overlap.")
        _ = await initializationTask.value
        _ = try? await pendingSaveTask?.value
        
        // Update the ID
        self.userId = userId
        
        // Reset the local UI state immediately so we don't leak
        // User A's balance into User B's view during the transition
        Log.debug("🔑 CreditStore: Identity updated. Immediately wiping standard memory UI to prevent screen leaks during load transitions.")
        apply(CreditStoreState())
        
        // Create a NEW initialization task for the new user
        // This ensures that anyone calling `waitForInitialization()` gets the new user's data
        Log.debug("🔑 CreditStore: Spawning fresh initialization task for the new identity.")
        self.initializationTask = Task { @MainActor in
            await self.initialize()
        }
        
        // Wait for the new user's data to actually load
        await self.initializationTask.value
    }
    
    func waitForInitialization() async {
        await initializationTask.value
    }
    
    // Ensure the ID check is strictly checking the locally cached processedTransactionIDs
    func isTransactionProcessed(transactionID: String) -> Bool {
        return processedTransactionIDs.contains(transactionID)
    }
    
    // MARK: - IAP Mutations (StoreKit 2 Compatibility)
    
    func addPurchase(credits amount: Int, transactionID: UInt64) async throws {
        try await addPurchase(credits: amount, transactionID: String(transactionID))
    }
    
    func unlockPremiumDestinations(transactionID: UInt64) async throws {
        try await unlockPremiumDestinations(transactionID: String(transactionID))
    }
    
    func applyBatch(credits amount: Int, transactions: Set<UInt64>, unlocksPremium: Bool) async throws {
        let stringSet = Set(transactions.map { String($0) })
        try await applyBatch(credits: amount, transactions: stringSet, unlocksPremium: unlocksPremium)
    }
    
    func isTransactionProcessed(transactionID: UInt64) -> Bool {
        return isTransactionProcessed(transactionID: String(transactionID))
    }
    
    // MARK: - IAP Mutations (Wait & Verify)
    
    func addPurchase(credits amount: Int, transactionID: String) async throws {
        Log.debug("💰 PURCHASE START: Processing \(amount) credits for ID \(transactionID)")
        Log.debug("Store: Checking transaction ID \(transactionID)...")
        
        if processedTransactionIDs.contains(transactionID) {
            Log.debug("Store: Blocking duplicate transaction ID \(transactionID) immediately.")
            return
        }
        
        // 1. Capture the "Pre-Flight" values
        let previouslyPurchased = self.hasPurchasedCredits
        
        // 2. Update memory immediately
        Log.debug("Store: transaction ID \(transactionID) ACCEPTED. Updating memory...")
        
        self.processedTransactionIDs.insert(transactionID)
        self.credits += amount
        self.hasPurchasedCredits = true
        
        Log.debug("💰 PURCHASE MEMORY UPDATED: Credits now \(self.credits)")
        
        do {
            Log.debug("Store: Suspending for Keychain write, transaction ID: \(transactionID)")
            try await saveState()
            Log.debug("✅ Store: Keychain write FINISHED, transaction ID: \(transactionID)")
        } catch {
            // 3. Rollback Logic
            self.credits -= amount
            self.processedTransactionIDs.remove(transactionID)
            
            // Only flip back to false if it was false before WE touched it
            if !previouslyPurchased {
                self.hasPurchasedCredits = false
            }
            
            throw error
        }
    }
    
    func addCredits(_ amount: Int) async throws {
        Log.debug("amount = \(amount)")
        
        // Update memory IMMEDIATELY (Before suspension)
        // This ensures UI is snappy and concurrent calls see the new truth.
        self.credits += amount
        
        do {
            // Queue the persistence
            try await saveState()
            Log.debug("SecureCreditStore: Manually added/refunded \(amount) credits.")
        } catch {
            // RELATIVE ROLLBACK
            // If the disk write fails, we give back/take away ONLY what we changed.
            self.credits -= amount
            
            Log.error("SecureCreditStore: Manual credit update failed. Rolled back.")
            throw StoreError.persistenceFailure(error)
        }
    }
    
    /// Atomic batch update for high-efficiency restores and syncs.
    func applyBatch(credits amount: Int, transactions: Set<String>, unlocksPremium: Bool) async throws {
        let newIDs = transactions.subtracting(self.processedTransactionIDs)
        
        // 1. Capture Booleans (Booleans still need snapshots)
        let previouslyUnlocked = self.premiumDestinationsUnlocked
        let previouslyPurchased = self.hasPurchasedCredits

        // 2. Immediate Memory Update
        self.credits += amount
        self.processedTransactionIDs.formUnion(newIDs)
        if unlocksPremium { self.premiumDestinationsUnlocked = true }
        if amount > 0 { self.hasPurchasedCredits = true }

        do {
            try await saveState()
        } catch {
            // 3. RELATIVE ROLLBACK (The gold standard)
            self.credits -= amount
            self.processedTransactionIDs.subtract(newIDs)
            
            // Booleans revert only if we were the ones who flipped them
            if !previouslyUnlocked { self.premiumDestinationsUnlocked = false }
            if !previouslyPurchased { self.hasPurchasedCredits = false }
            
            throw error
        }
    }
    
    func unlockPremiumDestinations(transactionID: String) async throws {
        // 1. Idempotency Check
        // If we've already recorded this ID, stop here.
        guard !processedTransactionIDs.contains(transactionID) else { return }

        // 2. Capture Previous State for Rollback
        let previouslyUnlocked = self.premiumDestinationsUnlocked
        
        // 3. Update Memory Immediately (Synchronous)
        self.premiumDestinationsUnlocked = true
        self.processedTransactionIDs.insert(transactionID) // Mark as "Handled" in memory
        
        do {
            // 4. Persistence Point (Suspension)
            try await saveState()
        } catch {
            // 5. Rollback on Failure
            // Remove the ID so that StoreKit can try again later
            self.processedTransactionIDs.remove(transactionID)
            
            // Only lock the door again if it was locked before WE turned the key
            if !previouslyUnlocked {
                self.premiumDestinationsUnlocked = false
            }
            
            Log.error("Failed to persist Premium Unlock for ID: \(transactionID)")
            throw error
        }
    }
    
    // MARK: - General Mutations
    
//    func grantInitialFreeCredits() async throws {
//        guard !hasGrantedFreeCredits else { return }
//        Log.debug("Granting initial free credits...")
//        
//        var freshState = CreditStoreState()
//        freshState.credits = initialFreeAmount
//        freshState.hasGrantedFreeCredits = true
//        
//        try await saveState()
//        apply(freshState)
//        
//        Log.debug("Initial free credits granted.")
//    }
    
    func consumeCredit() async throws {
        guard credits > 0 else { throw StoreError.insufficientFunds }
        
        self.credits -= 1
        
        do {
            try await saveState()
            Log.debug("SecureCreditStore: Credit successfully locked in Keychain.")
        } catch {
            // Rollback
            self.credits += 1
            
            Log.error("SecureCreditStore: Persistence failed, rolled back 1 credit.")
            throw StoreError.persistenceFailure(error)
        }
    }
    
    /// Completely wipes the local state and the Keychain record.
    /// Use this for testing or a "factory reset" feature.
    func resetAll() async {
        Log.debug("🔑 CreditStore: ☢️ ResetAll() triggered. Wiping keychain record and memory store.")
        
        await waitForInitialization()
        
        // Efficiently wait for the ENTIRE chain of saves to finish.
        _ = try? await pendingSaveTask?.value
        
        isSyncing = true // Lock the UI during the reset process
        defer { isSyncing = false }
        
        // Wipe the Keychain
        await keychain.delete(stateKey)
        
        // Wipe the memory (MainActor ensures UI updates safely)
        let freshState = CreditStoreState()
        apply(freshState)
        
        // Clear the task reference so the next save starts fresh
        pendingSaveTask = nil
        Log.debug("🔑 CreditStore: Reset successful.")
    }
    
    // MARK: - Private Helpers
    
    private var currentState: CreditStoreState {
        CreditStoreState(
            version: 2,
            credits: credits,
            processedTransactionIDs: processedTransactionIDs,
            premiumDestinationsUnlocked: premiumDestinationsUnlocked,
            hasPurchasedCredits: hasPurchasedCredits,
            hasGrantedFreeCredits: hasGrantedFreeCredits
        )
    }
    
    private func apply(_ state: CreditStoreState) {
        // We only update the data properties.
        // This triggers SwiftUI observers once for all changes.
        self.credits = state.credits
        self.processedTransactionIDs = state.processedTransactionIDs
        self.premiumDestinationsUnlocked = state.premiumDestinationsUnlocked
        self.hasPurchasedCredits = state.hasPurchasedCredits
        self.hasGrantedFreeCredits = state.hasGrantedFreeCredits
        
        // Since 'credits' and 'premium' use didSet, they will trigger
        // the subjects automatically. This ensures the ViewModel
        // gets the loaded Keychain value immediately.
        
        Log.debug("SecureCreditStore: Local state updated (Credits: \(state.credits))")
    }
    
    private func saveState() async throws {
        let trackingID = UUID().uuidString.prefix(4) // Short ID for tracking
            Log.debug("💾 SAVE QUEUED [\(trackingID)]: Current Mem Credits: \(self.credits), Premium: \(self.premiumDestinationsUnlocked)")
        
        isSyncing = true
        
        // Identify this specific operation
        let operationID = UUID()
        self.lastSaveOperationID = operationID
        
        // Capture the previous link in the chain
        let previousTask = pendingSaveTask
        
        // Create the new task and assign it to the chain
        // Make sure the Task runs on the @MainActor so it can safely read `self.currentState`
        let task: Task<Void, Error> = Task { @MainActor in
            Log.debug("💾 SAVE STARTING [\(trackingID)]: Waiting for queue...")
            
            defer {
                // Only clear the busy flag if WE are the last operation
                if self.lastSaveOperationID == operationID {
                    self.isSyncing = false
                }
            }
            
            // Wait for the previous save to finish (success or failure)
            // We ignore errors from previous tasks; we still want to try *our* save.
            _ = try? await previousTask?.value
            
            // CAPTURE STATE HERE (Just-In-Time)
            // If a previous task failed and rolled back, we will capture the corrected memory here.
            // This ensures that the disk always receives the most up-to-date memory state,
            // including any changes that happened while waiting in the queue
            let stateToSave = self.currentState
            Log.debug("💾 SAVE EXECUTING [\(trackingID)]: Capturing for Disk -> Credits: \(stateToSave.credits), Premium: \(stateToSave.premiumDestinationsUnlocked)")
            
            // Perform the actual write to Keychain
            let data = try JSONEncoder().encode(stateToSave)
            try await keychain.set(data, for: stateKey)
            Log.debug("💾 SAVE FINISHED [\(trackingID)]")
        }
        
        // Update the tail of the queue
        pendingSaveTask = task
        
        // Await the specific task we just created
        try await task.value
    }
    
    private func loadInitialState() async {
        // 1. Try to get data from Keychain
        guard let data = await keychain.get(stateKey) else {
            Log.debug("🔑 CreditStore: ℹ️ No historical state found in Keychain. Proceeding with system defaults.")
            self.apply(CreditStoreState()) // Explicitly apply defaults
            return
        }
        
        // 2. Try to decode the data
        do {
            let decoded = try JSONDecoder().decode(CreditStoreState.self, from: data)
            apply(decoded)
            Log.debug("🔑 CreditStore: Success. Context pulled from Keychain for [\(userId ?? "anonymous")].")
        } catch {
            Log.error("❌ CreditStore: Corrupted decoding for Keychain block: \(error.localizedDescription). Forging fresh structural fallback.")
            // If the data is corrupted or the format changed,
            // we apply a fresh state to keep the app functional.
            // Note: Future migration logic would go here
            apply(CreditStoreState())
        }
    }
}

extension SecureCreditStore {
    
    // MARK: - Sync from Firebase (The "Bank" update)
    
    /// Updates the store from external sources. Pass nil for values that should remain unchanged.
    func syncFromServer(
        credits: Int? = nil,
        premiumUnlocked: Bool? = nil,
        hasGrantedFreeCredits: Bool? = nil,
        hasPurchasedCredits: Bool? = nil
    ) async throws {
        Log.debug("""
            🔄 SYNC START: Mem(Credits: \(self.credits), Premium: \(self.premiumDestinationsUnlocked)) -> \
            Proposed(Credits: \(credits.map(String.init) ?? "nil"), \
            Premium: \(premiumUnlocked.map(String.init) ?? "nil"), \
            Gift: \(hasGrantedFreeCredits.map(String.init) ?? "nil"), \
            Purchased: \(hasPurchasedCredits.map(String.init) ?? "nil"))
            """)
        
        // Capture snapshots for potential rollback
        let previousPremium = self.premiumDestinationsUnlocked
        let previousGift = self.hasGrantedFreeCredits
        let previousPurchased = self.hasPurchasedCredits
        
        var creditDelta = 0
        var premiumChanged = false
        var giftChanged = false
        var purchasedChanged = false
        
        // Apply changes to memory immediately
        if let incomingCredits = credits, incomingCredits != self.credits {
            creditDelta = incomingCredits - self.credits
            self.credits = incomingCredits
            Log.debug("🔄 SYNC MEMORY UPDATED: credits is now \(incomingCredits)")
        }
        
        // 🔥 NEW ENTITLEMENT LOGIC: The "Direct Sync"
        if let incomingPremium = premiumUnlocked, incomingPremium != self.premiumDestinationsUnlocked {
            // We allow the change (true OR false) because the logic gate
            // is now handled by the SyncService layer.
            self.premiumDestinationsUnlocked = incomingPremium
            premiumChanged = true
            Log.debug("💾 Store: Premium status updated to \(incomingPremium) via Sync.")
        }
        
        if let incomingGift = hasGrantedFreeCredits, incomingGift != self.hasGrantedFreeCredits {
            self.hasGrantedFreeCredits = incomingGift
            giftChanged = true
            Log.debug("🎁 Store: Gift flag updated to \(incomingGift)")
        }
        
        if let incomingPurchased = hasPurchasedCredits {
            // Only flip to true if it isn't already.
            // We never want server sync to "revoke" their purchaser status.
            if incomingPurchased == true && !self.hasPurchasedCredits {
                self.hasPurchasedCredits = true
                purchasedChanged = true
                Log.debug("🛍️ Store: Purchaser status UNLOCKED via Server Sync.")
            }
        }
        
        // TODO: Also update hasPurchasedCredits if incomingCredits > 0 ?
        
        // Check if anything actually happened
        guard (creditDelta != 0) || premiumChanged || giftChanged || purchasedChanged else {
            Log.debug("😴 Sync: No changes detected. Skipping save.")
            return
        }
        
        do {
            try await saveState()
            Log.debug("SecureCreditStore: Synced with Server Truth.")
        } catch {
            // RELATIVE ROLLBACK
            // We only revert the specific fields this function touched.
            
            if creditDelta != 0 { self.credits -= creditDelta }
            if premiumChanged { self.premiumDestinationsUnlocked = previousPremium }
            if giftChanged { self.hasGrantedFreeCredits = previousGift }
            if purchasedChanged { self.hasPurchasedCredits = previousPurchased }
            
            Log.error("SecureCreditStore: Sync failed. Relative rollback applied.")
            throw error
        }
    }
}

#if DEBUG
extension SecureCreditStore {
    func debug_resetToZero() async {
        await waitForInitialization()
        _ = try? await pendingSaveTask?.value
        
        isSyncing = true
        defer { isSyncing = false }
        
        // 1. Wipe Keychain
        await keychain.delete(stateKey)
        
        // 2. Apply a state that has 0 credits AND marks free credits as already granted
        var zeroState = CreditStoreState()
        zeroState.credits = 0
        zeroState.hasGrantedFreeCredits = true // This prevents the auto-grant in initialize()
        
        apply(zeroState)
        Log.debug("🔑 CreditStore: 🛠️ Debug resetToZero() applied.")
    }
}
#endif

//struct CreditStoreState: Codable {
//    var version: Int = 1
//    var credits: Int = 0
//    var processedTransactionIDs: Set<UInt64> = []
//    var premiumDestinationsUnlocked: Bool = false
//    var hasPurchasedCredits: Bool = false
//    var hasGrantedFreeCredits: Bool = false
//}
