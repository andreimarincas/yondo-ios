//
//  PurchaseProcessor.swift
//  Yondo
//
//  Created by Andrei Marincas on 16.01.2026.
//

import StoreKit
import RevenueCat

enum ProcessError: Error {
    case previouslyRefunded // User is trying to "re-claim" money they got back
    case unknownProduct     // Apple sent a ProductID your app doesn't recognize
}

actor PurchaseProcessor {
    let store: SecureCreditStore
    
    init(store: SecureCreditStore) {
        self.store = store
    }
    
    /// The entry point for all transactions (Listener + Manual Sync)
    /// Return true if it actually added something new to the Keychain, and false if it just finished an old transaction.
    func process(transaction: Transaction) async throws -> Bool {
        Log.debug("--- 📦 Processor: Processing ID \(transaction.id) ---")
        
        // 1. Idempotency Gate (The "Logic Barrier")
        // If we've seen this ID before, it's a "Ghost" transaction.
        // We finish it with Apple and exit immediately.
        let alreadyProcessed = await store.isTransactionProcessed(transactionID: transaction.id)
        
        if alreadyProcessed {
            Log.debug("🚨 ID COLLISION: Transaction \(transaction.id) was already processed. Finishing and skipping.")
            await transaction.finish()
            return false // Return FALSE: No new goods added
        }
        
        // 2. Revocation Check: Don't process if the user was refunded
        guard transaction.revocationDate == nil else {
            await transaction.finish()
            Log.debug("Skipping refunded transaction: \(transaction.id)")
            throw ProcessError.previouslyRefunded
        }
        
        // 3. Product Validation
        guard let purchaseType = PurchaseType.from(productID: transaction.productID) else {
            Log.debug("Unknown product ID: \(transaction.productID)")
            throw ProcessError.unknownProduct
        }
        
        // 4. Persistence
        do {
            switch purchaseType {
            case .premiumDestinations:
                try await store.unlockPremiumDestinations(transactionID: transaction.id)
                
            case .imagePack3, .imagePack10, .imagePack25:
                try await store.addPurchase(credits: purchaseType.creditsAmount, transactionID: transaction.id)
            }
            
            // 5. Finalize with Apple
            
            // The Risk of finishing in a task: If the app is suspended or the actor is deallocated
            // immediately after the method returns true, that background task might never execute,
            // leaving the transaction "unfinished" in the Apple queue. Since you are already in an
            // actor, you should await the finish before returning.
            
            // Finish BEFORE returning to ensure Apple knows we are done.
            await transaction.finish()
            Log.debug("Successfully processed and finished: \(transaction.productID)")
            
            /*
            // We finish in a background Task so the UI can dismiss immediately
            Task {
                await transaction.finish()
                Log.debug("Successfully processed and finished: \(transaction.productID)")
            }*/
            
            Log.debug("Successfully saved in Keychain, productID: \(transaction.productID). Finishing transaction in background.")
            Log.debug("✅ Processor: Success for \(transaction.id). Returning TRUE.")
            
            return true // Return TRUE: Fresh credits added!
            
        } catch {
            // FAILURE: Something went wrong with the Keychain.
            // We do NOT call transaction.finish().
            // This transaction stays in 'currentEntitlements' and will be
            // retried automatically the next time the app starts.
            Log.error("Critical: Could not save purchase to Keychain: \(error)")
            throw error // Allow caller to handle UI (e.g., hide loading spinner)
        }
    }
    
    /// Processes multiple transactions at once for an efficient "Restore"
    /// Returns TRUE if any NEW items were added
    func processBatch(transactions: [Transaction]) async throws -> Bool {
        var totalCredits = 0
        var transactionsToFinish: [Transaction] = []
        var trashTransactions: [Transaction] = []
        var unlockPremium = false
        
        for transaction in transactions {
            // Skip if revoked/refunded
            if transaction.revocationDate != nil {
                trashTransactions.append(transaction)
                continue
            }
            
            // 1. Idempotency check: Only process if not already in Keychain
            let alreadyProcessed = await store.isTransactionProcessed(transactionID: transaction.id)
            if alreadyProcessed {
                trashTransactions.append(transaction)
                continue
            }
            
            if let type = PurchaseType.from(productID: transaction.productID) {
                switch type {
                case .premiumDestinations:
                    unlockPremium = true
                case .imagePack3, .imagePack10, .imagePack25:
                    totalCredits += type.creditsAmount
                }
                transactionsToFinish.append(transaction)
            }
        }
        
        // 2. Perform ONE atomic write for the whole batch
        if !transactionsToFinish.isEmpty {
            let ids = Set(transactionsToFinish.map { $0.id })
            try await store.applyBatch(credits: totalCredits, transactions: ids, unlocksPremium: unlockPremium)
            Log.debug("Successfully batched \(transactionsToFinish.count) transactions.")
        }
        
        // 3. Finish all transactions only after the batch save succeeds
        let allToFinish = transactionsToFinish + trashTransactions
        
        if !allToFinish.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for transaction in allToFinish {
                    group.addTask {
                        await transaction.finish()
                        Log.debug("Finished transaction: \(transaction.id)")
                    }
                }
            }
        }
        
        // 4. Return true only if we actually added new value
        return !transactionsToFinish.isEmpty
    }
}
