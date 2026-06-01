//
//  RequestModel.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.12.2025.
//

import UIKit

/// Represents a request to generate a scene based on a user's selfie and configuration settings.
struct SceneGenerationRequest: Sendable {
    /// The user's captured selfie image used as the basis for scene generation.
    let selfieImage: UIImage
    /// Configuration settings for the scene including environment, mood, lighting, and camera parameters.
    let config: SceneConfig
    /// A flag indicating whether to include secret viewpoints in the generated scene.
    let includeSecret: Bool
}

/// Represents the result of a scene generation request, containing the generated image.
struct SceneGenerationResult: Sendable {
    /// The image generated from the scene generation process.
    let generatedImage: UIImage
    
    /// Optional: The remote storage metadata (only populated by Firebase)
    let remoteIdentifier: String? // The generationId
    let remoteURL: URL?           // The permanent storage URL
    let storagePath: String?
}

/// Represents a user's identity through a face embedding vector, conforming to Sendable for concurrency safety.
//struct UserIdentity: Sendable {
//    /// The face embedding vector representing the user's facial features.
//    let faceEmbedding: [Float]
//}
