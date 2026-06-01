//
//  ResponseCache.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import Foundation
import CryptoKit

#if DEBUG
/// Simple file-based response cache for API responses.
/// Intended for DEBUG use only.
final class ResponseCache {
    private let cacheDirectory: URL

    init(subfolder: String = "APIResponseCache") {
        let fm = FileManager.default
        let baseURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = baseURL.appendingPathComponent(subfolder, isDirectory: true)
        
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func fileURL(forKey key: String) -> URL {
        // Make a safe filename from key (e.g., URL+body hash)
        let hashed = key.sha256()
        return cacheDirectory.appendingPathComponent(hashed)
    }
    
    /// Retrieves cached data for the given key.
    func get(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        Log.debug("ResponseCache get called for key: \(key)")
        return try? Data(contentsOf: url)
    }
    
    /// Caches the given data for the specified key.
    func set(_ data: Data, forKey key: String) {
        let url = fileURL(forKey: key)
        Log.debug("ResponseCache set called for key: \(key), size: \(data.count) bytes")
        try? data.write(to: url)
    }
}

private extension String {
    func sha256() -> String {
        // Simple SHA256 hash for filename
        guard let data = self.data(using: .utf8) else { return self }
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
#endif
