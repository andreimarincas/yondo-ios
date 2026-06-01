//
//  Models.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.03.2026.
//

struct GenerateAISceneRequest: Encodable {
    let config: SceneConfig
    let base64Selfie: String
    let includeSecret: Bool
}

struct GenerateAISceneResponse: Decodable {
    let imageUrl: String
    let generationId: String
    let storagePath: String
}
