//
//  SceneGenerationPersistence.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.04.2026.
//

import Foundation
import SwiftData

@MainActor
protocol SceneGenerationPersistence {
    func savePendingState(localID: UUID, userID: String, config: SceneConfig)
    func updateRemoteStatus(localID: UUID, status: String, firebaseID: String?, storagePath: String?)
}

extension SceneGenerationPersistence {
    func updateRemoteStatus(localID: UUID, status: String) {
        updateRemoteStatus(localID: localID, status: status, firebaseID: nil, storagePath: nil)
    }
}

@MainActor
final class SceneGenerationPersistenceService: SceneGenerationPersistence {
    private let modelContainer: ModelContainer
    
    private var modelContext: ModelContext {
        Log.debug("⚡ About to access modelContainer.mainContext")
        let context = modelContainer.mainContext
        Log.debug("✅ modelContainer.mainContext accessed")
        return context
    }
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    func savePendingState(localID: UUID, userID: String, config: SceneConfig) {
        let remoteGen = RemoteGeneration(
            localID: localID,
            userID: userID,
            status: "processing",
            destinationName: config.destination?.title
        )
        modelContext.insert(remoteGen)
        try? modelContext.save()
    }
    
    func updateRemoteStatus(localID: UUID, status: String, firebaseID: String? = nil, storagePath: String? = nil) {
        let predicate = #Predicate<RemoteGeneration> { $0.localID == localID }
        let descriptor = FetchDescriptor<RemoteGeneration>(predicate: predicate)
        
        do {
            Log.debug("⚡ SwiftData: About to fetch record with localID [\(localID)]")
            let records = try modelContext.fetch(descriptor)
            Log.debug("✅ SwiftData: Fetch completed, found \(records.count) record(s) for localID [\(localID)]")
            if let record = records.first {
                record.status = status
                if let firebaseID { record.firebaseID = firebaseID }
                if let storagePath { record.storagePath = storagePath }
                
                // No need to manually save usually in SwiftData if autosave is on,
                // but explicitly calling it is safer here.
                try modelContext.save()
                
                Log.debug("💾 SwiftData: Updated record [\(localID)] to [\(status)].")
            } else {
                Log.error("❌ SwiftData: No record found for localID [\(localID)]. Update to [\(status)] failed.")
            }
        } catch {
            Log.error("SwiftData update failed: \(error)")
        }
    }
}
