//
//  GenerationHistoryManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 10.01.2026.
//

import UIKit

/// Unique token for a generation task
struct GenerationToken: Identifiable, Hashable {
    let id = UUID()
}

/// Tracks a single AI image generation attempt
struct GenerationRecord: Identifiable {
    let id = UUID()
    let token: GenerationToken
    let config: SceneConfig
    let selfie: UIImage
    
    var image: UIImage?
    var saveError: ImageStoreError?
    var wasRefunded: Bool = false
    var isSaved: Bool  = false
}

extension GenerationRecord {
    init(token: GenerationToken, config: SceneConfig, selfie: UIImage) {
        self.token = token
        self.config = config
        self.selfie = selfie
    }
    
    var isDelivered: Bool {
        (image != nil) || isSaved
    }
    
    var isFinalized: Bool {
        isDelivered || wasRefunded
    }
}

@MainActor
/// Singleton manager that tracks all generation attempts
final class GenerationHistoryManager {
    static let shared = GenerationHistoryManager()
    
    private(set) var records: [GenerationToken: GenerationRecord] = [:]
    
    private init() {}
    
    @discardableResult
    /// Add a new generation record
    func addRecord(token: GenerationToken, config: SceneConfig, selfie: UIImage) -> GenerationRecord {
        let record = GenerationRecord(token: token, config: config, selfie: selfie)
        records[token] = record
        return record
    }
    
    /// Checks if a credit-consuming record exists for a specific task.
    func hasCommittedRecord(for token: GenerationToken) -> Bool {
        return records[token] != nil
    }
    
    func markImageGenerated(_ token: GenerationToken, image: UIImage) {
        guard var record = records[token], record.image == nil else { return }
        record.image = image
        records[token] = record
    }
    
    func markSaved(_ token: GenerationToken) {
        guard var record = records[token], !record.isSaved else { return }
        record.isSaved = true
        records[token] = record
    }
    
    /// Mark a generation as failed to save (transient or permanent)
    func markSaveError(_ token: GenerationToken, error: ImageStoreError) {
        guard var record = records[token] else { return }
        record.saveError = error
        records[token] = record
    }
    
    /// Refund credit if generation failed and was never delivered
    func refundIfUndelivered(_ token: GenerationToken, creditProvider: CreditProvider) async throws {
        guard var record = records[token],
              !record.wasRefunded,
              !record.isDelivered else { return }
        
        try await creditProvider.creditStore.addCredits(1)
        record.wasRefunded = true
        records[token] = record
        
        Log.debug("GenerationHistoryManager: Refunded 1 credit for token \(token.id)")
    }
    
    func cleanupIfFinalized(_ token: GenerationToken) {
        guard let record = records[token] else { return }
        if record.isFinalized {
            records.removeValue(forKey: token)
            Log.debug("Cleaned up generation record \(token)")
        }
    }
}
