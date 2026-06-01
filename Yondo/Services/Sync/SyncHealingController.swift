//
//  SyncHealingController.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.04.2026.
//

import Foundation

@MainActor
/**
 * @controller Sync Healing Mechanism
 * ARCHITECTURAL ROLE: Conflict Resolver.
 * * TRIGGER: Triggered by a backend 403 (Premium Required) when local state is True.
 * THE 3-4-1 WINDOW:
 * 1. [3s] Wait for natural webhook propagation.
 * 2. [4s] Execute a forced server-side verification (Healer).
 * 3. [1s] Final buffer before resolving the UI state.
 */
final class SyncHealingController {
    private var syncHealingTask: Task<Void, Never>?
    
    // MARK: Dependencies
    private let iapProvider: CreditProvider
    private let syncService: SyncService
    
    init(iapProvider: CreditProvider, syncService: SyncService) {
        self.iapProvider = iapProvider
        self.syncService = syncService
    }
    
    func cancel() {
        syncHealingTask?.cancel()
        syncHealingTask = nil
    }
    
    /// Executes the healing window for Premium Unlock conflicts.
    func startPremiumHealing(
        token: GenerationToken,
        destinationName: String?,
        isStillSyncing: @escaping () -> Bool,
        onCompletion: @escaping (SceneGenerationError?) -> Void
    ) {
        cancel()
        
        syncHealingTask = Task { [iapProvider] in
            do {
                // Phase 1: Grace period for natural webhooks (3s)
                // Give the RevenueCat Webhook time to hit Firestore naturally.
                try await Task.sleep(for: .seconds(3))
                
                // Phase 2: Manual Kick (Force check)
                // The 'Healer' call. We timeout at 4s to ensure the user isn't
                // stuck on a loading spinner forever if the RC API is down.
                do {
                    Log.debug("⏰ 3s passed. Premium silent. Refreshing entitlements (4s max)...")
                    try await Task.runWithTimeout(seconds: 4) {
                        _ = await iapProvider.refreshEntitlements(force: true)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // timeout
                    Log.warning("⚠️ Premium healing attempt finished with error: \(error.localizedDescription)")
                }
                
                // Phase 3: Buffer (1s)
                try await Task.sleep(for: .seconds(1))
                
                // Phase 4: Resolve
                // If the store is STILL not premium after the 3-4-1 window,
                // we finally accept the server's 'False' and show the Hard Lock.
                // If the store is premium, the 'requires premium unlock' error
                // gets resolved on UI and user can try again.
                if isStillSyncing() {
                    Log.debug("🚑 [\(token.id.uuidString.prefix(8))] Premium Sync Timeout. Showing hard Lock.")
                    onCompletion(.requiresPremiumUnlock(destinationName: destinationName))
                } else {
                    Log.debug("✅ [\(token.id.uuidString.prefix(8))] Premium Sync Success: UI already transitioned.")
                    onCompletion(nil)
                }
            } catch {
                Log.debug("🛑 Premium Sync Window [\(token.id)] was cancelled.")
                onCompletion(.requiresPremiumUnlock(destinationName: destinationName))
            }
        }
    }
    
    /// Executes the healing window for Credit balance conflicts.
    func startCreditHealing(
        token: GenerationToken,
        isStillSyncing: @escaping () -> Bool,
        onCompletion: @escaping (SceneGenerationError?) -> Void
    ) {
        cancel()
        
        syncHealingTask = Task { [syncService] in
            do {
                // Phase 1: Wait for background listener (3s)
                try await Task.sleep(for: .seconds(3))
                
                // Phase 2: Force cloud refresh
                do {
                    Log.debug("⏰ 3s passed. Snapshot listener silent. Forcing cloud refresh...")
                    try await Task.runWithTimeout(seconds: 4) {
                        await syncService.forceRefreshFromCloud()
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Log.warning("⚠️ Cloud refresh failed or timed out. Proceeding to hard error.")
                }
                
                // Phase 3: Buffer (1s)
                try await Task.sleep(for: .seconds(1))
                
                // Phase 4: Resolve
                if isStillSyncing() {
                    Log.debug("🚑 [\(token.id.uuidString.prefix(8))] Heal Timeout: Forcing .insufficientCredits.")
                    onCompletion(.insufficientCredits)
                } else {
                    Log.debug("✅ [\(token.id.uuidString.prefix(8))] Heal Success: UI already transitioned.")
                    onCompletion(nil)
                }
            } catch {
                Log.debug("🛑 Credit Sync Window [\(token.id)] was cancelled.")
                onCompletion(.insufficientCredits)
            }
        }
    }
}
