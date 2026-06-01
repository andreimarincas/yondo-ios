//
//  CreditStore.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.01.2026.
//

import Combine

@MainActor
/// Protocol defining storage and management of user credits and premium unlocks.
protocol CreditStore: AnyObject {
    /// Current number of available credits (free or purchased)
    var credits: Int { get async }
    
    /// True if all premium destinations have been unlocked
    var premiumDestinationsUnlocked: Bool { get async }
    
    /// True if user has purchased credits
    var hasPurchasedCredits: Bool { get async }

    /// Add a number of credits to the store
    /// - Parameters:
    ///   - amount: Number of credits to add
    ///   - purchased: True if these credits were purchased, false if free/bonus
//    func addCredits(_ amount: Int, purchased: Bool) async
    func addCredits(_ amount: Int) async throws
    
    func addPurchase(credits amount: Int, transactionID: UInt64) async throws
    
    /// Consume a single credit if available
    /// - Returns: True if a credit was successfully consumed, false if none available
//    func consumeCredit() async -> Bool
    func consumeCredit() async throws

    /// Unlock all premium destinations permanently
//    func unlockPremiumDestinations() async
    func unlockPremiumDestinations(transactionID: UInt64) async throws
    
    /// Reset all credits and unlocks (debug / testing only)
    func resetAll() async // debug / testing
    
    var creditsPublisher: AnyPublisher<Int, Never> { get }
    
    var premiumPublisher: AnyPublisher<Bool, Never> { get }
}

// TODO: Consider having isRunningOnFreeCredits here on the CreditStore protocol instead of the concrete SecureCreditStore, but double check if it would break SwiftUI observability
//extension CreditStore {
//    func isRunningOnFreeCredits() async -> Bool {
//        let available = await credits
//        let purchased = await hasPurchasedCredits
//        return available > 0 && !purchased
//    }
//}
