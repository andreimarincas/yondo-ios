//
//  SceneBuilderViewModel+ErrorHandling.swift
//  Yondo
//
//  Created by Andrei Marincas on 25.03.2026.
//

import Foundation

extension SceneBuilderViewModel {
    func handleGenerationError(_ error: Error, token: GenerationToken, transactionID: UUID) async {
        Log.debug("⚠️ handleGenerationError caught: \(error). Token Match: \(token == self.activeGenerationToken)")
        
        // 🎯 Catch Local Store Errors first
        if let storeError = error as? StoreError, storeError == .insufficientFunds {
            shieldManager.stopTransaction(id: transactionID)
            self.finalizeGeneration(for: token, withError: .insufficientCredits)
            return
        }
        
        // Cast the incoming error to our clean Domain enum
        let sceneError = (error as? SceneGenerationError) ?? .unknown(error)
        
        // Handle the "Economy" (Refunds/Shields)
        if sceneError == .insufficientCredits {
            Log.debug("🛡️ [\(token.id.uuidString.prefix(8))] Server Insufficient: Dropping shield, skipping local refund.")
            // Never refund on insufficient credits error to avoid ghost credit loop.
            shieldManager.stopTransaction(id: transactionID)
        } else {
            Log.debug("♻️ [\(token.id.uuidString.prefix(8))] General Error: Refunding local credit and dropping shield.")
            // If it's a "Real" error (Network, Timeout, Server Crash), give the credit back.
            try? await generationManager.refundIfUndelivered(token, creditProvider: iapProvider)
            shieldManager.stopTransaction(id: transactionID)
        }
        
        // UI State Reaction
        switch sceneError {
        case .requiresPremiumUnlock(let destinationName):
            self.handlePremiumRequired(destinationName: destinationName, token: token)
            
        case .insufficientCredits:
            // 🛑 DO NOT REFUND (already handled above)
            self.handleInsufficientCredits(token: token)
            
        case .aiBusy, .networkConnectionLost, .unknown, .syncingCredits, .syncingPremiumUnlock:
            // Standard finalize for everything else
            self.finalizeGeneration(for: token, withError: sceneError)
        }
    }
    
    private func handlePremiumRequired(destinationName: String?, token: GenerationToken) {
        let hasLocalPremium = iapProvider.creditStore.premiumDestinationsUnlocked
        let recentlyPurchased = iapProvider.wasPurchaseMadeRecently
        
        Log.debug("🛡️ Premium Conflict: Local=\(hasLocalPremium), RecentPurchase=\(recentlyPurchased).")
        
        // 1. THE STALE TOKEN / AWAY CHECK
        // Prevent old/background generations from hijacking the active UI.
        guard isSceneViewVisible, token == activeGenerationToken else {
            Log.debug("🚶 User away or token stale during Premium Error. Finalizing state silently.")
            self.finalizeGeneration(for: token, withError: .requiresPremiumUnlock(destinationName: destinationName))
            
            // THE GHOST KILLER
            // If we haven't bought anything recently, and the server says NO,
            // then our local 'true' is a ghost. Kill it now.
            if !recentlyPurchased {
                Log.debug("👻 [Identity] Ghost Premium detected. Forcing revocation.")
                Task { await iapProvider.refreshEntitlements(force: true) }
            }
            // If recentlyPurchased == true, we do NOTHING.
            // We avoid the "Slow Webhook Wipeout" by NOT allowing a downgrade yet.
            return
        }
        
        // 2. ACTIVE UI CONFLICT HANDLING
        if hasLocalPremium || recentlyPurchased {
            Log.debug("🛡️ Active Premium Conflict Detected. Entering .syncingPremiumUnlock.")
            
            // MUTATE UI STATE SAFELY
            // Since local is still true (or we just bought it), we enter the sync state.
            self.generationError = .syncingPremiumUnlock
            self.isGenerating = false
            self.messageRotationTask?.cancel()
            self.cancelEnabled = false
            
            // 3. START HEALING
            // Start the 3-4-1 window
            syncHealingController.startPremiumHealing(
                token: token,
                destinationName: destinationName,
                isStillSyncing: { [weak self] in
                    // Hardened closure: Double check token hasn't changed during the sync window
                    self?.generationError == .syncingPremiumUnlock && self?.activeGenerationToken == token
                },
                onCompletion: { [weak self] error in
                    self?.finalizeGeneration(for: token, withError: error)
                }
            )
            
        } else {
            // Hard Lock: No reason to believe they have Premium.
            self.finalizeGeneration(for: token, withError: .requiresPremiumUnlock(destinationName: destinationName))
        }
    }
    
    private func handleInsufficientCredits(token: GenerationToken) {
        let localCredits = iapProvider.creditStore.credits
        let recentlyPurchased = iapProvider.wasPurchaseMadeRecently
        
        Log.debug("🛡️ Credit Conflict: Local=\(localCredits), RecentPurchase=\(recentlyPurchased).")
        
        // 1. THE STALE TOKEN / AWAY CHECK
        // If the user left the screen, OR if this error belongs to a previous/background generation,
        // we DO NOT touch the UI. We silently finalize the old generation.
        guard isSceneViewVisible, token == activeGenerationToken else {
            Log.debug("🚶 User is away or token is stale. Silently finalizing as Insufficient.")
            self.finalizeGeneration(for: token, withError: .insufficientCredits)
            
            // The Ghost Killer (Background Edition)
            // Even if we don't show the UI, we still want to kill the ghost credits.
            if !recentlyPurchased {
                Task { await syncService.forceRefreshFromCloud() }
            }
            return
        }
        
        // 2. ACTIVE UI CONFLICT HANDLING
        // We KNOW this is the visible, active generation. We must heal.
        Log.debug("🛡️ Active Credit Conflict Detected. Entering .syncingCredits state.")
        
        // If it's an old ghost credit, we can flush the buffers to speed up the kill.
        // (forceBypass is removed because the shield naturally drops when recentlyPurchased is false).
        if !recentlyPurchased {
            Task { await syncService.flushBuffers() }
        }
        
        // 3. MUTATE UI STATE SAFELY
        self.generationError = .syncingCredits
        self.isGenerating = false
        self.messageRotationTask?.cancel()
        self.cancelEnabled = false
        
        // DO NOT call finalizeGeneration() here! We need activeGenerationToken
        // to stay alive so the 8s timer knows who it belongs to.
        
        // 4. START HEALING
        syncHealingController.startCreditHealing(
            token: token,
            isStillSyncing: { [weak self] in
                // Double check it's still the active token when evaluating the sync state
                self?.generationError == .syncingCredits && self?.activeGenerationToken == token
            },
            onCompletion: { [weak self] error in
                self?.finalizeGeneration(for: token, withError: error)
            }
        )
    }
}
