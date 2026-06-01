//
//  IAPManager+Network.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.03.2026.
//

import Foundation
import RevenueCat

extension IAPManager {
    func observeNetwork() {
        if networkTask != nil {
            Log.debug("IAPManager+Network: 🔄 Restarting network observation. Cancelling previous task.")
            networkTask?.cancel() // Kill any existing observer
        } else {
            Log.debug("IAPManager+Network: 🛰️ Starting network observation.")
        }
        
        networkTask = Task { [weak self] in
            guard let networkMonitor = self?.networkMonitor else {
                Log.error("IAPManager+Network: ❌ Deallocated or missing networkMonitor. Aborting observation.")
                return
            }
            
            Log.debug("IAPManager+Network: ✅ Successfully attached to statusStream.")
            
            // This loop suspends (does nothing) until the monitor yields a value
            for await isConnected in networkMonitor.statusStream {
                guard let self = self else {
                    Log.debug("IAPManager+Network: ⚠️ Self deallocated. Breaking status stream loop.")
                    break
                }
                
                Log.debug("IAPManager+Network: 📶 Stream yielded connection status -> \(isConnected ? "Online" : "Offline")")
                
                // Now you only act when a REAL change happens
                if isConnected {
                    await self.handleNetworkRecovery()
                } else {
                    self.handleNetworkLoss()
                }
            }
        }
    }
    
    @MainActor
    private func handleNetworkRecovery() async {
        Log.debug("IAPManager+Network: 🟢 Network Recovery Detected (Offline -> Online). Checking if UI state needs evaluation.")
        
        // MARK: Transition -> ONLINE 🟢
        // We just got internet back.
        // Only auto-retry if we are currently blocked by a Network/Regional Error.
        if case .error(let error) = loadingState, let storeError = error as? StoreError {
            switch storeError {
                // Consider if you also want to retry if the state is .emptyRegion.
                // Sometimes, a "Regional Error" is actually just a misconfigured proxy
                // or a weird hotel WiFi login page that blocked Apple but didn't "kill" the connection.
                // If they switch to LTE, you might want to try one more time to see if the products appear.
            case .networkIssue(_), .emptyRegion:
                Log.debug("IAPManager+Network: 🟢 Recovery trigger matched current error state [\(storeError)]. Automatically retrying fetch to clear error.")
                await retryFetch()
                
            default:
                break
            }
        } else {
            Log.debug("IAPManager+Network: ℹ️ Network recovered, but UI is currently in state [\(loadingState.debugDescription)]. No automatic retry needed.")
        }
    }
    
    @MainActor
    private func handleNetworkLoss() {
        Log.debug("IAPManager+Network: 🔴 Network Loss Detected (Online -> Offline). Checking if UI needs updating.")
        
        // MARK: Transition -> OFFLINE 🔴
        // We just lost internet.
        // If we are showing "Region Not Supported", update it to "No Internet".
        // This ensures the user sees the correct icon (WiFi) and doesn't try to tap "Check Again" in vain.
        if case .error(let error) = loadingState, let storeError = error as? StoreError, case .emptyRegion = storeError {
            Log.debug("IAPManager+Network: 🔴 Downgrading state from [.emptyRegion] to [.networkIssue] due to connection loss.")
            // Manually switch state without fetching
            self.loadingState = .error(StoreError.networkIssue(URLError(.notConnectedToInternet)))
        }
    }
}
