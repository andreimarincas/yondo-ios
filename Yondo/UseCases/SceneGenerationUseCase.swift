//
//  SceneGenerationUseCase.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.04.2026.
//

import UIKit

/// Defines the contract for generating AI scenes.
/// Implementing services are responsible for credit consumption, AI communication, and local persistence.
protocol SceneGenerationUseCase: Sendable {
    /// Executes the core AI generation request.
    ///
    /// This function handles the "Point of No Return." If it returns without throwing,
    /// the generation is considered a domain-level success, even if local saving fails.
    ///
    /// - Parameters:
    ///   - selfie: The user's input image.
    ///   - config: The configuration for the scene.
    ///   - onStageChange: A thread-safe callback executed on the Main Actor to update UI and local state.
    func generateScene(
        selfie: UIImage,
        config: SceneConfig,
        onStageChange: @escaping @MainActor @Sendable (SceneGenerationStage) -> Void
    ) async throws
}

/// Represents the granular milestones of the generation process.
enum SceneGenerationStage {
    /// The "Commitment Point." Credit has been successfully deducted and a pending record created.
    /// Use this to start UI loading animations or "message rotation."
    case creditConsumed
    
    /// The "Delivery Point." The AI has returned a valid image.
    /// This should be used to update the primary UI so the user isn't kept waiting for disk I/O.
    case imageReceived(UIImage)
    
    /// The "Persistence Point." The image is safely stored in the local file system.
    /// Use this to update history records or gallery thumbnails.
    case localSaveSuccess(filename: String)
    
    /// A "Non-Fatal Warning." The generation succeeded and was delivered to the UI,
    /// but the local disk save failed. The user should be warned that the image is "temporary."
    case localSaveFailed(Error)
}
