//
//  _FirebaseSyncService+Debug.swift
//  Yondo
//
//  Created by Andrei Marincas on 09.04.2026.
//

#if DEBUG
extension _FirebaseSyncService {
    /// Modifies the raw Firestore data to match the requirements of the active debug scenario.
    func applyDebugScenario(to data: inout [String: Any]) {
        // We can access DebugManager directly since we are on the @MainActor
        guard let scenario = DebugManager.shared.activeScenario else { return }
        
        Log.debug("🐞 SyncService: Forging cloud data for [\(scenario.rawValue)]")
        
        switch scenario {
        case .slowCreditWebhook:
            // Simulate that the webhook FINALLY arrived.
            // We ensure credits > 0 so the UI heals and allows generation.
            data["credits"] = max(data["credits"] as? Int ?? 0, 1)
            
        case .ghostCredit:
            // Simulate that the server confirms the user has 0 credits.
            // This will kill the local ghost credit and show the paywall.
            data["credits"] = 0
            
        case .slowPremiumWebhook:
            // Simulate that the premium flag finally synced to true.
            data["isPremium"] = true
            
        case .failedPremiumSync:
            // Simulate that the server still says false.
            data["isPremium"] = false
        }
    }
}
#endif
