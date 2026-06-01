//
//  APIClient.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import Foundation

/// Represents errors that can occur during API requests.
enum APIError: Error {
    /// The response received was invalid or could not be parsed.
    case invalidResponse
    /// The server responded with an error status code and optional body.
    case serverError(status: Int, body: String)
    /// The response body contains HTML, indicating an unexpected error page.
    case htmlError(String)
    /// The maximum number of retry attempts has been exceeded.
    case retryLimitExceeded
}

/// A retrying HTTP client with optional caching for API requests.
final class APIClient: APIClientProtocol {
    private let urlSession: URLSession
#if DEBUG
    private let cache: ResponseCache
    private let enableCaching: Bool
#endif
    private let maxAttempts: Int
    
    init(
        urlSession: URLSession = .shared,
        enableCaching: Bool = false,
        maxAttempts: Int = 3
    ) {
        self.urlSession = urlSession
        self.maxAttempts = maxAttempts
#if DEBUG
        self.enableCaching = enableCaching
        self.cache = ResponseCache()
#endif
    }
    
    /// Performs a request with retry, backoff, caching, and robust error handling.
    ///
    /// - Parameters:
    ///   - request: The URLRequest to perform.
    ///   - cacheKey: An optional cache key to use for caching the response.
    /// - Returns: The response data from the server or cache.
    /// - Throws: An error if the request fails after retries or an invalid response is received.
    func perform(request: URLRequest, cacheKey: String? = nil) async throws -> Data {
        Log.debug("Starting request to \(request.url?.absoluteString ?? "unknown URL"), attempt 1")
        
#if DEBUG
        if enableCaching {
            let key = cacheKey ?? self.cacheKey(for: request)
            if let cached = cache.get(forKey: key) {
                Log.debug("Returning cached response for key \(key)")
                // Artificial delay to simulate network latency
                //try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return cached
            }
        }
#endif
        
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                // Retryable server errors
                if [502, 503, 504].contains(httpResponse.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw APIError.serverError(
                        status: httpResponse.statusCode,
                        body: body
                    )
                }

                // Non-success responses
                guard (200...299).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw APIError.serverError(
                        status: httpResponse.statusCode,
                        body: body
                    )
                }

                // Cloudflare / HTML error pages
                if let bodyString = String(data: data, encoding: .utf8),
                   bodyString.lowercased().contains("<html") {
                    throw APIError.htmlError(bodyString)
                }
                
#if DEBUG
                if enableCaching {
                    let key = cacheKey ?? self.cacheKey(for: request)
                    cache.set(data, forKey: key)
                }
#endif
                
                Log.debug("Request succeeded with status code \(httpResponse.statusCode)")
                return data

            } catch {
                lastError = error

                Log.debug("Attempt \(attempt) failed with error: \(error)")

                // Exponential backoff
                if attempt < maxAttempts {
                    let delay = UInt64(attempt) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        Log.debug("Retry limit exceeded for request to \(request.url?.absoluteString ?? "unknown URL")")
        throw lastError ?? APIError.retryLimitExceeded
    }
}
