//
//  FirebaseAIResultGenerator.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.03.2026.
//

import UIKit
import FirebaseFunctions
import FirebaseStorage

struct FirebaseAIResultGenerator: AIImageGenerator, Sendable {
    private let preprocessor = FirebaseImagePreprocessor()
    private let aiClient = FirebaseAIClient()
    
    func generateScene(request: SceneGenerationRequest) async throws -> SceneGenerationResult {
        // Ensure the user is logged in first
        // If this fails, it will throw an error before we even hit OpenAI
        let userId = try await AuthManager.shared.ensureGlobalAuthentication()
        Log.debug("👤 Authenticated as: \(userId)")
        
        // 1. Process the image (Resize and convert to JPEG)
        let jpegData = try preprocessor.prepareSelfie(request.selfieImage)
        let base64String = jpegData.base64EncodedString()
        
        // 2. Prepare the request
        let apiRequest = GenerateAISceneRequest(
            config: request.config,
            base64Selfie: base64String,
            includeSecret: request.includeSecret
        )
        
        do {
            // 3. Call Firebase
            let firebaseResponse = try await aiClient.generateScene(request: apiRequest)
            
            Log.debug("🚀 Firebase Success!")
            Log.debug("📸 Generated Image URL: \(firebaseResponse.imageUrl)")
            Log.debug("🆔 Firestore Doc ID: \(firebaseResponse.generationId)")
            
            // 4. Download the generated image using the Firebase Storage SDK
            let storage = Storage.storage()
            let storageRef = storage.reference().child(firebaseResponse.storagePath)
//            let storageRef = storage.reference(forURL: firebaseResponse.imageUrl)

            // We fetch the data directly (max 10MB)
            let imageData = try await storageRef.data(maxSize: 10 * 1024 * 1024)
            
            guard let uiImage = UIImage(data: imageData) else {
                throw SceneGenerationError.unknown(
                    NSError(domain: "AIImageGenerator",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to decode result image data."])
                )
            }
            
            // 5. Return a local result object for the UI to use
            let result = SceneGenerationResult(
                generatedImage: uiImage,
                remoteIdentifier: firebaseResponse.generationId,
                remoteURL: URL(string: firebaseResponse.imageUrl),
                storagePath: firebaseResponse.storagePath
            )
            
            return result
            
        } catch let error {
            // 1. Business Logic Check (Credits, Premium)
            // This MUST come first to handle the dictionary details
            if let remoteError = FirebaseErrorParser.parse(error) {
                switch remoteError.code {
                case .premiumRequired:
                    throw SceneGenerationError.requiresPremiumUnlock(destinationName: remoteError.destinationName)
                case .insufficientCredits:
                    throw SceneGenerationError.insufficientCredits
                case .aiGenFailed:
                    throw SceneGenerationError.aiBusy
                case .authRequired, .userNotFound, .invalidConfig:
                    throw SceneGenerationError.unknown(error)
                }
            }
            
            // 2. Handle specific system-level Firebase errors
            if let fError = error.asFunctionsError {
                switch fError.code {
                case .resourceExhausted:
                    throw SceneGenerationError.aiBusy
                case .deadlineExceeded, .unavailable:
                    throw SceneGenerationError.networkConnectionLost
                default:
                    // .unauthenticated or other system errors fall here
                    throw SceneGenerationError.unknown(error)
                }
            }
            
            // 3. Catch networking or storage errors (Offline, timeouts)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain || nsError.code == -1009 {
                throw SceneGenerationError.networkConnectionLost
            }
            
            // 4. Absolute fallback
            throw SceneGenerationError.unknown(error)
        }
    }
}

extension Error {
    var asFunctionsError: (code: FunctionsErrorCode, message: String)? {
        let nsError = self as NSError
        guard nsError.domain == FunctionsErrorDomain else { return nil }
        return (FunctionsErrorCode(rawValue: nsError.code) ?? .unknown, nsError.localizedDescription)
    }
}
