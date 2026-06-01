//
//  MockAIImageGenerator.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.01.2026.
//

//@testable import Yondo
import UIKit

@MainActor
class MockAIImageGenerator: AIImageGenerator {
    var shouldSucceed = true
    var generateCallCount = 0
    var duration: Duration = .seconds(2.0)
    
    // Allow setting a specific error code for testing different UI states
    var mockErrorCode: YondoRemoteError = .insufficientCredits
    var mockDestinationName: String? = "Mars Colony"
    
    func generateScene(request: SceneGenerationRequest) async throws -> SceneGenerationResult {
        // Simulate network/processing time so we have a window to cancel
        try await Task.sleep(for: duration)
        
        generateCallCount += 1
        
        if shouldSucceed {
            // Return a dummy image
            let image = UIImage.solidColor(.gray)
            return SceneGenerationResult(
                generatedImage: image,
                remoteIdentifier: "mock-remote-id",
                remoteURL: URL(string: "https://example.com/mock-image.jpg"),
                storagePath: "example.com/mock-image.jpg"
            )
        } else {
//            throw NSError(domain: "AIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI Failed"])
            
            // Construct the error to match Firebase's HttpsError structure
            // FirebaseErrorParser looks for nsError.userInfo["details"]
            let errorDetails: [String: Any] = [
                "code": mockErrorCode.rawValue,
                "message": "You don't have enough credits to generate this scene.",
                "destinationName": mockDestinationName as Any
            ]
            
            throw NSError(
                domain: "com.firebase.functions", // Match typical Firebase domain
                code: 3, // Usually 'INVALID_ARGUMENT' or similar in Firebase
                userInfo: ["details": errorDetails]
            )
        }
    }
}
