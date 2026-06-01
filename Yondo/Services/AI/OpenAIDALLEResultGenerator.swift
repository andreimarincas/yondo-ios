//
//  OpenAIDALLEResultGenerator.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.12.2025.
//

import UIKit
import Foundation

actor OpenAIDALLEResultGenerator: AIImageGenerator {
    private let apiKey: String
    private let apiClient: APIClientProtocol
    private let imagePreprocessor: ImagePreprocessing
    
    init(
        apiKey: String,
        apiClient: APIClientProtocol,
        imagePreprocessor: ImagePreprocessing
    ) {
        self.apiKey = apiKey
        self.apiClient = apiClient
        self.imagePreprocessor = imagePreprocessor
        Log.debug("OpenAIDALLEResultGenerator initialized")
    }
    
    func generateScene(request: SceneGenerationRequest) async throws -> SceneGenerationResult {
        Log.debug("generateScene started")
        let prompt = request.config.makePrompt(includeSecretViewpoints: request.includeSecret)
        Log.debug("Prompt built (secretViewpoints=\(request.includeSecret))")
        let imageData = try await imagePreprocessor.prepareSelfie(request.selfieImage)
        Log.debug("Selfie preprocessed (\(imageData.count) bytes)")
        let endpoint: OpenAIImageEndpoint = .editImage
        
        var form = MultipartFormBuilder()
        form.addField(name: "model", value: endpoint.model)
        form.addField(name: "prompt", value: prompt)
        form.addField(name: "size", value: endpoint.defaultSize)
        form.addFile(
            name: "image",
            filename: "selfie.png",
            contentType: "image/png",
            data: imageData
        )
        
        let body = form.build()
        let urlRequest = buildURLRequest(url: endpoint.url, body: body, contentType: form.contentTypeHeader)
        
        let cacheKeyPrompt = request.config.makePrompt(includeSecretViewpoints: request.includeSecret, includeSeed: false)
        let cacheKey = await apiClient.cacheKey(for: urlRequest, prompt: cacheKeyPrompt)
        Log.debug("Request cacheKey computed")
        let result = try await performRequest(urlRequest, cacheKey: cacheKey)
        Log.debug("generateScene completed successfully")
        return result
    }
    
    private func buildURLRequest(url: URL, body: Data, contentType: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
    
    private func performRequest(_ request: URLRequest, cacheKey: String? = nil) async throws -> SceneGenerationResult {
        Log.debug("performRequest started")
        let data = try await apiClient.perform(request: request, cacheKey: cacheKey)
        Log.debug("API request completed (\(data.count) bytes)")

        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard
            let response = json as? [String: Any],
            let dataArr = response["data"] as? [[String: Any]],
            let b64String = dataArr.first?["b64_json"] as? String,
            let imageData = Data(base64Encoded: b64String),
            let image = UIImage(data: imageData)
        else {
            Log.error("OpenAI response parse failed")
            throw NSError(
                domain: "AIImageGenerator",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI response"]
            )
        }
        Log.debug("Image decoded successfully")

        return SceneGenerationResult(
            generatedImage: image,
            remoteIdentifier: nil,
            remoteURL: nil,
            storagePath: nil
        )
    }
}
