//
//  IdentityEvaluator.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation

@MainActor
/**
 * @class IdentityEvaluator
 * ARCHITECTURAL ROLE: The Access Guardian.
 * This class processes updates for the 'Identity' domain (Premium status and free gifts).
 * It implements "Passive Revocation Blocking" (Sticky Success) to ensure users
 * don't lose access due to minor network latencies or stale snapshots, allowing
 * positive upgrades to flow through instantly.
 */
final class IdentityEvaluator: SyncEvaluator {
    let name = "Identity"
    let buffer = SyncBufferManager()
    
    /**
     * Evaluates incoming identity data to manage access and premium status.
     * * This method implements "Passive Revocation Blocking" (Sticky Success):
     * 1. Positive Upgrades: If the server grants Premium or a Gift, it is applied immediately.
     * 2. Passive Downgrades: If a passive sync (background) suggests a loss of Premium,
     * the update is ignored to prevent UI flickering or false-positive lockouts.
     * 3. Forced Revocation: If 'force' is true, the server's word is final, and access
     * can be revoked (used for manual refreshes or specific account resets).
     * * - Parameters:
     * - data: The raw dictionary snapshot received from the cloud provider.
     * - userId: The unique identifier for the user to whom this data belongs.
     * - force: If true, bypasses the "Sticky Success" filter and accepts the
     * server's status as absolute truth, even if it results in a revocation.
     */
    func evaluate(data: [String: Any], for userId: String, force: Bool) async throws {
        var data = data
        
        #if DEBUG
        // Allows for simulation of subscription expiration or gift behavior
        DebugManager.shared.applyIdentityScenario(to: &data)
        #endif
        
        // 1. STICKY SUCCESS LOGIC (Passive Revocation Blocking)
        // We no longer buffer identity updates during active transactions.
        // Positive upgrades (Premium/Gifts) should apply instantly.
        // Unwanted downgrades are naturally caught by the Sticky Success logic below.
        let isPremiumFromServer = data["isPremium"] as? Bool
        var resolvedPremium: Bool? = nil
        
        if let incoming = isPremiumFromServer {
            if incoming == true {
                // Server confirms Premium -> Accept immediately.
                resolvedPremium = true
            } else if force {
                // Server says NO, and we are FORCING (Healer/Manual) -> Accept revocation.
                Log.debug("🛰️ [Identity]: Premium revocation (false) accepted via forced sync.")
                resolvedPremium = false
            } else {
                // Server says NO, but this is a passive snapshot -> Ignore.
                // This is the "Sticky" part that prevents UI flickering mid-session.
                Log.debug("🛡️ [Identity] Shield: Sticky Success active. Ignoring passive revocation.")
                resolvedPremium = nil
            }
        }
        
        // 2. COMMIT TO STORE
        // We only prepare data that this domain "owns".
        var writeData: [String: Any] = [:]
        if let premium = resolvedPremium { writeData["isPremium"] = premium }
        if let gift = data["hasGrantedFreeCredits"] as? Bool { writeData["gift"] = gift }
        
        // Only trigger a write if we actually have data to update.
        guard !writeData.isEmpty else {
            Log.debug("ℹ️ [Identity]: No state changes required for [\(userId)].")
            return
        }
        
        // If we are about to write fresh truth, ensure no 'zombie'
        // updates are lingering in the pen.
        buffer.clear()
        
        do {
            try await writeToStore(data: writeData, for: userId)
        } catch {
            Log.error("❌ [Identity]: Write failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func writeToStore(data: [String: Any], for userId: String) async throws {
        let store = IAPManager.shared.creditStore
        
        // IDENTITY GUARD: Bulletproof check against cross-user pollution.
        guard store.userId == userId else {
            Log.error("❌ [Identity]: Identity mismatch. Sync for [\(userId)] blocked for local user [\(store.userId ?? "nil")].")
            return
        }
        
        // Domain Split: Explicitly pass nil for Economy fields.
        try await store.syncFromServer(
            credits: nil,
            premiumUnlocked: data["isPremium"] as? Bool,
            hasGrantedFreeCredits: data["gift"] as? Bool,
            hasPurchasedCredits: nil
        )
        
        Log.debug("✅ [Identity]: Access state synchronized for [\(userId)].")
    }
}
