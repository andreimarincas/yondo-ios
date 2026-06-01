//
//  FirebaseAIClient.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.03.2026.
//

import FirebaseFunctions
import UIKit

final class FirebaseAIClient: Sendable {
    // Specify the region if you deployed to somewhere other than us-central1
    private let functions = Functions.functions(region: "us-central1")
    
    func generateScene(request: GenerateAISceneRequest) async throws -> GenerateAISceneResponse {
#if DEBUG
        // Check for debug interception
        try await simulateDebugScenarioIfNeeded(for: request)
#endif
        
        // Begin Background Task
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "GenerateAIScene") {
            // This closure is called if time runs out.
            // We don't need to do much here as the network call will likely just fail.
        }
        
        // Use a defer block to ensure the background task is ALWAYS ended,
        // whether the call succeeds, fails, or is cancelled.
        defer {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
        
        // 1. Call the function by the exact name we deployed
        let callable = functions.httpsCallable("generateAIScene")
        
        // Set the client to wait at least as long as the server (e.g., 300 seconds)
        callable.timeoutInterval = 310 // Slightly longer than server
        
        // 2. Use the new extension to convert the request
        let params = try request.asDictionary()
        
        // 3. Pass the dictionary to Firebase
        let result = try await callable.call(params)
        
        // 4. Decode the result into our Response struct
        // The Firebase SDK handles the JSON parsing internally
        guard let data = result.data as? [String: Any] else {
            throw NSError(domain: "FirebaseAIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        // 5. Map dictionary to our Decodable struct
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(GenerateAISceneResponse.self, from: jsonData)
    }
}

extension Encodable {
    /// Converts an Encodable object into a Dictionary for Firebase Functions.
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError(domain: "MappingError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not encode object to dictionary"])
        }
        return dictionary
    }
}
