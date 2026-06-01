//
//  YondoProduct.swift
//  Yondo
//
//  Created by Andrei Marincas on 18.03.2026.
//

import StoreKit
import RevenueCat

protocol YondoProduct {
    var id: String { get }
    var displayName: String { get }
    var displayDescription: String { get }
    var displayPrice: String { get }
    
    // Add this to bridge RevenueCat packages into the manager
    var rcPackage: RevenueCat.Package? { get }
}

// Extend StoreKit 2 Product
extension StoreKit.Product: YondoProduct {
//    var id: String { self.id }
//    var displayName: String { self.displayName }
    var displayDescription: String { self.description }
//    var displayPrice: String { self.displayFormat.format() }
//    var displayPrice: String { self.displayPrice }
    
    // StoreKit 2 doesn't have RC packages, so return nil
    var rcPackage: RevenueCat.Package? { nil }
}

// Extend RevenueCat StoreProduct
extension RevenueCat.StoreProduct: YondoProduct {
    var id: String { self.productIdentifier }
    var displayName: String { self.localizedTitle }
    var displayDescription: String { self.localizedDescription }
    var displayPrice: String { self.localizedPriceString }
    
    // StoreProduct alone doesn't hold the package reference,
    // so we return nil here; we'll handle the mapping in the fetch.
    var rcPackage: RevenueCat.Package? { nil }
}

// This allows us to store the whole Package in your products dictionary
extension RevenueCat.Package: YondoProduct {
    var id: String { self.storeProduct.productIdentifier }
    var displayName: String { self.storeProduct.localizedTitle }
    var displayDescription: String { self.storeProduct.localizedDescription }
    var displayPrice: String { self.storeProduct.localizedPriceString }
    var rcPackage: RevenueCat.Package? { self } // Returns itself!
}
