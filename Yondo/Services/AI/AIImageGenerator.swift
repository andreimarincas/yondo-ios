//
//  AIImageGenerator.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.12.2025.
//

/// A protocol defining an interface for generating AI-based scene images.
protocol AIImageGenerator {
    /// Generates a scene image based on the provided generation request.
    ///
    /// - Parameter request: A `SceneGenerationRequest` containing parameters and specifications for the scene to be generated.
    /// - Returns: A `SceneGenerationResult` containing the generated scene image and related data.
    /// - Throws: An error if the scene generation process fails.
    func generateScene(request: SceneGenerationRequest) async throws -> SceneGenerationResult
}
