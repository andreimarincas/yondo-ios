//
//  SyncShieldManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation

@MainActor
/**
 * @class SyncShieldManager
 * ARCHITECTURAL ROLE: The Global Bouncer.
 * This singleton tracks the app's state to determine if incoming server data
 * is "safe" to apply. It manages two primary protections:
 * 1. Transaction Shield: Prevents UI shifts while the user is generating AI content.
 * 2. Anti-Dip Shield: Prevents stale server balances from overwriting recent IAPs.
 */
final class SyncShieldManager {
    static let shared = SyncShieldManager()
    
    /// When true, the Anti-Dip Shield is ignored (used for 'Insufficient Credit' errors).
    private var isShieldBypassed = false
    
    /// Tracks active AI generations to prevent credit/identity flickering during use.
    private var activeTransactionIDs = Set<UUID>()
    
    private init() {}
    
    // MARK: - Transaction Shield (AI Safety)
    
    var isTransactionActive: Bool {
        return !activeTransactionIDs.isEmpty
    }
    
    var activeTransactionCount: Int {
        return activeTransactionIDs.count
    }
    
    /**
     * Call this when starting a long-running AI task (e.g., Image Generation).
     * Returns a UUID that must be used to release the shield.
     */
    func startTransaction() -> UUID {
        let id = UUID()
        activeTransactionIDs.insert(id)
        Log.debug("🔒 Shield: Transaction START [\(id.uuidString.prefix(6))]. Active count: \(activeTransactionIDs.count)")
        
        // ⏰ FAILSAFE: Auto-release after 60s if the caller forgets.
        Task {
            try? await Task.sleep(for: .seconds(60))
            if activeTransactionIDs.contains(id) {
                Log.error("🚨 Shield: Transaction [\(id.uuidString.prefix(6))] timed out. Force-releasing.")
                stopTransaction(id: id)
            }
        }
        
        return id
    }
    
    func stopTransaction(id: UUID?) {
        guard let id = id, activeTransactionIDs.contains(id) else { return }
        activeTransactionIDs.remove(id)
        Log.debug("🔓 Shield: Transaction STOP [\(id.uuidString.prefix(6))]. Remaining: \(activeTransactionIDs.count)")
    }
    
    // MARK: - Anti-Dip Shield (IAP Safety)
    
    /// Forces the next sync to ignore the 90s purchase window.
    func forceBypass() {
        Log.debug("🛡️ Shield: Manual bypass ACTIVATED.")
        isShieldBypassed = true
    }
    
    // MARK: - For the Evaluators (The Logic Check)
    /// Checks if a bypass is active and resets it if true.
    /// This ensures a 'Force Bypass' only applies to the very next incoming update.
    func consumeBypass() -> Bool {
        let wasBypassed = isShieldBypassed
        if wasBypassed {
            isShieldBypassed = false
            Log.debug("🛡️ Shield: Bypass flag consumed and reset.")
        }
        return wasBypassed
    }
    
    /**
     * Determines if a credit update should be blocked because it looks like a "Stale Dip."
     * - Parameters:
     * - incomingCredits: The value from the Firestore snapshot.
     * - currentCredits: The value currently in the local Store.
     */
    func shouldShieldDip(incomingCredits: Int, currentCredits: Int) -> Bool {
        // 1. If we forced a bypass (e.g., after an error), let it through.
        if isShieldBypassed { return false }
        
        // 2. Identify if we are in a "Volatile Window" (Recent purchase or Store UI open).
        let lastPurchase = IAPManager.shared.lastPurchaseDate ?? .distantPast
        let wasRecent = Date().timeIntervalSince(lastPurchase) < 90
        let isPurchaseWindow = wasRecent || IAPManager.shared.isEconomyUIActive
        
        // 3. A 'Dip' is only dangerous if we are in that volatile window.
        let isDip = incomingCredits < currentCredits
        
        if isDip && isPurchaseWindow {
            Log.debug("🛡️ Shield: Dip detected (\(currentCredits) -> \(incomingCredits)). Blocking stale update.")
            return true
        }
        
        return false
    }
    
    /// Calculates the remaining wait time for the 90s RevenueCat window.
    var timeUntilWindowExpires: TimeInterval {
        let lastPurchase = IAPManager.shared.lastPurchaseDate ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastPurchase)
        // 91s adds a 1s buffer to ensure the webhook has definitely landed.
        return max(91 - elapsed, 2.0)
    }
    
    // MARK: - Cleanup
    
    /// Resets all shields. Call this on logout.
    func resetAll() {
        Log.debug("🛡️ Shield: Resetting all states (Logout/Teardown).")
        activeTransactionIDs.removeAll()
        isShieldBypassed = false
    }
}

extension SyncShieldManager: SyncShielding {
    // MARK: - For the UI / ViewModels (The Command)
    /// Manually closes the bypass gate.
    /// Use this when cancelling a task or finishing an error flow.
    func clearBypass() {
        if isShieldBypassed {
            Log.debug("🛡️ Shield: Bypass manually cleared.")
            isShieldBypassed = false
        }
    }
}
