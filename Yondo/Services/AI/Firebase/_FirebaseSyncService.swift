//
//  _FirebaseSyncService.swift
//  Yondo
//
//  Created by Andrei Marincas on 18.03.2026.
//

#if DEBUG

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
/**
 * @service Firebase Sync Listener
 * ARCHITECTURAL ROLE: The "Sticky" Guard.
 * * IMPLEMENTATION:
 * This service implements "Passive Revocation Blocking." It allows Firestore to
 * turn Premium ON at any time, but explicitly prevents it from turning it OFF
 * during passive snapshots.
 * * REVOCATION POLICY:
 * Only a 'forced' sync (from the Healer or Manual Refresh) can downgrade the user.
 */
class _FirebaseSyncService {
    static let shared = _FirebaseSyncService()
    
    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?
    
    // THE HOLDING PEN: If a sync arrives while purchasing, we cache it here
    private var pendingDataBuffer: [String: Any]?
    private var currentUserId: String?
    
    private var pendingReconcileTask: Task<Void, Never>?
    private var pendingReconcileToken: UUID?
    
    /// When true, the Anti-Dip Shield allows credits to decrease even within the 90s window.
    private var isShieldBypassed = false
    
    // Tracks active API calls
    private var activeTransactionIDs = Set<UUID>()
    
    private init() {}
    
    /// Starts a real-time listener for the specific user's document.
    func startSync(for userId: String) {
        // Clean up any existing listener first
        stopSync()
        self.currentUserId = userId
        
        Log.debug("🛰️ SyncService: Attaching snapshot listener for user [\(userId)]")
        
        userListener = db.collection("users").document(userId)
            .addSnapshotListener { snapshot, error in
                Log.debug("🛰️ SyncService: addSnapshotListener triggered for [\(userId)]")
                
                if let error = error {
                    Log.error("❌ SyncService: Firestore listener encountered error: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    Log.error("❌ SyncService: Yielded snapshot is nil for [\(userId)]")
                    return
                }
                
                guard let data = snapshot.data() else {
                    Log.debug("🛰️ SyncService: ℹ️ No Firestore document found (User may be new or doc not created yet).")
                    return
                }
                
                // If a snapshot comes from the local cache, ignore it
                if snapshot.metadata.isFromCache == true {
                    Log.debug("🛰️ SyncService: 🛡️ Ignoring local Firestore cache bounce. Waiting for server-side truth.")
                    return
                }
                
                self.evaluateIncomingData(data, for: userId)
            }
    }
    
    private func evaluateIncomingData(_ data: [String: Any], for userId: String, force: Bool = false) {
        var data = data
        
#if DEBUG
            // 🐞 Inject debug state if a scenario is active
            applyDebugScenario(to: &data)
#endif
        
        let credits = data["credits"] as? Int
        let isPremiumFromServer = data["isPremium"] as? Bool
        let gift = data["hasGrantedFreeCredits"] as? Bool
        let purchased = data["hasPurchasedCredits"] as? Bool
        
        // Decide if we should even consider the premium status from this snapshot.
        var isPremium: Bool? = nil
        
        if let incomingPremium = isPremiumFromServer {
            if incomingPremium == true {
                // Passive snapshots are ALWAYS allowed to turn premium ON
                isPremium = true
            } else if force {
                // Passive snapshots are BLOCKED from turning premium OFF.
                // We only allow a 'false' if the call was forced (manual refresh?)
                isPremium = false
                Log.debug("🛰️ Sync: Server revocation (false) accepted because force == true.")
            } else {
                // 🛡️ STICKY SUCCESS SHIELD:
                // We ignore passive 'false' updates to prevent UI flickering during
                // transient network errors or slow webhook propagation.
                // Access is only revoked during a high-intent 'force' sync (Healer).
                Log.debug("🛡️ Sync: Server revocation (false) ignored for passive snapshot.")
            }
        }
        
        Log.debug("🛰️ SyncService: 🔍 Evaluating incoming payload for [\(userId)]. Credits: \(credits ?? 0), Premium: \(isPremium == nil ? "Ignored/NoChange" : "\(isPremium!)")")
        
        Task { @MainActor in
            let store = IAPManager.shared.creditStore
            
            // 🛡️ THE TRANSACTION SHIELD
            // If an AI generation is in flight, we freeze everything.
            if isTransactionShieldActive && !force {
                Log.debug("🔒 Sync Shield: AI Transaction in progress. Hard-buffering all data.")
                self.pendingDataBuffer = data
                // Safety net: 45s (Image takes 30s, give it some breathing room)
                scheduleReconcile(for: userId, delay: 45)
                return // Stop here. Do not even look at the dip shield.
            }
            
            let lastPurchase = IAPManager.shared.lastPurchaseDate ?? .distantPast
            let wasRecent = Date().timeIntervalSince(lastPurchase) < 90
            let isPurchaseWindow = wasRecent || IAPManager.shared.isEconomyUIActive
            let isDip = (credits ?? 0) < store.credits
            let shouldShieldDip = isPurchaseWindow && !isShieldBypassed && !force
            
            Log.debug("🛰️ Sync: Comparing Server(\(credits ?? 0)) vs Local(\(store.credits)). Shield Active: \(isTransactionShieldActive)")
            
            // 🛡️ ANTI-DIP SHIELD:
            // If the user just bought credits, and the server tries to
            // set our balance LOWER than what we currently have locally,
            // we assume the server is stale and DISCARD the update.
            if isDip && shouldShieldDip {
                Log.debug("🛡️ Dip Shield: Dropping stale server update (\(credits ?? 0) < \(store.credits)) during recent purchase window.")
                
                // 💡 Save the shielded data into the holding pen so the healer can use it later!
                self.pendingDataBuffer = data
                
                // 💡 SELF-HEAL: Schedule a reconcile for when the window expires
                let remaining = 91 - Date().timeIntervalSince(lastPurchase)
                scheduleReconcile(for: userId, delay: remaining)
                
                return // FULL STOP
            }
            
            // ✅ GREEN LIGHT: Apply the entire document
            Log.debug("🛰️ Sync: All shields passed. Applying full server truth.")
            
            // If we are letting data through, reset the bypass
            if isShieldBypassed {
                Log.debug("🛡️ SyncService: Bypass used and reset.")
                isShieldBypassed = false
            }
            
            // Server caught up! We can cancel any pending "forced" reconcile.
            pendingReconcileTask?.cancel()
            pendingReconcileToken = nil
            
            do {
                // We check the store's current ID to ensure we aren't
                // overwriting data during a logout/login transition.
                if store.userId == userId {
                    Log.debug("🛰️ SyncService: 💾 Committing verified sync payload to local CreditStore identity.")
                    try await store.syncFromServer(
                        credits: credits,
                        premiumUnlocked: isPremium,
                        hasGrantedFreeCredits: gift,
                        hasPurchasedCredits: purchased
                    )
                    Log.debug("✅ Sync Success: Local Store now at \(store.credits) credits. (ID: \(userId))")
                } else {
                    Log.error("❌ SyncService: ⚠️ Identity mismatch. Sync payload for [\(userId)] dropped because local store identity is [\(store.userId ?? "nil")].")
                }
            } catch {
                Log.error("❌ SyncService: 💥 Failed to push sync to CreditStore: \(error.localizedDescription)")
            }
        }
    }
    
    /// Called when the IAPManager finishes the purchase and clears `purchasingProductID`.
    func flushBufferedSync() {
        guard let userId = currentUserId, let bufferedData = pendingDataBuffer else {
            Log.debug("🛰️ SyncService: ℹ️ flushBufferedSync() requested, but holding pen is empty.")
            return
        }
        
        // 🛡️ THE MASTER GATEKEEPER
        // We only flush if NO sensitive operations are happening.
        guard !IAPManager.shared.isEconomyUIActive, !isTransactionShieldActive else {
            Log.debug("🛡️ Sync: Flush deferred. Either Economy UI or AI Transaction is still active.")
            return
        }
        
        Log.debug("⏰ SyncService: 🏁 All shields down. Safely flushing buffered snapshot.")
        
        // Clear the buffer and evaluate
        self.pendingDataBuffer = nil
        evaluateIncomingData(bufferedData, for: userId)
    }
    
    private func scheduleReconcile(for userId: String, delay: TimeInterval) {
        // Cancel any existing reconcile task; we only need the latest one
        pendingReconcileTask?.cancel()
        
        // Create a unique identity for THIS specific reconciliation attempt
        let token = UUID()
        self.pendingReconcileToken = token
        
        let newTask = Task {
            // Sleep until the window is guaranteed to be over, plus a tiny safety margin
            let safetyDelay = max(delay, 2.0) // 2s floor prevents rapid-fire loops
            try? await Task.sleep(for: .seconds(safetyDelay))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // 🎯 THE IDENTITY CHECK:
                // Only proceed if our token still matches the global one.
                // If a newer snapshot arrived, the token will have changed.
                guard self.pendingReconcileToken == token else {
                    Log.debug("🛰️ SyncService: Stale reconcile token. Newer task is active.")
                    return
                }
                
                // Check if the user is still the same before applying
                if self.currentUserId == userId, let data = self.pendingDataBuffer {
                    Log.debug("🛰️ SyncService: 🩹 Window expired. Applying previously shielded data.")
                    // We call evaluate again. Now wasRecent will be false,
                    // and the shield will let the data through.
                    self.evaluateIncomingData(data, for: userId)
                }
            }
        }
        
        self.pendingReconcileTask = newTask
    }
    
    /// Call this when the server returns an authoritative Insufficient Credits error.
    func forceBypassShield() {
        Log.debug("🛡️ SyncService: Shield Bypass ACTIVATED. Next update will ignore the 90s window.")
        self.isShieldBypassed = true
        flushBufferedSync()
    }
    
    /// Manually turn the shield back on (called if a timeout occurs)
    func resetBypassShield() {
        if self.isShieldBypassed {
            Log.debug("🛡️ SyncService: Shield Bypass manually RESET.")
            self.isShieldBypassed = false
            flushBufferedSync()
        }
    }
    
    func startTransactionShield() -> UUID {
        let id = UUID()
        activeTransactionIDs.insert(id)
        Log.debug("🔒 Transaction Shield ON [\(id)]. Active: \(activeTransactionIDs.count)")
        
        // ⏰ THE AUTO-RELEASE TIMER
        // If this ID is still in the set after 60s, remove it.
        Task {
            try? await Task.sleep(for: .seconds(60))
            
            if activeTransactionIDs.contains(id) {
                Log.error("🚨 Shield Timeout: Transaction [\(id)] took too long. Auto-releasing.")
                stopTransactionShield(id: id, wasSuccessful: false)
            }
        }
        
        return id
    }
    
    func stopTransactionShield(id: UUID?, wasSuccessful: Bool) {
        guard let id = id, activeTransactionIDs.contains(id) else { return }
        
        activeTransactionIDs.remove(id)
        Log.debug("🔓 Transaction Shield OFF [\(id)]. Success: \(wasSuccessful). Remaining: \(activeTransactionIDs.count)")
        
        // Only trigger the flush if this was the LAST active transaction
        if activeTransactionIDs.isEmpty {
            if wasSuccessful {
                // Even on success, evaluate the buffer instead of killing it.
                // This ensures that non-credit data (like a gift or premium status)
                // that arrived during the generation is preserved.
                Log.debug("🛰️ SyncService: All transactions done. Flushing buffer to catch concurrent updates.")
                self.flushBufferedSync()
            } else {
                Log.debug("🛰️ SyncService: Transaction failed/timed out. Flushing buffer.")
                self.flushBufferedSync()
            }
        }
    }
    
    var isTransactionShieldActive: Bool {
        return !activeTransactionIDs.isEmpty
    }
    
    /// Forces a direct fetch from the Firestore server, bypassing the local offline cache.
    /// This acts as the "Active Reality Check" to kill Ghost Credits if the passive listener fails.
    func forceRefreshFromCloud() async {
        guard let userId = currentUserId else {
            Log.error("🛰️ SyncService: Cannot force refresh, no current user ID.")
            return
        }
        
        Log.debug("🛰️ SyncService: ⚡️ Initiating forced refresh from cloud for [\(userId)]...")
        
        do {
            // THE EXORCIST: Force a network call, ignoring the local cache completely.
            let document = try await db.collection("users").document(userId).getDocument(source: .server)
            
            guard let data = document.data() else {
                Log.error("🛰️ SyncService: ❌ Forced refresh failed. Document is empty or missing.")
                return
            }
            
            // Purge the buffer. We just pulled the absolute latest state from the server,
            // so any buffered data we were holding onto is now officially stale.
            self.pendingDataBuffer = nil
            
            // Push the FULL payload through your standard evaluation pipeline.
            // This updates credits, premium, gifts, etc.
            self.evaluateIncomingData(data, for: userId, force: true)
            
        } catch {
            // If this fails (e.g., user lost internet exactly at the 8-second mark),
            // it will simply throw an error. The UI will stay in its current state
            // or the ViewModel's fallback logic will push it to the paywall.
            Log.error("🛰️ SyncService: ❌ Forced refresh from cloud failed: \(error.localizedDescription)")
        }
    }
    
    /// Stops the listener. Call this during logout.
    func stopSync() {
        if userListener != nil {
            Log.debug("🛰️ SyncService: 🛑 Tearing down active listener for user [\(currentUserId ?? "nil")].")
            userListener?.remove()
            userListener = nil
        }
        pendingReconcileTask?.cancel() // 🛑 Kill the healer
        pendingReconcileTask = nil
        pendingDataBuffer = nil
        currentUserId = nil
        Log.debug("_FirebaseSyncService: Listener stopped.")
    }
}

extension _FirebaseSyncService: SyncService {
    /// Forces the server to directly query RevenueCat and update Firestore.
    /// Use this as your "Healer" if the webhook is delayed.
    func verifyPremiumWithServer(allowDowngrade: Bool = false) async throws -> Bool {
        lazy var functions = Functions.functions(region: "us-central1")
        Log.debug("🔄 SyncService: Asking server to verify RevenueCat status...")
        
        do {
            let result = try await functions.httpsCallable("checkSubscriptionStatus").call()
            
            guard var data = result.data as? [String: Any] else {
                // Unexpected data format - treat as ambiguous
                return IAPManager.shared.creditStore.premiumDestinationsUnlocked
            }
            
#if DEBUG
            applyDebugScenario(to: &data)
#endif
            
            // 1. DEFINITIVE STATE (True or False)
            if let isPremium = data["isPremium"] as? Bool {
                // 🛡️ THE SHIELD:
                // If we found false, but downgrades are forbidden, just return the result
                // without touching the Store.
                if isPremium == false && !allowDowngrade {
                    Log.debug("🛡️ SyncService: Server said False, but downgrade is shielded. Returning False without writing to Store.")
                    return false
                }
                
                try await IAPManager.shared.creditStore.syncFromServer(premiumUnlocked: isPremium)
                return isPremium
            }
            
            // 2. AMBIGUOUS STATE (Null/404)
            // Server doesn't know, so we don't change our local truth.
            Log.debug("⚠️ Server returned null. Preserving local state.")
            return IAPManager.shared.creditStore.premiumDestinationsUnlocked
        } catch {
            // 3. HARD NETWORK/SERVER ERROR
            Log.error("❌ Network/Function error: \(error.localizedDescription)")
            
            // Throwing here is better for Sync Healing.
            // It tells the caller: "We couldn't even reach the healer."
            throw error
        }
    }
    
    func flushBuffers() async {
        flushBufferedSync()
    }
}

extension _FirebaseSyncService: SyncShielding {
    var isTransactionActive: Bool {
        isTransactionShieldActive
    }
    
    func startTransaction() -> UUID {
        startTransactionShield()
    }
    
    // TODO: wasSuccessful param?
    func stopTransaction(id: UUID?) {
        stopTransactionShield(id: id, wasSuccessful: true)
    }
    
    func forceBypass() {
        forceBypassShield()
    }
    
    func clearBypass() {
        resetBypassShield()
    }
    
    func resetAll() {
        activeTransactionIDs.removeAll()
        isShieldBypassed = false
    }
}

#endif
