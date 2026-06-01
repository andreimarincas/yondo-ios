//
//  Purchase.swift
//  Yondo
//
//  Created by Andrei Marincas on 31.12.2025.
//

import StoreKit

nonisolated enum PurchaseType: String, CaseIterable, Sendable {
    /// Consumable: 3-image pack
    case imagePack3
    /// Consumable: 10-image pack
    case imagePack10
    /// Consumable: 25-image pack
    case imagePack25
    /// Non-consumable: unlock all premium destinations
    case premiumDestinations
    
    /// The product identifier string associated with the purchase type.
    var productID: String {
        switch self {
        case .imagePack3:
            return "com.andreimarincas.yondo.images.3"
        case .imagePack10:
            return "com.andreimarincas.yondo.images.10"
        case .imagePack25:
            return "com.andreimarincas.yondo.images.25"
        case .premiumDestinations:
            return "com.andreimarincas.yondo.premiumDestinations"
        }
    }
    
    /// Returns the `PurchaseType` corresponding to the given product identifier string, if any.
    /// - Parameter productID: The product identifier string.
    /// - Returns: The matching `PurchaseType` or `nil` if no match is found.
    static func from(productID: String) -> PurchaseType? {
        return Self.allCases.first { $0.productID == productID }
    }
    
    /// Indicates whether the purchase type is consumable.
    var isConsumable: Bool {
        switch self {
        case .imagePack3, .imagePack10, .imagePack25:
            return true
        case .premiumDestinations:
            return false
        }
    }
    
    var creditsAmount: Int {
        switch self {
        case .imagePack3: return 3
        case .imagePack10: return 10
        case .imagePack25: return 25
        default: return 0
        }
    }
}

struct Purchase {
    let product: Product
    let type: PurchaseType
}

extension PurchaseType {
    /// The Entitlement ID as defined in the RevenueCat Dashboard.
    nonisolated var entitlementID: String? {
        switch self {
        case .premiumDestinations:
            return "premium_destinations" // Match this to your RC Dashboard
        default:
            return nil // Consumables don't have entitlements
        }
    }
}
