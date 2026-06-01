//
//  AuthManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 13.03.2026.
//

import SwiftUI
import FirebaseAuth
import Combine
import RevenueCat

/// Orchestrates the app's authentication state and coordinates data silos.
/// Mark the whole class as main actore to prevents accidental background-thread property updates.
@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isInitialized = false
    @Published var isSyncingSlowly = false
    @Published var hasRevealedApp = false
    @Published var sessionID: String? = FirebaseAuthService.shared.currentUID
    
    /// The "Shield": Prevents multiple concurrent identity shifts
    private var activeAuthTask: Task<String, Error>?
    
    @MainActor
    func bootstrap() async {
        let startTime = Date()
        Log.debug("🎬 [BOOT]: Starting bootstrap boot-up sequence...")
        
        // 1. Start a "patience" timer for the spinner
        let spinnerTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled {
                Log.debug("🎬 [BOOT]: Boot took longer than 1.5s. Rendering 'isSyncingSlowly' UI fallback.")
                withAnimation { self.isSyncingSlowly = true }
            }
        }
        
        // 🔥 Start warming up hardware IMMEDIATELY in the background.
        // We do NOT await this so it doesn't eat into the 1.5s handshake budget.
        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(0.5))
            await HapticManager.shared.prewarm()
        }
        
        // 2. Perform the actual work
        // e.g., await checkKeychainAndFirebase()
        await performHandshake()
        
        // Cancel the spinner task if the work finished fast
        spinnerTask.cancel()
        Log.debug("🎬 [BOOT]: Handshake finished in \(String(format: "%.2fs", Date().timeIntervalSince(startTime)))")
        
        // 3. Enforce the 1.25s pulse "floor"
        let elapsed = Date().timeIntervalSince(startTime)
        let targetDelay = 0.75 // 1.25
        
        if elapsed < targetDelay {
            let padding = targetDelay - elapsed
            Log.debug("🎬 [BOOT]: Padding launch splash screen for an extra \(String(format: "%.2fs", padding)) to prevent UI flashing.")
            try? await Task.sleep(for: .seconds(padding))
        } else {
            Log.debug("🎬 [BOOT]: Launch handshake took \(String(format: "%.2fs", elapsed)) (No padding needed).")
        }
        
        // 4. Reveal the app
        // We stay on @MainActor, so no need for DispatchQueue.main.async
        AppLaunchContext.isAppLaunching = false
        
        // The big cross-dissolve transition
        Log.debug("🎬 [BOOT]: Initializing App UI cross-dissolve.")
        withAnimation(.easeInOut(duration: 0.35)) {
            self.isInitialized = true
        }
        
        // Wait for the fade to nearly finish, then trigger the internal Hero animations
        // 0.25s gives the splash time to disappear so the Empty State "insertion" is fresh
        try? await Task.sleep(for: .seconds(0.25))
        Log.debug("🎬 [BOOT]: Triggering Hero view reveal animations.")
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            self.hasRevealedApp = true
        }
    }
    
    /**
     * 🤝 THE HANDSHAKE
     * This routine synchronizes all core services in a strict order:
     * 1. Auth (Identify the user)
     * 2. Firestore (Create the shell for the user)
     * 3. RevenueCat (Link the identity for billing)
     * 4. FirebaseSyncService (Start listening for the Cloud Function to finish the gift)
     */
    private func performHandshake() async {
        Log.debug("🤝 Handshake: Beginning handshake routines.")
        
        let authService = FirebaseAuthService.shared
        let imageStore = ImageStore.shared
        let iapManager = IAPManager.shared
        let syncService = FirebaseSyncService.shared
        
        var userId = authService.currentUID
        
        do {
            // PHASE 1: IDENTITY
            if userId == nil {
                Log.debug("🤝 Handshake: No cached UID found. Attempting anonymous ensuresAuthenticated().")
                userId = try await authService.ensureAuthenticated()
            } else {
                Log.debug("🤝 Handshake: Found cached UID -> \(userId!)")
            }
            
            // PHASE 2: ONLINE RESOLUTION - Resolve Online Silos (Only happens if Auth succeeds)
            if let userId = userId {
                // A) Ensure Firestore Doc exists
                Log.debug("🤝 Handshake: Validating Firestore user document existence for \(userId)...")
                
                // We call this before IAP sync to ensure the doc is ready
                // for any immediate 'linkPremium' calls from the RC Delegate.
                await authService.ensureUserDocumentExists(userId: userId)
                
                // Sync Firebase User with RevenueCat
                do {
                    // B) Identify the user to RevenueCat for server-side subscription hooks
                    Log.debug("🤝 Handshake: Syncing RevenueCat with Firebase UID: \(userId)...")
                    
                    // This links the Firebase UID to the RevenueCat CustomerInfo
                    let (_, created) = try await Purchases.shared.logIn(userId)
                    Log.debug("✅ Handshake: RevenueCat Synced! New User created on RC: \(created)")
                } catch {
                    Log.error("❌ Handshake: Sync Firebase User with RevenueCat failed: \(error.localizedDescription)")
                }
                
                // C) Start Real-time Listening
                Log.debug("🤝 Handshake: Attaching real-time FirebaseSyncService pipe.")
                
                // This listener will react when the 'handleWelcomeGift' function
                // eventually updates the credit count from 0 to 3.
                syncService.startSync(for: userId)
            }
            
//            await iapManager.creditStore.resetAll()
//            await nuclearReset()
            
            Log.debug("✅ Handshake: Handshake routines completed successfully.")
        } catch {
            // Handled gracefully! The app will boot into an "offline/local" state.
            Log.error("❌ Handshake: Core handshake failed with error: \(error.localizedDescription)")
        }
        
        // PHASE 3: HYDRATION (Always runs to ensure UI is ready)
        // Resolve Local/Hydration Silos (ALWAYS executes, regardless of Auth status)
        
        // Initialize the Store and IAP (Keychain bucket)
        Log.debug("🤝 Handshake: Booting IAPManager State.")
        
        // If Auth failed, this safely falls back to "anonymous" / nil
        await iapManager.start(userId: userId)
        
        // Explicitly initialize the Selfie Store with the resolved ID!
        Log.debug("🤝 Handshake: Booting LastSelfieStore...")
        await LastSelfieStore.shared.initialize(with: userId)
        
        // Finish ImageStore and UI Reveal...
        Log.debug("🤝 Handshake: Initializing ImageStore...")
        
        imageStore.initialize()
        await imageStore.waitForReady()
        
        // Push the session UID to local memory
        let currentUserId = authService.currentUID
        if currentUserId != self.sessionID {
            Log.debug("🤝 Handshake: sessionID shifted from [\(self.sessionID ?? "none")] to [\(currentUserId ?? "local")].")
            self.sessionID = currentUserId
        }
        
//        try? await Task.sleep(for: .seconds(15.0)) // Simulation
        
//        await nuclearReset()
        Log.debug("✅ Handshake: Handshake routines completed successfully (Offline context preserved).")
    }
    
    // MARK: - Identity Management
    
    func ensureGlobalAuthentication() async throws -> String {
        // If a shift is already in progress, just wait for it and return its result
        if let existingTask = activeAuthTask {
            Log.debug("🎬 Auth: 🛡️ Hooking into existing auth task already in progress.")
            return try await existingTask.value
        }
        
        // Create a new task and store it
        let newTask = Task {
            return try await self.performIdentitySync()
        }
        
        self.activeAuthTask = newTask
        
        // Clean up when finished (use defer to ensure it clears even on failure)
        defer { self.activeAuthTask = nil }
        
        return try await newTask.value
    }
    
    /// Safely ensures authentication and synchronizes all local stores if a late-identity shift occurs.
    ///
    /// This method uses **Atomic Success** to handle identity migrations.
    /// It executes all domain shifts in parallel (Firestore, RevenueCat, ImageStore, and Keychain).
    ///
    /// - Important: By calling `try await group.waitForAll()`, we guarantee that:
    ///   1. All sibling tasks are allowed to run to completion (no early data truncation).
    ///   2. The method awaits physical file renaming and cache-clearing before returning.
    ///   3. If any critical network identity bound throws (e.g., RevenueCat), the entire shift is
    ///      re-thrown as a failure to prevent state fragmentation.
    ///
    /// - Returns: The unified `String` representing the active Firebase UID.
    @MainActor
    func performIdentitySync() async throws -> String {
        Log.debug("🎬 [SYNC] Resolving Firebase identity...")
        
        // 1. Resolve Identity
        let resolvedUID = try await FirebaseAuthService.shared.ensureAuthenticated()
        
        // 2. Check for Shift
        if resolvedUID != self.sessionID {
            Log.debug("🎬 [SYNC] 🔄 Late Shift detected. Syncing silo identities...")
            
            // 3. Parallel Execution (Wait for all to finish)
            // We use a TaskGroup to update everything at once
            try await withThrowingTaskGroup(of: Void.self) { group in
                
                // SILO 1: Firestore Document (Crucial for API calls)
                group.addTask {
                    Log.debug("📦 [SYNC] Silo 1: Firestore")
                    await FirebaseAuthService.shared.ensureUserDocumentExists(userId: resolvedUID)
                }
                
                // SILO 2: RevenueCat Identity (Crucial for Purchases)
                group.addTask {
                    Log.debug("📦 [SYNC] Silo 2: RevenueCat")
                    // RevenueCat checks if the user is already logged in with that ID.
                    // If yes, it skips network traffic and returns the cache.
                    _ = try await Purchases.shared.logIn(resolvedUID)
                }
                
                // SILO 3: ImageStore (Disk Migration & Cache)
                group.addTask {
                    Log.debug("📦 [SYNC] Silo 3: ImageStore")
                    await ImageStore.shared.updateIdentity(newUserId: resolvedUID)
                }
                
                // SILO 4: SecureCreditStore & IAPManager Network Hydration
                group.addTask {
                    Log.debug("📦 [SYNC] Silo 4: CreditStore & IAP Hydration")
                    
                    // 1. Shift the local Keychain identity (Wipes old credits, loads new local ones)
                    await IAPManager.shared.creditStore.updateIdentity(userId: resolvedUID)
                    
                    // 2. Trigger the network fetch for products/entitlements for the NEW user
                    await IAPManager.shared.start(userId: resolvedUID)
                }
                
                // SILO 5: LastSelfieStore Identity Shift
                group.addTask {
                    Log.debug("📦 [SYNC] Silo 5: LastSelfieStore")
                    await LastSelfieStore.shared.updateIdentity(newUserId: resolvedUID)
                }
                
                // 🛑 Wait for all sibling tasks to complete. If any tasks (like RevenueCat logIn)
                // threw an error, this will rethrow the first encountered error up to the caller
                // while ensuring that the filesystem and Keychain tasks were allowed to finish.
                try await group.waitForAll()
            }
            
            // ✅ SUCCESS: Update the AuthManager's local pointer
            self.sessionID = resolvedUID
            
            // 4. Restart Real-time listeners
            Log.debug("🎬 [SYNC] Re-starting real-time listeners...")
            FirebaseSyncService.shared.startSync(for: resolvedUID)
            
            Log.debug("✅ [SYNC] Global Identity Sync Complete for [\(resolvedUID)]")
        } else {
            Log.debug("🎬 [SYNC] No identity shift required.")
        }
        
        return resolvedUID
    }
    
    // MARK: - Cleanup
    
    @MainActor
    func logout() async {
        Log.debug("🚪 LOGOUT: Starting cleanup...")
        
        // Instantly cover the screen with the SplashView while the background works!
        withAnimation(.easeInOut(duration: 0.25)) {
            self.isInitialized = false
            self.hasRevealedApp = false // Reset hero animations
            self.sessionID = nil
        }
        
        // Stop the Listener (Stop the "Incoming" pipe)
        // This prevents any late-arriving Firestore snapshots from
        // trying to update the store while we are wiping it.
        Log.debug("🚪 Logout: Severing real-time Firebase syncing pipes.")
        FirebaseSyncService.shared.stopSync()
        
        // Clear Firebase session
        do {
            // Firebase Auth Sign Out (Revoke the "ID Card")
            try Auth.auth().signOut()
            Log.debug("🚪 LOGOUT: Firebase Auth signed out.")
        } catch {
            Log.error("❌ Logout: Firebase sign out failed: \(error.localizedDescription)")
        }
        
        // Clear RevenueCat session
        do {
            // Tell RevenueCat to clear its cache for this user
            // This ensures the next user doesn't inherit the previous user's receipt.
            _ = try await Purchases.shared.logOut()
            Log.debug("🚪 Logout: RevenueCat customerInfo cached states dumped.")
        } catch {
            Log.error("❌ Logout: RevenueCat failed to log out: \(error.localizedDescription)")
        }
        
        // Reset the store back to anonymous/zero
        Log.debug("🚪 Logout: Stripping local CreditStore identities.")
        await IAPManager.shared.creditStore.updateIdentity(userId: "anonymous")
        
        // Update ImageStore to "local" or nil to wipe the gallery UI,
        // so the next user doesn't see the previous user's gallery for a split second
        Log.debug("🚪 Logout: Resetting ImageStore to 'local'.")
        await ImageStore.shared.updateIdentity(newUserId: "local")
        
        // Reset the Selfie store to anonymous
        Log.debug("🚪 Logout: Stripping LastSelfieStore identity.")
        await LastSelfieStore.shared.updateIdentity(newUserId: "local")
        
        Log.debug("✅ LOGOUT: Cleanup complete.")
    }
    
    func nuclearReset() async {
        // 1. Sign out of Firebase (This clears the internal Keychain cache)
        try? Auth.auth().signOut()
        
        // 2. Log out of RevenueCat
        Purchases.shared.logOut { (customerInfo, error) in
            Log.debug("RevenueCat Logged Out")
        }
        
        // 3. Clear your local store
        await IAPManager.shared.creditStore.resetAll()
    }
}
