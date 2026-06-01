//
//  IAPTypes.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.03.2026.
//

import Foundation

enum IAPServiceType {
    case storeKit   // Legacy: Local StoreKit 2 + Local Keychain
    case revenueCat // Modern: RevenueCat + Firebase + Local Keychain Cache
}

enum PurchaseResult {
    case success          // New credits or first-time unlock
    case alreadyVerified  // Collision / Already owned. Silent sync.
}
