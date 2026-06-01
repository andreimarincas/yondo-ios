//
//  ImageStoring.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.01.2026.
//

import UIKit

protocol ImageStoring: AnyObject {
    func save(image: UIImage, withId explicitID: UUID?) async throws -> GeneratedImage
    func loadFullImage(for entry: GeneratedImage) async -> UIImage?
    func loadThumbnail(for entry: GeneratedImage, allowGeneration: Bool, forceGeneration: Bool) async -> UIImage?
}

extension ImageStoring {
    @discardableResult
    /// Internal helper to allow retries on specific failures
    func saveWithRetry(_ image: UIImage, maxAttempts: Int, withId explicitID: UUID? = nil) async throws -> GeneratedImage {
        var lastError: Error?
        
        for i in 0..<maxAttempts {
            do {
                let entry = try await self.save(image: image, withId: explicitID)
                return entry
            } catch {
                // Check if the error is actually because the task was cancelled
                // internally (e.g. app shutting down), which we should respect.
                if error is CancellationError { throw error }
                
                lastError = error
                Log.debug("Save attempt \(i + 1) failed: \(error.localizedDescription)")
                
                // Only sleep if we have more attempts left
                if i < maxAttempts - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        
        if let error = lastError {
            throw ImageStoreError.saveFailed(error)
        } else {
            // This part is technically a fallback, though lastError
            // should always be set if the loop finishes without returning.
            throw ImageStoreError.encodingFailed
        }
    }
    
    @discardableResult
    func saveWithRetry(_ image: UIImage) async throws -> GeneratedImage {
        try await saveWithRetry(image, maxAttempts: 3)
    }
    
    @discardableResult
    func saveWithRetryIgnoringCancellation(_ image: UIImage) async throws -> GeneratedImage {
        try await Task.withExternalCancellationIgnored {
            try await self.saveWithRetry(image)
        }
    }
    
    func loadThumbnail(for entry: GeneratedImage) async -> UIImage? {
        await loadThumbnail(for: entry, allowGeneration: true, forceGeneration: false)
    }
}
