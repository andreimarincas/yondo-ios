//
//  FirebaseAIClient+Debug.swift
//  Yondo
//
//  Created by Andrei Marincas on 09.04.2026.
//

import Foundation
import FirebaseFunctions

#if DEBUG
extension FirebaseAIClient {
    func simulateDebugScenarioIfNeeded(for request: GenerateAISceneRequest) async throws {
        // Access DebugManager on the MainActor
        guard let scenario = await MainActor.run(body: { DebugManager.shared.activeScenario }) else {
            return
        }
        
        Log.debug("🐞 DEBUG: Scenario [\(scenario.rawValue)] detected. Simulating 1s delay...")
        
        // 1. Artificial network delay
        try await Task.sleep(for: .seconds(3))
        
        // 2. Prepare the error data
        let errorCode: String
        var details: [String: Any] = [:]
        
        switch scenario {
        case .slowCreditWebhook, .ghostCredit:
            errorCode = YondoRemoteError.insufficientCredits.rawValue
            
        case .slowPremiumWebhook, .failedPremiumSync:
            errorCode = YondoRemoteError.premiumRequired.rawValue
            // Extract destination from the request so the error UI is accurate
            details["destinationName"] = request.config.destination?.title
        }
        
        details["code"] = errorCode
        details["message"] = "DEBUG: Simulated server rejection (\(errorCode))"
        
        // 3. Throw the specific NSError that FirebaseErrorParser expects
        throw NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.internal.rawValue,
            userInfo: ["details": details]
        )
    }
}
#endif
