//
//  PurchaseProcessor+RevenueCat.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.03.2026.
//

import RevenueCat
import Foundation

extension PurchaseProcessor {
    func processRevenueCat(customerInfo: CustomerInfo, transaction: RevenueCat.StoreTransaction?, type: PurchaseType) async throws -> Bool {
        Log.debug("📦 RC PROCESSOR START: Product: \(type.productID), Transaction: \(transaction?.transactionIdentifier ?? "NIL (Recovery Mode)")")
        
        // 1. Determine the best Transaction ID available
        var stableID: String? = transaction?.transactionIdentifier
        
        // If we are in a 'Ghost' recovery (transaction is nil), find the most recent matching ID
        if stableID == nil {
            Log.debug("📦 RC PROCESSOR: No direct transaction, searching history for \(type.productID)...")
            stableID = customerInfo.nonSubscriptions
                .filter { $0.productIdentifier == type.productID }
                .sorted { $0.purchaseDate > $1.purchaseDate }
                .first?.transactionIdentifier
            
            if let recoveredID = stableID {
                Log.debug("📦 RC PROCESSOR: Recovered ID from history: \(recoveredID)")
            }
        }
        
        // 2. Final Guard: If we still have no ID and it's a consumable, we can't grant it safely
        guard let finalID = stableID else {
            if type.isConsumable {
                Log.error("🚨 RC Processor: No transaction ID found for consumable. Aborting.")
                return false
            }
            // For non-consumables, we can fallback to a synthetic ID if needed
            let dateTag = customerInfo.requestDate.timeIntervalSince1970.description
            let syntheticID = "rc_synth_\(customerInfo.originalAppUserId)_\(type.productID)_\(dateTag)"
            
            Log.debug("📦 RC PROCESSOR: Using Synthetic ID for Non-Consumable: \(syntheticID)")
            return try await handlePersistence(type: type, id: syntheticID, info: customerInfo)
        }

        return try await handlePersistence(type: type, id: finalID, info: customerInfo)
    }

    private func handlePersistence(type: PurchaseType, id: String, info: CustomerInfo) async throws -> Bool {
        Log.debug("📦 RC PERSISTENCE: Handling \(type.productID) with ID \(id)")
        
        // Idempotency Gate
        let alreadyProcessed = await store.isTransactionProcessed(transactionID: id)
        if alreadyProcessed {
            Log.debug("🚨 RC ID COLLISION: \(id) already handled in Store. Skipping.")
            return false
        }

        // Entitlement Check for Premium
        if let entitlementID = type.entitlementID {
            let isActive = info.entitlements[entitlementID]?.isActive == true
            Log.debug("📦 RC ENTITLEMENT: \(entitlementID) status: \(isActive)")
            
            guard isActive else {
                Log.debug("RC: Entitlement \(entitlementID) not active for ID \(id).")
                return false
            }
        }

        // Save to Keychain
        do {
            if type.isConsumable {
                Log.debug("📦 RC ACTION: Adding \(type.creditsAmount) credits...")
                try await store.addPurchase(credits: type.creditsAmount, transactionID: id)
            } else if type == .premiumDestinations {
                Log.debug("📦 RC ACTION: Unlocking Premium...")
                try await store.unlockPremiumDestinations(transactionID: id)
            }
            
            Log.debug("✅ Processor: RC Success for ID \(id).")
            return true
        } catch {
            // Restoring your critical alert for keychain/DB failures
            Log.error("CRITICAL: Persistence failed for ID \(id): \(error.localizedDescription)")
            throw error
        }
    }
}
