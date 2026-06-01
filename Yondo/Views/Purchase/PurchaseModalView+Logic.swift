//
//  PurchaseModalView+Logic.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.03.2026.
//

import SwiftUI
import StoreKit

extension PurchaseModalView {
    func handlePurchase(for type: PurchaseType, productID: Product.ID) {
        Log.debug("🕹️ UI: User tapped purchase for type: [\(type)] (Product ID: \(productID))")
        
        guard !isInteractionDisabled else {
            Log.debug("🕹️ UI: 🛑 Purchase tap ignored. UI interaction is currently disabled.")
            return
        }
        
        isProcessing = true
        
        Task {
            defer {
                Log.debug("🕹️ UI: Ending purchase task processing state.")
                isProcessing = false
            }
            
            // Pre-flight check: Network
            // Show the alert immediately without even trying the purchase
            guard iapManager.networkMonitor.isConnected else {
                Log.error("🕹️ UI: ❌ Purchase aborted. Device is offline.")
                self.activeAlert = .init(title: "Cannot Purchase", message: "Internet connection required to complete purchase.")
                return
            }
            
            do {
                Log.debug("🕹️ UI: ⏳ Forwarding purchase intent to IAPManager...")
                
                let result = try await iapManager.purchase(type)
                Log.debug("🕹️ UI: 📥 Received purchase result: [\(result)]")
                
                switch result {
                case .success:
                    // 🎉 FULL CELEBRATION
                    Log.debug("🎉 UI: Processing full success celebration for \(productID)")
                    HapticManager.shared.success()
                    
                    iapManager.isAnimatingCelebration = true
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0)) {
                        successfulProductID = type.productID
                        isProcessing = false
                    }
                    
                    Log.debug("🎉 UI: Sleeping for 1.5s to display celebration view.")
                    try? await Task.sleep(for: .seconds(1.5))
                    
                    Log.debug("🎉 UI: Dismissing modal post-celebration.")
                    dismiss()
                    
                case .alreadyVerified:
                    // 🙂 SOFT SUCCESS
                    Log.debug("🎉 UI: Processing soft success (already verified) for \(productID)")
                    isProcessing = false
                    try? await Task.sleep(for: .seconds(0.6))
                    
                    Log.debug("🎉 UI: Dismissing modal post-soft-success.")
                    dismiss()
                }
            } catch PurchaseError.pending {
                // DO NOTHING.
                // The system popup already told the user what happened.
                // We just let the spinner stop (via defer) so they can use the app.
                Log.debug("🕹️ UI: 🟡 Purchase is pending parental/deferred approval. Halting UI spinner.")
            } catch PurchaseError.cancelled {
                // User swiped down the Apple pay sheet or tapped 'Cancel'
                // Silence cancellation
                Log.debug("🕹️ UI: ⚪ Purchase sheet cancelled by the user.")
            } catch let storeError as StoreError {
                Log.error("🕹️ UI: ❌ Local StoreError thrown: \(storeError.localizedDescription)")
                
                if case .missingUser = storeError {
                    self.activeAlert = .init(
                        title: "Account Verification Needed",
                        message: storeError.errorDescription ?? "Please verify your internet connection and try again."
                    )
                } else {
                    self.activeAlert = .init(title: "Purchase Failed", message: storeError.localizedDescription)
                }
            } catch {
                Log.error("🕹️ UI: ❌ Purchase flow failed with error: \(error.localizedDescription)")
                
                if case .previouslyRefunded = error as? ProcessError {
                    Log.debug("🕹️ UI: Mapping ProcessError.previouslyRefunded to custom alert message.")
                    self.activeAlert = .init(
                        title: "Purchase Unavailable",
                        message: "Apple indicates this transaction was previously refunded. Please try a different credit pack or contact Apple Support if you believe this is an error."
                    )
                } else {
                    self.activeAlert = .init(title: "Purchase Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    // Helper to keep the errorView clean
    func isRootErrorOffline(_ error: Error) -> Bool {
        Log.debug("🕹️ UI: Evaluating if error is root-offline: \(error.localizedDescription)")
        
        // Check StoreKit 2 Errors
        if let skError = error as? StoreKitError {
            if case .networkError = skError {
                Log.debug("  ↳ Result: True (StoreKit networkError)")
                return true
            }
        }
        // Check underlying URLErrors
        if let urlError = error as? URLError {
            let isOffline = urlError.code == .notConnectedToInternet || urlError.code == .timedOut
            Log.debug("  ↳ Result: \(isOffline) (URLError)")
            return isOffline
        }
        let nsError = error as NSError
        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost]
        let isNSOffline = nsError.domain == NSURLErrorDomain && offlineCodes.contains(nsError.code)
        
        Log.debug("  ↳ Result: \(isNSOffline) (NSError)")
        return isNSOffline
    }
    
    func restore() {
        Log.debug("🔄 UI: User tapped Restore Purchases.")
        
        // Reset states
        showSuccess = false
        isRestoring = true
        
        Task {
            defer {
                Log.debug("🔄 UI: Ending restore task processing state.")
                if isRestoring {
                    withAnimation {
                        isRestoring = false // Spinner stops no matter what
                    }
                }
            }
            
            // Show the alert immediately without even trying the restore
            guard iapManager.networkMonitor.isConnected else {
                Log.error("🔄 UI: ❌ Restore aborted. Device is offline.")
                self.activeAlert = .init(
                    title: "Cannot Restore Purchases",
                    message: "Internet connection required to restore purchases.")
                return
            }
            
            do {
                Log.debug("🔄 UI: ⏳ Forwarding restore intent to IAPManager...")
                
                // AppStore.sync() triggers the background listener.
                // That listener updates the Keychain.
                // The Keychain updates trigger your TWO .onChange modifiers.
                let foundNewItems = try await iapManager.restorePurchases()
                Log.debug("🔄 UI: 📥 Restore logic finished. Found new items: \(foundNewItems)")
                
                // Give the .onChange a tiny millisecond to catch up
                // Increased sleep from 0.1s to 0.5s in the restore task. StoreKit 2 and Keychain
                // syncing are notoriously "eventually consistent"—giving it half a second ensures
                // your .onChange triggers before the "No purchases found" alert pops up.
                Log.debug("🔄 UI: Sleeping 0.5s for eventual-consistency race coverage.")
                try? await Task.sleep(for: .seconds(0.5))
                
                // GUARD: If the .onChange already started the dismissal, STOP here.
                guard !isDismissing else {
                    Log.debug("🔄 UI: 🛑 Aborting restore alert sequence. .onChange observer already dismissed the view.")
                    return
                }
                
                if foundNewItems {
                    Log.debug("🎉 UI: Showing Restore Success visual state.")
                    
                    // This covers the case where items were restored but maybe
                    // the .onChange didn't fire (e.g., a non-consumable sync)
                    HapticManager.shared.success()
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0)) {
                        // Update both in the same animation block so that the morphing
                        // animation for spinner -> restore glass buttons works
                        showSuccess = true
                        isRestoring = false
                    }
                    
                    // If it's a non-consumable that doesn't trigger a credit .onChange,
                    // you might want to dismiss here manually:
                    try? await Task.sleep(for: .seconds(1.5))
                    
                    Log.debug("🎉 UI: Dismissing modal post-restore success.")
                    dismiss()
                    
                } else {
                    Log.debug("ℹ️ UI: Rendering 'No purchases found' empty set alert.")
                    
                    // IDEMPOTENT/EMPTY: Sync finished but nothing new was found
                    self.activeAlert = .init(
                        title: "Restore Status",
                        message: "No new purchases were found to restore. Your account is already up to date."
                    )
                }
            } catch {
                // Explicitly check for StoreKitError.userCancelled
                if case StoreKitError.userCancelled = error {
                    Log.debug("🔄 UI: ⚪ User cancelled AppStore syncing sheet during restore.")
                    return
                }
                
                Log.error("🔄 UI: ❌ Restore failed with error: \(error.localizedDescription)")
                self.activeAlert = .init(title: "Restore Failed", message: error.localizedDescription)
            }
        }
    }
    
    var isRestoreDisabled: Bool {
        // TODO: double check logic
        (isInteractionDisabled && !isRestoring && !showSuccess) || !iapManager.networkMonitor.isConnected
    }
    
    var captionMessage: String {
        // 1. Highest priority: No internet
        if !iapManager.networkMonitor.isConnected {
            return "Connect to the internet to restore purchases."
        }
        
        // NEW: Add a success message priority
        if showSuccess {
            return "Restore successful!"
        }
        
        // 2. Second priority: If the button is disabled for ANY reason,
        // we show a "working" message.
        if isInteractionDisabled && successfulProductID == nil && !showSuccess {
            if isProcessing {
                return "Processing purchase..."
            }
            return "Syncing with App Store..."
        }
        
        // 3. Default: Ready to go
        return "Purchases are linked to your Apple ID."
    }
    
    func getStatusBadge(for productID: String) -> String? {
        guard let product = PurchaseType.from(productID: productID) else { return nil }
        switch product {
        case .imagePack10:
            return "⭐"
        case .premiumDestinations:
            return iapManager.creditStore.premiumDestinationsUnlocked ? "✅" : "🔒"
        default:
            return nil
        }
    }
    
    func shouldShowSuccessBadge(for productID: String) -> Bool {
        // Only show the badge if this is the successful product
        // AND we aren't currently trying to buy something else
        return successfulProductID == productID //&& iapManager.purchasingProductID == nil
    }
}
