//
//  APIClientProtocol.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import Foundation

/// A protocol that abstracts a network client capable of performing URLRequests with optional caching support.
protocol APIClientProtocol: Sendable {
    /// Performs a network request asynchronously.
    ///
    /// - Parameters:
    ///   - request: The URLRequest to be performed.
    ///   - cacheKey: An optional string representing the cache key for the request.
    /// - Returns: The data returned from the network request.
    /// - Throws: An error if the request fails.
    func perform(request: URLRequest, cacheKey: String?) async throws -> Data
}

extension APIClientProtocol {
    /// Constructs a cache key for the given request and optional prompt.
    ///
    /// The cache key is built by concatenating the request URL string, the HTTP body if present,
    /// and an optional prompt string. This is intended for DEBUG / development caching purposes.
    ///
    /// - Parameters:
    ///   - request: The URLRequest for which to generate the cache key.
    ///   - prompt: An optional prompt string to include in the cache key.
    /// - Returns: A string representing the cache key.
    func cacheKey(for request: URLRequest, prompt: String? = nil) -> String {
        // Start with the request URL string
        var key = request.url?.absoluteString ?? ""
        
        // Include HTTP body if present
        if let body = request.httpBody {
            // Append the HTTP body as a UTF-8 string
            key += String(data: body, encoding: .utf8) ?? ""
        }
        
        // Include prompt if provided
        if let prompt = prompt {
            // Append the prompt string
            key += prompt
        }
        
        return key
    }
}
