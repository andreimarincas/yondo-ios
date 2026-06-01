//
//  CreditProvider.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.01.2026.
//

import Foundation

@MainActor
protocol CreditProvider: AnyObject {
    
    var creditStore: SecureCreditStore { get }
    
    func consumeCredit() async throws
    
    func refreshEntitlements(force: Bool) async -> Bool
    
    var wasPurchaseMadeRecently: Bool { get }
}

// Make your real manager conform to it
extension IAPManager: CreditProvider {}
