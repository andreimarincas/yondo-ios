//
//  SceneGenerationService.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.04.2026.
//

import UIKit

/// The concrete implementation of the scene generation business logic.
/// This service acts as the orchestrator between the user's economy (credits),
/// the remote AI backend, and the local persistence layers (database and file system).
final class SceneGenerationService: SceneGenerationUseCase {
    private let generator: AIImageGenerator
    private let iapProvider: CreditProvider
    private let persistence: SceneGenerationPersistence
    private let imageStore: ImageStoring
    
    init(
        generator: AIImageGenerator,
        iapProvider: CreditProvider,
        persistence: SceneGenerationPersistence,
        imageStore: ImageStoring
    ) {
        self.generator = generator
        self.iapProvider = iapProvider
        self.persistence = persistence
        self.imageStore = imageStore
    }
    
    func generateScene(
        selfie: UIImage,
        config: SceneConfig,
        onStageChange: @escaping @MainActor @Sendable (SceneGenerationStage) -> Void
    ) async throws {
        // Establish the Domain Identity
        // This localID tracks the generation in the database independently of UI tokens.
        let localID = UUID()
        
        let isOnFreeCredits = iapProvider.creditStore.isRunningOnFreeCredits
        let shouldIncludeSecret = !isOnFreeCredits
        
        do {
            let userId = try await AuthManager.shared.ensureGlobalAuthentication()
            Log.debug("👤 Authenticated user with ID: \(userId)")
            
            persistence.savePendingState(localID: localID, userID: userId, config: config)
            
            // Economy: The Point of No Return
            try await iapProvider.consumeCredit()
            Log.debug("💳 [\(localID.uuidString.prefix(8))] Local Credit Consumed. Current balance: \(iapProvider.creditStore.credits)")
            
            onStageChange(.creditConsumed)
            
            // The AI Request
            Log.debug("🎬 Starting AI generation request")
            
            let request = SceneGenerationRequest(
                selfieImage: selfie,
                config: config,
                includeSecret: shouldIncludeSecret
            )
            
            let result = try await generator.generateScene(request: request)
            Log.debug("✅ AI generation completed. Remote ID: \(result.remoteIdentifier ?? "nil")")
            
            onStageChange(.imageReceived(result.generatedImage))
            
            // Remote Persistence
            // Link the local DB record to the remote Firebase references
            persistence.updateRemoteStatus(
                localID: localID,
                status: "completed",
                firebaseID: result.remoteIdentifier,
                storagePath: result.storagePath
            )
            
            // Local Disk Persistence
            // We use a nested do-catch here because a disk failure should NOT
            // abort the entire generation (which was already paid for and delivered).
            do {
                let entry = try await imageStore.saveWithRetryIgnoringCancellation(result.generatedImage)
                Log.debug("💾 Image saved successfully: \(entry.filename)")
                
                onStageChange(.localSaveSuccess(filename: entry.filename))
            } catch {
                Log.error("Failed to save image to disk, but generation was successful: \(error)")
                onStageChange(.localSaveFailed(error))
            }
        } catch {
            Log.error("❌ Generation failed: \(error.localizedDescription)")
            
            // Global Failure Recovery
            // If authentication, credit consumption, or the AI request fails,
            // we must update the database so this item doesn't hang in "pending" forever.
            persistence.updateRemoteStatus(localID: localID, status: "failed")
            
            // Rethrow so the ViewModel can trigger the economy refund safety net
            throw error
        }
    }
}
