//
//  IAPManager+Auth.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.03.2026.
//

import Foundation
import RevenueCat

extension IAPManager {
    /// Guarantees that Firebase, RevenueCat, and all local app silos are unified under the current
    /// Firebase UID before presenting a paywall or accepting real money.
    func ensureAuthenticated() async throws {
        let firebaseUID: String
        
        do {
            // 1. Resolve Global State
            // Because AuthManager waits for its internal TaskGroup to finish,
            // this technically guarantees that RevenueCat is ALREADY logged in.
            firebaseUID = try await AuthManager.shared.ensureGlobalAuthentication()
        } catch {
            Log.error("IAPManager+RC: ❌ Global authentication failed: \(error.localizedDescription)")
            throw StoreError.missingUser
        }
        
        // 2. 🛡️ DEFENSIVE INVARIANT CHECK (Belt & Suspenders)
        // Even though step 1 successfully resolved, we double-check the RevenueCat SDK
        // directly. If a background thread reset the cache or if AuthManager is
        // modified in the future to skip RC login, this check keeps the Paywall autonomous.
        if Purchases.shared.appUserID != firebaseUID {
            Log.debug("IAPManager+RC: ⚠️ Identity mismatch or cache drop in RC. Forcing logIn for \(firebaseUID)...")
            
            do {
                _ = try await Purchases.shared.logIn(firebaseUID)
                Log.debug("IAPManager+RC: ✅ RevenueCat successfully bridged to Firebase UID.")
            } catch {
                Log.error("IAPManager+RC: ❌ Failed to bridge RevenueCat identity: \(error.localizedDescription)")
                throw StoreError.missingUser
            }
        } else {
            Log.debug("IAPManager+RC: ✅ RevenueCat is successfully verified and bound to Firebase.")
        }
    }
}
