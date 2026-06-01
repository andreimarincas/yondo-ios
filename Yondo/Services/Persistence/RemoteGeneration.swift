//
//  RemoteGeneration.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.03.2026.
//

import Foundation
import SwiftData

@Model
final class RemoteGeneration {
    // 🔗 This is the bridge to ImageStore's GeneratedImage.id
    @Attribute(.unique) var localID: UUID
    var userID: String
    
    // ☁️ Firebase Metadata
    var firebaseID: String?
    var storagePath: String?
    
    // 🚦 State Management
    var status: String // "pending", "processing", "completed", "failed"
    var createdAt: Date
    
    // 📝 Optional: Store the prompt/config used
    var destinationName: String?

    init(localID: UUID = UUID(), userID: String, status: String = "pending", destinationName: String? = nil) {
        self.localID = localID
        self.userID = userID
        self.status = status
        self.createdAt = Date()
        self.destinationName = destinationName
    }
}
