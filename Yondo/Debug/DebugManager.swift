//
//  DebugManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.04.2026.
//

#if DEBUG
import Foundation
import SwiftUI
import Combine

enum DebugScenario: String, CaseIterable, Identifiable {
    case slowCreditWebhook = "Slow Credit Webhook (Resolves to Success)"
    case ghostCredit = "Ghost Credit (Resolves to 0 / Paywall)"
    case slowPremiumWebhook = "Slow Premium Webhook (Resolves to Unlocked)"
    case failedPremiumSync = "Failed Premium Sync (Shows Paywall)"
    
    var id: String { self.rawValue }
}

@MainActor
final class DebugManager: ObservableObject {
    static let shared = DebugManager()
    @Published var activeScenario: DebugScenario?
    
    private init() {}
    
    // MARK: - Economy Forgery
    
    /// Modifies wallet snapshots to test the Anti-Dip Shield and Credit Buffering.
    func applyEconomyScenario(to data: inout [String: Any]) {
        guard let scenario = activeScenario else { return }
        Log.debug("🐞 Debug: Forging Economy data for [\(scenario.rawValue)]")
        
        // Extract what the server actually thinks
        let incomingCredits = data["credits"] as? Int ?? 0
        
        switch scenario {
        case .slowCreditWebhook:
            // Simulate that the webhook FINALLY arrived.
            // We ensure credits > 0 so the UI heals and allows generation.
            if incomingCredits > 0 {
                // ✅ SUCCESS: The server already has credits (like the '2' in your logs).
                // We do NOTHING. This allows the Evaluator to trust the real cloud truth.
                Log.debug("🐞 Debug: Server has \(incomingCredits) credits. Trusting cloud truth.")
            } else {
                // 🔄 SIMULATED SUCCESS: The server is still at 0 (webhook hasn't landed).
                // We forge a '3' to simulate the webhook finally arriving,
                // allowing the UI to finish its healing animation.
                data["credits"] = 3
                Log.debug("🐞 Debug: Server is 0. Forging '3' to resolve simulation.")
            }
            
        case .ghostCredit:
            // Force credits to 0 to test how the UI handles a sync that kills "Ghost Credits".
            data["credits"] = 0
            Log.debug("🐞 Debug [Economy]: Forged zero-balance (Ghost Credit Killer)")
            
        default:
            // Identity scenarios don't affect the Economy evaluator.
            break
        }
    }
    
    // MARK: - Identity Forgery
    
    /// Modifies user snapshots to test Sticky Success and Premium Buffering.
    func applyIdentityScenario(to data: inout [String: Any]) {
        guard let scenario = activeScenario else { return }
        Log.debug("🐞 Debug: Forging Identity data for [\(scenario.rawValue)]")
        
        switch scenario {
        case .slowPremiumWebhook:
            // Force premium to true to simulate a successful IAP sync.
            data["isPremium"] = true
            Log.debug("🐞 Debug [Identity]: Forged Premium = TRUE")
            
        case .failedPremiumSync:
            // Force premium to false to test if the "Sticky Shield" correctly ignores it.
            data["isPremium"] = false
            Log.debug("🐞 Debug [Identity]: Forged Premium = FALSE (Testing Sticky Shield)")
            
        default:
            // Economy scenarios don't affect the Identity evaluator.
            break
        }
    }
}
#endif
