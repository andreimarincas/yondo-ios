//
//  FirebaseSyncService.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

@MainActor
/**
 * @service Firebase Sync Service (The Dispatcher)
 * ARCHITECTURAL ROLE:
 * This is a Facade that manages the connection to Firestore. It coordinates two
 * distinct listeners (Identity and Economy) and dispatches incoming snapshots
 * to specialized Evaluators.
 *
 * DOMAIN SPLIT:
 * 1. Identity: root `users/{uid}` (Premium status, gifts)
 * 2. Economy: `users/{uid}/wallet/status` (Credits, purchase history)
 */
class FirebaseSyncService {
    static let shared = FirebaseSyncService()
    
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var currentUserId: String?
    
    // Dependencies (The Brains)
    private let identityEvaluator = IdentityEvaluator()
    private let economyEvaluator = EconomyEvaluator()
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Starts real-time listeners for both Identity and Economy domains.
    func startSync(for userId: String) {
        stopSync()
        self.currentUserId = userId
        
        Log.debug("🛰️ SyncService: Initializing dual-domain sync for [\(userId)]")
        
        // 1. Identity Listener (Root User Doc)
        let userSub = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snap, err in
                Task { [weak self] in
                    await self?.handle(snap, err, for: userId, label: "Identity", with: self?.identityEvaluator)
                }
            }
            
        // 2. Economy Listener (Wallet Subcollection)
        let walletSub = db.collection("users").document(userId).collection("wallet").document("status")
            .addSnapshotListener { [weak self] snap, err in
                Task { [weak self] in
                    await self?.handle(snap, err, for: userId, label: "Economy", with: self?.economyEvaluator)
                }
            }
            
        listeners.append(contentsOf: [userSub, walletSub])
    }
    
    func stopSync() {
        if !listeners.isEmpty {
            Log.debug("🛰️ SyncService: Tearing down \(listeners.count) active listeners.")
            listeners.forEach { $0.remove() }
            listeners.removeAll()
        }
        
        // Tell evaluators to clear their internal buffers/timers
        identityEvaluator.buffer.clear()
        economyEvaluator.buffer.clear()
        
        currentUserId = nil
    }
    
    // MARK: - Handlers
    
    private func handle(_ snap: DocumentSnapshot?, _ err: Error?, for userId: String, label: String, with evaluator: SyncEvaluator?) async {
        if let error = err {
            Log.error("❌ Sync [\(label)]: \(error.localizedDescription)")
            return
        }
        
        guard let data = snap?.data() else {
            Log.debug("🛰️ Sync [\(label)]: ℹ️ Document is empty/missing.")
            return
        }
        
        // Ignore local cache echoes to ensure we only react to server-side truth.
        guard snap?.metadata.isFromCache == false else {
            Log.debug("🛰️ Sync [\(label)]: 🛡️ Ignoring local cache echo.")
            return
        }
        
        Log.debug("🛰️ Sync [\(label)]: Snapshot received. Dispatching to evaluator.")
        do {
            try await evaluator?.evaluate(data: data, for: userId, force: false)
        } catch {
            Log.error("❌ Sync [\(label)]: Evaluation failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - The Exorcist (Forced Refresh)
    
    /// Bypasses the local cache and forces a direct fetch from the Firestore server.
    /// This is used by the "Sync Healer" UI to resolve ghost credits.
    func forceRefreshFromCloud() async {
        guard let userId = currentUserId else { return }
        Log.debug("🛰️ SyncService: ⚡️ Initiating forced cloud refresh for Identity & Economy...")
        
        do {
            // Fetch both documents concurrently
            async let identityDoc = db.collection("users").document(userId).getDocument(source: .server)
            
            async let economyDoc = db.collection("users").document(userId)
                .collection("wallet").document("status").getDocument(source: .server)
            
            let (iSnap, eSnap) = try await (identityDoc, economyDoc)
            
            if let iData = iSnap.data() {
                try await identityEvaluator.evaluate(data: iData, for: userId, force: true)
            }
            
            if let eData = eSnap.data() {
                try await economyEvaluator.evaluate(data: eData, for: userId, force: true)
            }
            
            Log.debug("✅ SyncService: Forced refresh complete.")
        } catch {
            Log.error("❌ SyncService: Forced refresh failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - The Healer (Firebase Functions)

extension FirebaseSyncService: SyncService {
    /// Asks the server to verify RevenueCat status directly.
    /// This is a "heavy" operation used when webhooks are delayed.
    func verifyPremiumWithServer(allowDowngrade: Bool = false) async throws -> Bool {
        let functions = Functions.functions(region: "us-central1")
        Log.debug("🔄 SyncService: Requesting server-side RevenueCat verification...")
        
        do {
            let result = try await functions.httpsCallable("checkSubscriptionStatus").call()
            
            // 1. AMBIGUOUS STATE (Null/404)
            // Server doesn't know, so we don't change our local truth.
            guard let data = result.data as? [String: Any],
                  let isPremium = data["isPremium"] as? Bool else {
                Log.debug("⚠️ Server returned null. Preserving local state.")
                // Fallback to local truth
                return IAPManager.shared.creditStore.premiumDestinationsUnlocked
            }
            
            // 2. DEFINITIVE STATE (True or False)
            // If we got an answer, push it through the evaluator with 'force: allowDowngrade'
            // to bypass the Sticky Success shield.
            if let userId = currentUserId {
                // THE BRIDGE:
                // allowDowngrade == true  -> force == true  (Accepts revocation)
                // allowDowngrade == false -> force == false (Sticky Success blocks revocation)
                try await identityEvaluator.evaluate(data: data, for: userId, force: allowDowngrade)
            }
            
            return isPremium
        } catch {
            // 3. HARD NETWORK/SERVER ERROR
            Log.error("❌ Network/Function error: \(error.localizedDescription)")
            
            // Throwing here is better for Sync Healing.
            // It tells the caller: "We couldn't even reach the healer."
            throw error
        }
    }
    
    func flushBuffers() async {
        guard let userId = currentUserId else { return }
        Log.debug("🧹 SyncService: Manually flushing all domain buffers for [\(userId)]")
        
        await identityEvaluator.flushBuffer(for: userId)
        await economyEvaluator.flushBuffer(for: userId)
    }
}
