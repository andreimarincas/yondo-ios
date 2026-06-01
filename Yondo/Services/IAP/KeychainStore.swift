//
//  KeychainStore.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.01.2026.
//

import Security
import Foundation

enum KeychainError: Error {
    case saveFailure(OSStatus)
    case unhandled(OSStatus)
}

/// A thread-safe, actor-based wrapper for the system Keychain.
/// Provides serialized access to prevent race conditions and ensures operations
/// run off the Main Thread to maintain UI responsiveness.
actor KeychainStore {
    static let shared = KeychainStore()
    private init() {}
    
    private let serviceIdentifier = Bundle.main.bundleIdentifier ?? "com.yondo.keychain"

    // MARK: - Public API

    /// Saves or updates data in the Keychain.
    /// - Parameters:
    ///   - data: The Data to persist.
    ///   - key: The unique account identifier for the item.
    func set(_ data: Data, for key: String) throws {
        // Identity Query: Used to find the specific item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceIdentifier
        ]

        // Attributes to update or add
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // 1. Try to update the existing item
        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if status == errSecItemNotFound {
            // 2. If it doesn't exist, create it (Query + Attributes)
            let addQuery = query.merging(attributesToUpdate) { $1 }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            
            if addStatus != errSecSuccess {
                Log.error("KeychainStore: Add failed for \(key) with status: \(addStatus)")
                throw KeychainError.saveFailure(addStatus)
            }
        } else if status != errSecSuccess {
            Log.error("KeychainStore: Update failed for \(key) with status: \(status)")
            throw KeychainError.saveFailure(status)
        }
    }

    /// Retrieves data from the Keychain.
    func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
    
    func exists(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceIdentifier,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true // Don't return data, just check attributes
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Removes an item from the Keychain.
    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // We only log if the error is something other than 'not found'
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.error("KeychainStore: Delete failed for \(key) with OSStatus: \(status)")
        }
    }
    
    /// Clears all generic password items for this app (use with caution).
    func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            Log.debug("KeychainStore: All items cleared.")
        }
    }
}
