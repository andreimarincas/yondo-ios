//
//  IAPManager+RevenueCat.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.03.2026.
//

import RevenueCat
import SwiftUI

extension IAPManager {
    func fetchRevenueCatProducts() async {
        let isConnected = networkMonitor.isConnected
        Log.debug("IAPManager+RC: 🐱 fetchRevenueCatProducts() called. Online: \(isConnected), Cache Count: \(self.products.count)")
        
        // 1. If we are offline AND we have no products at all, show Error immediately.
        if !isConnected && self.products.isEmpty {
            Log.error("IAPManager+RC: ❌ Hard failure. Device is offline and no cached products exist.")
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
            Log.debug("IAPManager+RC: ⚠️ Offline, but skipping fetch and holding \(self.products.count) stale products to keep UI populated.")
            return
        }
        
        let startTime = Date()
        
        withAnimation {
            Log.debug("IAPManager+RC: ⏳ Transitioning state to .loading")
            self.loadingState = .loading
        }
        
#if DEBUG
        // Simulate a slow network delay if toggled
        if activeDebugScenario == .slowNetwork {
            Log.debug("IAPManager+RC: 🧪 Simulating slow network (3s delay)...")
            try? await Task.sleep(for: .seconds(3))
        }
#endif
        
        // Ensure the spinner shows for at least 500ms
        func sleepIfNeeded(startTime: Date) async {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.5 {
                let delay = 0.5 - elapsed
                Log.debug("IAPManager+RC: ⏳ Padding UI spinner for an extra \(String(format: "%.2fs", delay))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        do {
            // 1. Fetch current offerings from RevenueCat Dashboard
            Log.debug("IAPManager+RC: 🛰️ Sending offerings fetch request to RevenueCat...")
            let offerings = try await Purchases.shared.offerings()
            
            // Log which offering we are targeting
            let offeringToUse = offerings["main_store"] ?? offerings.current
            let offeringID = (offerings["main_store"] != nil) ? "main_store" : "current"
            
            guard let current = offeringToUse else {
                // No current offering set in the dashboard
                Log.error("IAPManager+RC: ❌ No offerings found! (Checked 'main_store' and fallback 'current')")
                finalizeFetch(fetchedProducts: [PurchaseType: any YondoProduct](), error: StoreError.emptyRegion, updateDate: true)
                return
            }
            
            Log.debug("IAPManager+RC: ✅ Offering '\(offeringID)' contains \(current.availablePackages.count) packages.")
            
            // 2. Map RC Packages directly to your Dictionary
            var mapped: [PurchaseType: any YondoProduct] = [:]
            for package in current.availablePackages {
                let productID = package.storeProduct.productIdentifier
                if let type = PurchaseType.from(productID: productID) {
                    mapped[type] = package
                    Log.debug("  ↳ 🛒 Mapped: \(productID) -> \(type)")
                } else {
                    Log.debug("  ↳ ⚠️ Unmapped: \(productID) (No matching local PurchaseType found)")
                }
            }
            
            Log.debug("IAPManager+RC: ✅ Mapping completed. Yielding \(mapped.count) products.")
            
            await sleepIfNeeded(startTime: startTime)
            if Task.isCancelled {
                Log.debug("IAPManager+RC: 🛑 Task cancelled during UI padding. Aborting finalization.")
                return
            }
            
            // 3. Use the generic finalizer
            finalizeFetch(fetchedProducts: mapped, error: nil, updateDate: true)
            
        } catch {
            await sleepIfNeeded(startTime: startTime)
            if Task.isCancelled {
                Log.debug("IAPManager+RC: 🛑 Task cancelled on error path. Aborting finalization.")
                return
            }
            Log.error("IAPManager+RC: ❌ Fetch failed with error: \(error.localizedDescription)")
            finalizeFetch(fetchedProducts: [PurchaseType: any YondoProduct](), error: StoreError.networkIssue(error), updateDate: false)
        }
    }
    
    func purchaseViaRevenueCat(_ type: PurchaseType) async throws -> PurchaseResult {
        Log.debug("IAPManager+RC: 💳 purchaseViaRevenueCat() requested for: \(type.productID)")
        
        guard purchasingProductID == nil else {
            Log.error("IAPManager+RC: 🛑 Cannot purchase \(type.productID). Already purchasing \(purchasingProductID!)")
            throw PurchaseError.invalidState
        }
        
        purchasingProductID = type.productID
        Log.debug("IAPManager+RC: 🏷️ Set purchasingProductID to \(type.productID). Spinning UI...")
        
        defer {
            // Do it in a task to avoid ghost price
            Task { @MainActor in
                Log.debug("IAPManager+RC: 🏷️ Nullifying purchasingProductID for \(type.productID). Ending UI Spin.")
                purchasingProductID = nil
            }
        }
        
        // Identity Unification Check (The Cloud Sync Gate)
        try await ensureAuthenticated()
        
        // 1. Find the RevenueCat Package from your local products dictionary
        // Note: Ensure your YondoProduct protocol or struct stores the RC 'Package'
        guard let product = products[type], let package = product.rcPackage else {
            Log.error("IAPManager+RC: ❌ Could not find RevenueCat package in cache for \(type.productID)")
            throw PurchaseError.productNotFound
        }
        
        do {
            Log.debug("IAPManager+RC: 📡 Yielding control to RC SDK for package: \(package.identifier)")
            
            // 2. Perform the purchase using the Package
            let result = try await Purchases.shared.purchase(package: package)
            Log.debug("IAPManager+RC: 🟢 RC SDK yielded purchase result. Request Date: \(result.customerInfo.requestDate)")
            
            self.lastCustomerInfoRequestDate = result.customerInfo.requestDate
            
            // 3. Handle User Cancellation
            if result.userCancelled {
                Log.debug("IAPManager+RC: ⚪ Purchase sheet manually cancelled by user.")
                throw PurchaseError.cancelled
            }
            
            // 4. Update the local Keychain/Firebase via your processor
            // We pass the type so the processor knows how many credits to add
            Log.debug("IAPManager+RC: 🏗️ Routing to PurchaseProcessor for persistence mapping.")
            let isFresh = try await processor.processRevenueCat(
                customerInfo: result.customerInfo,
                transaction: result.transaction,
                type: type
            )
            Log.debug("IAPManager+RC: 🏗️ Processor finished. Fresh Transaction locally: \(isFresh)")
            
            return (isFresh || !type.isConsumable) ? .success : .alreadyVerified
            
        } catch {
            Log.error("IAPManager+RC: ⚠️ RC purchase sheet threw error: \(error.localizedDescription). Checking for 'Ghost' success...")
            
            // If an error occurred, the purchase might still have finished in the background.
            try? await Task.sleep(for: .seconds(1.5)) // Give RC a moment to sync
            
            do {
                let info = try await Purchases.shared.customerInfo()
                
                // 1. Check if the specific entitlement is now active (for Premium)
                let hasEntitlement = type.entitlementID != nil && info.entitlements[type.entitlementID!]?.isActive == true
                
                // 2. Check for a very recent transaction matching this product ID (for Credits)
                let hasRecentTransaction = info.nonSubscriptions.contains {
                    $0.productIdentifier == type.productID && abs($0.purchaseDate.timeIntervalSinceNow) < 60
                }
                
                if hasEntitlement || hasRecentTransaction {
                    Log.debug("IAPManager+RC: ✅ Ghost success validated on retry. Entitlement/Consumable active on RC servers. Overriding error!")
                    
                    // We pass transaction: nil because the error hidden the original object,
                    // but processRevenueCat is now updated to handle this.
                    let isFresh = try await processor.processRevenueCat(
                        customerInfo: info,
                        transaction: nil,
                        type: type
                    )
                    return (isFresh || !type.isConsumable) ? .success : .alreadyVerified
                } else {
                    Log.debug("IAPManager+RC: ❌ Ghost success scrub yielded no valid matches.")
                }
            } catch {
                Log.error("IAPManager+RC: ❌ Scrub check crashed: \(error.localizedDescription)")
            }
            
            // Re-throw the original error if no ghost success was found
            throw error
        }
    }
    
    func restoreRevenueCatPurchases() async throws -> Bool {
        Log.debug("IAPManager+RC: ⏳ restoreRevenueCatPurchases() requested.")
        
        do {
            // 1. Sync with RevenueCat Backend
            // This identifies the user and refreshes their entitlements
            let customerInfo = try await Purchases.shared.restorePurchases()
            Log.debug("IAPManager+RC: 📥 RC server yielded \(customerInfo.allPurchasedProductIdentifiers.count) historical product IDs.")
            
            // If nothing is found, we can try a "Sync" which force-refreshes the receipt
            // This is sometimes more effective in Sandbox
//            if customerInfo.entitlements.active.isEmpty {
//                Log.debug("ℹ️ Standard restore empty, attempting force sync...")
//                let syncedPurchases = try await Purchases.shared.syncPurchases()
//                Log.debug("syncedPurchases = \(syncedPurchases)")
//            }
            
            // 2. Determine if the "premium" entitlement is active
            // Change "premium" to whatever ID you set in the RevenueCat Dashboard
            let entitlementID = PurchaseType.premiumDestinations.entitlementID ?? "premium_destinations"
            let isPremiumActive = customerInfo.entitlements[entitlementID]?.isActive ?? false
            
            // 3. Sync the local SecureCreditStore (Keychain)
            // This ensures the UI updates immediately via your .onChange modifiers
            // Note: We don't restore credits here because they are consumables.
            // Consumables are usually handled via Firebase/Backend
            if isPremiumActive {
                Log.debug("IAPManager+RC: 📦 Verified active premium entitlement. Forcing processor to hydrate Keychain...")
                
                // We pass transaction: nil. The processor will generate a Synthetic ID
                // and securely unlock it in the Keychain.
                let isFresh = try await processor.processRevenueCat(
                    customerInfo: customerInfo,
                    transaction: nil,
                    type: .premiumDestinations
                )
                
                return isFresh
            } else {
                Log.debug("IAPManager+RC: ℹ️ No active premium entitlements found on user account.")
            }
            
            // TODO: Restore batch transactions?
            
            Log.debug("IAPManager+RC: ✅ Restore routine finished. Premium Active state yielded: \(isPremiumActive)")
            return false
            
        } catch let error as RevenueCat.ErrorCode {
            // 4. RevenueCat has a specific ErrorCode enum—much better than checking '1'
            if error == .purchaseCancelledError {
                Log.debug("IAPManager+RC: ⚪ User cancelled the AppStore login sheet during restore.")
                throw PurchaseError.cancelled
            }
            Log.error("IAPManager+RC: ❌ Restore failed with RC Error Code: \(error)")
            throw error
        } catch {
            Log.error("IAPManager+RC: ❌ Restore failed with unknown error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func refreshRevenueCatEntitlements() async -> Bool {
        Log.debug("IAPManager+RC: 🔄 refreshRevenueCatEntitlements() polling customerInfo...")
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            
            // 1. Update Premium Status
            let entitlementID = PurchaseType.premiumDestinations.entitlementID ?? "premium_destinations"
            let isPremiumActive = customerInfo.entitlements[entitlementID]?.isActive ?? false
            
            // 2. Update the Store (Keychain)
            // Since RC is the source of truth, we sync the local store to match
            if isPremiumActive {
                Log.debug("IAPManager+RC: 🔄 Passive refresh found active Premium. Synching keychain.")
                // Route through Processor
                _ = try await processor.processRevenueCat(
                    customerInfo: customerInfo,
                    transaction: nil,
                    type: .premiumDestinations
                )
            } else {
                Log.debug("IAPManager+RC: 🔄 Passive refresh yielded no active Premium.")
            }
            return isPremiumActive
        } catch {
            Log.error("IAPManager+RC: ❌ Passive refresh failed: \(error.localizedDescription)")
            return false
        }
    }
}

extension IAPManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Log.debug("IAPManager+RC: 🔔 PurchasesDelegate pushed updated CustomerInfo. Date: \(customerInfo.requestDate)")
        
        // 🛡️ CHRONOLOGICAL GUARD
        if let lastDate = lastCustomerInfoRequestDate, customerInfo.requestDate <= lastDate {
            Log.debug("IAPManager+RC: 🔔 Delegate payload ignored. Sequence is stale or duplicate (Current: \(customerInfo.requestDate) <= Known: \(lastDate))")
            return // Ignore stale delegate emissions
        }
        self.lastCustomerInfoRequestDate = customerInfo.requestDate
        
        // Get the entitlement ID from your central enum
        let entitlementID = PurchaseType.premiumDestinations.entitlementID ?? "premium_destinations"
        let isPremiumActive = customerInfo.entitlements[entitlementID]?.isActive ?? false
        
        // Sync the Keychain immediately
        // We use Task because this delegate method might be called on a background thread
        if isPremiumActive {
            Task {
                Log.debug("IAPManager+RC: 🔔 Processing Active Premium found in delegate payload...")
                do {
                    // Update local Keychain/Memory via Processor
                    // This updates the UI immediately.
                    _ = try await self.processor.processRevenueCat(
                        customerInfo: customerInfo,
                        transaction: nil,
                        type: .premiumDestinations
                    )
                } catch {
                    Log.error("IAPManager+RC: ❌ Failed to process delegate customerInfo: \(error.localizedDescription)")
                }
            }
        }
        
        // Check if there are active entitlements or recent transactions
        // Non-consumables (Premium) are in entitlements.
        // Consumables (Credits) are in nonSubscriptions.
        let hasRecentTransaction = customerInfo.nonSubscriptions.contains {
            Date().timeIntervalSince($0.purchaseDate) < 60
        }
        
        let hasRecentEntitlement = customerInfo.entitlements.active.values.contains {
            guard let latestPurchase = $0.latestPurchaseDate else { return false }
            return Date().timeIntervalSince(latestPurchase) < 60
        }

        if hasRecentTransaction || hasRecentEntitlement {
            Task { @MainActor in
                self.recordSuccessfulPurchase()
            }
        }
    }
}
