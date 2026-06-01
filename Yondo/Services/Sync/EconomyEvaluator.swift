//
//  EconomyEvaluator.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation

@MainActor
/**
 * @class EconomyEvaluator
 * ARCHITECTURAL ROLE: The Wallet Guardian (Refactored for Projected Credits).
 * This class processes updates for the 'Economy' domain (credits and purchase history).
 * It is specifically designed to handle "Stale Dips" caused by delayed webhooks.
 * Instead of blocking updates during transactions, it subtracts active locks from
 * the server truth to maintain local optimistic consistency.
 */
final class EconomyEvaluator: SyncEvaluator {
    let name = "Economy"
    let buffer = SyncBufferManager()
    private let shield = SyncShieldManager.shared
    
    /**
     * Evaluates incoming economy data against local optimistic state.
     * * This method implements a "Protective Synchronizer" pattern:
     * 1. It calculates projected credits by subtracting active AI generation locks.
     * 2. It uses an 'Anti-Dip Shield' to detect and reject stale server data during IAP windows.
     * 3. It manages a buffer for passive updates while ensuring 'Force' updates prioritize data integrity.
     * * - Parameters:
     * - data: The raw dictionary snapshot received from the cloud provider.
     * - userId: The unique identifier for the user to whom this data belongs.
     * - force: If true, ignores the buffer delay to evaluate immediately (Sync Healing).
     * Note: Even when forced, stale dips during an IAP window are rejected to
     * preserve purchased local balance.
     */
    func evaluate(data: [String: Any], for userId: String, force: Bool) async throws {
        var data = data
        
        #if DEBUG
        // Allows the Debug UI to simulate ghost credits or slow webhooks
        DebugManager.shared.applyEconomyScenario(to: &data)
        #endif
        
        // 1. EXTRACT SERVER TRUTH
        let serverCredits = data["credits"] as? Int ?? 0
        let currentLocalCredits = IAPManager.shared.creditStore.credits
        
        // 2. CALCULATE PROJECTED CREDITS (Server - Active Locks)
        // We subtract the number of ongoing generations from the server balance.
        // This prevents the UI from jumping 'up' if the server hasn't processed
        // the local optimistic consumption yet.
        let activeLocks = shield.activeTransactionCount
        let projectedCredits = max(serverCredits - activeLocks, 0)
        
        Log.debug("💰 [Economy] Projection: Server(\(serverCredits)) - Locks(\(activeLocks)) = Projected(\(projectedCredits))")
        
        // 3. ANTI-DIP SHIELD (IAP Safety)
        // We buffer ONLY if the PROJECTED value is lower than current local credits
        // during the 90s purchase window.
        if shield.shouldShieldDip(incomingCredits: projectedCredits, currentCredits: currentLocalCredits) {
            if force {
                // HEALING CASE:
                // We reject this update because the server is currently untrustworthy.
                // We don't buffer because we are in a high-priority 'Force' flow.
                Log.debug("⚠️ [Economy] Rejected Stale Server Update: Server reported a dip during the IAP window. Preserving local truth.")
                return
            } else {
                // PASSIVE CASE:
                // Buffer the update so it eventually applies once the window expires.
                let delay = shield.timeUntilWindowExpires
                Log.debug("🛡️ [Economy] Shield: Stale Dip detected (\(currentLocalCredits) -> \(projectedCredits)). Holding for \(Int(delay))s.")
                
                buffer.hold(data, for: userId, delay: delay) { [weak self] in
                    Task { [weak self] in
                        await self?.flushBuffer(for: userId)
                    }
                }
                return
            }
        }
        
        // 4. THE CLEARING MOMENT
        // If we reached here, the server data is VALID (it's not a dip).
        // This means the server has caught up to our local reality.
        // We must kill any pending buffered updates to prevent "Delayed Poisoning."
        buffer.clear()
        
        // 5. PREPARE DATA FOR WRITE
        // We overwrite the raw server 'credits' with our projected credits.
        var finalData = data
        finalData["credits"] = projectedCredits
        
        // 6. COMMIT TO STORE
        do {
            try await writeToStore(data: finalData, for: userId)
            Log.debug("✅ [Economy] Sync: Balance updated. Local is now \(projectedCredits).")
        } catch {
            Log.error("❌ [Economy] Sync: Write failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func writeToStore(data: [String: Any], for userId: String) async throws {
        let store = IAPManager.shared.creditStore
        
        // IDENTITY GUARD: Never write if the active user changed during the buffer period.
        guard store.userId == userId else {
            Log.error("❌ [Economy]: User ID mismatch. Local: \(store.userId ?? "nil"), Sync: \(userId). Aborting write.")
            return
        }
        
        let credits = data["credits"] as? Int
        let purchased = data["hasPurchasedCredits"] as? Bool
        
        // Domain Split: We pass 'nil' for everything except Wallet fields.
        try await store.syncFromServer(
            credits: credits,
            premiumUnlocked: nil,
            hasGrantedFreeCredits: nil,
            hasPurchasedCredits: purchased
        )
    }
}
