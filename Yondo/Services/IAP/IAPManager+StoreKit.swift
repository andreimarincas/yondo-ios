//
//  IAPManager+StoreKit.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.03.2026.
//

import StoreKit
import SwiftUI

extension IAPManager {
    func fetchStoreKitProducts() async {
        let isConnected = networkMonitor.isConnected
        Log.debug("IAPManager+SK: 🍎 fetchStoreKitProducts() called. Online: \(isConnected), Cache Count: \(self.products.count)")
        
        // 1. If we are offline AND we have no products at all, show Error immediately.
        if !isConnected && self.products.isEmpty {
            Log.error("IAPManager+SK: ❌ Hard failure. Device is offline and no cached products exist.")
            try? await Task.sleep(for: .seconds(0.5))
            
            self.finalizeFetch(
                fetchedProducts: [PurchaseType: any YondoProduct](),
                error: StoreError.networkIssue(URLError(.notConnectedToInternet)),
                updateDate: false
            )
            return
        }
        
        // 2. If we are offline BUT we HAVE products from a previous successful fetch:
        if !isConnected {
            // Log it, but don't overwrite the screen with an error.
            // The user sees the old prices, but the PurchaseButton will
            // handle the failure if they try to tap it.
            Log.debug("IAPManager+SK: ⚠️ Offline, but skipping fetch and holding \(self.products.count) stale products to keep UI populated.")
            return
        }
        
        let startTime = Date()
        
        withAnimation {
            Log.debug("IAPManager+SK: ⏳ Transitioning state to .loading")
            self.loadingState = .loading
        }
        
#if DEBUG
        // Simulate a slow network delay if toggled
        if activeDebugScenario == .slowNetwork {
            Log.debug("IAPManager+SK: 🛠️ Debug Scenario slowNetwork - Forcing 3.0 second artificial delay.")
            try? await Task.sleep(for: .seconds(3))
        }
#endif
        
        // Ensure the spinner shows for at least 500ms
        func sleepIfNeeded(startTime: Date) async {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.5 {
                let delay = 0.5 - elapsed
                Log.debug("IAPManager+SK: ⏳ Padding UI spinner for an extra \(String(format: "%.2fs", delay))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        do {
            let ids = PurchaseType.allCases.map { $0.productID }
            Log.debug("IAPManager+SK: 🛰️ Sending request to Apple for Product IDs: \(ids)")
            let storeProducts = try await Product.products(for: ids)
            
            // CHECK: Did the user leave while we were waiting for Apple?
            // If the user already has credits now (from a background save),
            // and we are about to dismiss, maybe we don't need to update the state.
            if Task.isCancelled {
                Log.debug("IAPManager+SK: 🛑 Task cancelled while waiting on Apple. Aborting.")
                return
            }
            
            Log.debug("IAPManager+SK: 📥 Apple returned \(storeProducts.count) valid products.")
            
            // 1. Map directly to [PurchaseType: any YondoProduct] in one pass
            let mapped = storeProducts.reduce(into: [PurchaseType: any YondoProduct]()) { dict, product in
                if let type = PurchaseType.from(productID: product.id) {
                    dict[type] = product
                }
            }
            
            await sleepIfNeeded(startTime: startTime)
            if Task.isCancelled {
                Log.debug("IAPManager+SK: 🛑 Task cancelled during UI padding. Aborting.")
                return
            }
            
            // 2. Finalize (Success or Regional Empty)
            // If Apple returned nothing but we are online, it's a regional/setup issue
            if mapped.isEmpty {
                // We successfully reached Apple, but they returned nothing.
                // This is usually a Storefront/Region issue.
                Log.error("IAPManager+SK: ❓ Apple returned nothing for our IDs. Evaluating as emptyRegion.")
                finalizeFetch(fetchedProducts: [PurchaseType: any YondoProduct](), error: StoreError.emptyRegion, updateDate: true)
            } else {
                // Success! We have live data.
                Log.debug("IAPManager+SK: ✅ Successfully mapped \(mapped.count) products.")
                finalizeFetch(fetchedProducts: mapped, error: nil, updateDate: true)
            }
        } catch {
            await sleepIfNeeded(startTime: startTime)
            if Task.isCancelled {
                Log.debug("IAPManager+SK: 🛑 Task cancelled on error path. Aborting.")
                return
            }
            Log.error("IAPManager+SK: ❌ StoreKit fetch failed with error: \(error)")
            finalizeFetch(fetchedProducts: [PurchaseType: any YondoProduct](), error: StoreError.networkIssue(error), updateDate: false)
        }
    }
    
    func purchaseViaStoreKit(_ type: PurchaseType) async throws -> PurchaseResult {
        Log.debug("IAPManager+SK: 🛒 purchaseViaStoreKit() requested for Product ID: \(type.productID)")
        
        guard purchasingProductID == nil else {
            Log.error("IAPManager+SK: 🛑 Cannot purchase \(type.productID). Already purchasing \(purchasingProductID!)")
            throw PurchaseError.invalidState
        }
        
        purchasingProductID = type.productID
        Log.debug("IAPManager+SK: 🏷️ Set purchasingProductID to \(type.productID). Spinning UI...")
        
        defer {
            // Do it in a task to avoid ghost price
            Task { @MainActor in
                Log.debug("IAPManager+SK: 🏷️ Nullifying purchasingProductID for \(type.productID). Ending UI Spin.")
                purchasingProductID = nil
            }
        }
        
        // Identity Unification Check (The Cloud Sync Gate)
        try await ensureAuthenticated()
        
        // Cast the generic product back to StoreKit's Product
        guard let product = products[type] as? StoreKit.Product else {
            Log.error("IAPManager+SK: ❌ Could not find/cast generic product to StoreKit.Product for \(type.productID)")
            throw PurchaseError.productNotFound
        }
        
        do {
            Log.debug("IAPManager+SK: 📡 Awaiting Apple system payment sheet...")
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                Log.debug("IAPManager+SK: 🟢 Transaction success for \(transaction.id). Handing over to processor.")
                
                let isFresh = try await processor.process(transaction: transaction)
                Log.debug("IAPManager+SK: 🟢 Processor finished. Fresh Transaction: \(isFresh)")
                
                return (isFresh || !type.isConsumable) ? .success : .alreadyVerified
                
            case .userCancelled:
                Log.debug("IAPManager+SK: ⚪ User cancelled the Apple sheet.")
                throw PurchaseError.cancelled
                
            case .pending:
                // This happens for "Ask to Buy" or "Deferred" payments
                Log.debug("IAPManager+SK: 🟡 Transaction pending (Ask to Buy / Deferred).")
                throw PurchaseError.pending
                
            @unknown default:
                Log.error("IAPManager+SK: ❌ Unknown result yielded by product.purchase()")
                throw PurchaseError.unknown
            }
            
        } catch {
            // 4. THE FIX: If an error occurs, check if the transaction actually went through anyway
            Log.debug("IAPManager+SK: ⚠️ product.purchase() threw an error: \(error.localizedDescription). Scrubbing for Ghost transactions...")
            
            // Give the background listener a tiny moment to receive the transaction
            try? await Task.sleep(for: .seconds(1.5))
            
            // Look for any verified transaction for this product that happened in the last 30 seconds
            for await verification in Transaction.currentEntitlements {
                if case .verified(let transaction) = verification,
                   transaction.productID == purchasingProductID,
                   abs(transaction.purchaseDate.timeIntervalSinceNow) < 30 {
                    
                    Log.debug("IAPManager+SK: ✅ Ghost transaction found for \(transaction.productID)! Treating as successful.")
                    let isFresh = try await processor.process(transaction: transaction)
                    return (isFresh || !type.isConsumable) ? .success : .alreadyVerified
                }
            }
            
            // If we found nothing, then it really failed
            Log.error("IAPManager+SK: ❌ Ghost check failed. No concurrent successful transactions found for product. Propagating error.")
            throw error
        }
    }
    
    /// Helper to verify StoreKit 2 results
    func checkVerified<T>(_ result: StoreKit.VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            Log.error("IAPManager+SK: 🔐 Verification failed for payload. Error: \(error)")
            throw PurchaseError.verificationFailed(error)
        case .verified(let safe):
            return safe
        }
    }
    
    func restoreStoreKitPurchases() async throws -> Bool {
        Log.debug("IAPManager+SK: ⏳ restoreStoreKitPurchases() -> Forcing AppStore.sync()")
        
        // 1. Force Apple to sync the local receipt/entitlements
        // AppStore.sync() forces the device to fetch the latest data from Apple
        // Note: This often triggers a system-level Apple ID password prompt
        try await AppStore.sync()
        
        // 2. Re-verify everything Apple just gave us
        // This will hit your background listener logic and update the Keychain
        Log.debug("IAPManager+SK: AppStore.sync() finished. Recounting current entitlements...")
        return await refreshStoreKitEntitlements()
    }
    
    func refreshStoreKitEntitlements() async -> Bool {
        Log.debug("IAPManager+SK: 🔄 refreshStoreKitEntitlements() (Batch Refresh) initiated.")
        var batch: [StoreKit.Transaction] = []
        
        // 1. Collect everything Apple says we own
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                batch.append(transaction)
            }
        }
        
        Log.debug("IAPManager+SK: 🔄 Batch collected \(batch.count) verified entitlements from Apple. Pushing to processor.")
        
        // 2. Send the whole pile to the processor at once
        do {
            let success = try await processor.processBatch(transactions: batch)
            Log.debug("IAPManager+SK: ✅ Batch process finished. Success: \(success)")
            return success
        } catch {
            Log.error("IAPManager+SK: ❌ Batch process failed with error: \(error)")
            return false
        }
    }
    
    /// The Centralized Listener
    func observeTransactionUpdate() {
        Log.debug("IAPManager+SK: 🕵️ Initializing observeTransactionUpdate listener.")
        
        skUpdateTask = Task { [weak self] in
            Log.debug("IAPManager+SK: 🕵️ Transaction listener Task attached to Transaction.updates stream.")
            
            for await update in Transaction.updates {
                guard let self = self else {
                    Log.debug("IAPManager+SK: 🕵️ Transaction listener loop broken because IAPManager was deallocated.")
                    break
                }
                
                Log.debug("IAPManager+SK: 🕵️ Transaction.updates stream yielded an event.")
                
                do {
                    // Verify the JWS signature
                    let transaction = try self.checkVerified(update)
                    Log.debug("IAPManager+SK: 🕵️ Received background transaction \(transaction.id) for Product ID \(transaction.productID). Sending to processor...")
                    
                    // Pass to actor for serial, thread-safe processing
                    try await _ = self.processor.process(transaction: transaction)
                    Log.debug("IAPManager+SK: 🕵️ Background transaction \(transaction.id) processed successfully.")
                } catch {
                    Log.error("IAPManager+SK: ❌ Background Transaction stream processing error: \(error)")
                }
            }
        }
    }
}
