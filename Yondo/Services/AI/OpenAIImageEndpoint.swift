//
//  OpenAIImageEndpoint.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import Foundation

/// Centralized definition of OpenAI image endpoints and defaults.
/// Intentionally no logging — used by higher-level networking code.
nonisolated enum OpenAIImageEndpoint: Sendable {

    // MARK: - Cases

    case editImage
    case generateImage

    // MARK: - URL

    var url: URL {
        switch self {
        case .editImage:
            return URL(string: "https://api.openai.com/v1/images/edits")!
        case .generateImage:
            return URL(string: "https://api.openai.com/v1/images/generations")!
        }
    }

    // MARK: - Model

    var model: String {
        switch self {
        case .editImage:
            return "gpt-image-1.5"
        case .generateImage:
            return "gpt-image-1.5"
        }
    }

    // MARK: - Capabilities / Defaults

    var supportsImageInput: Bool {
        switch self {
        case .editImage:
            return true
        case .generateImage:
            return false
        }
    }

    var defaultSize: String {
        "1024x1024"
    }
}
