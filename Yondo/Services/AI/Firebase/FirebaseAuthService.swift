//
//  FirebaseAuthService.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.03.2026.
//

import FirebaseAuth
import FirebaseFirestore

final class FirebaseAuthService: Sendable {
    static let shared = FirebaseAuthService()
    
    /// Returns the current UID, signing in anonymously if necessary
    func ensureAuthenticated() async throws -> String {
        Log.debug("🔐 AuthContext: ensureAuthenticated() called.")
        
        // If we already have a user, just return the ID
        if let currentUser = Auth.auth().currentUser {
            Log.debug("🔐 AuthContext: Found existing cached user session. UID -> [\(currentUser.uid)]")
            return currentUser.uid
        }
        
        // No user found, trigger anonymous sign-in
        // Firebase will keep this session persisted on the device automatically
        Log.debug("🔐 AuthContext: No session found. Spawning new anonymous Auth profile...")
        
        do {
            let result = try await Auth.auth().signInAnonymously()
            Log.debug("✅ AuthContext: Anonymous sign-in successful. New UID -> [\(result.user.uid)]")
            return result.user.uid
        } catch {
            Log.error("❌ AuthContext: Anonymous sign-in failed with error: \(error.localizedDescription)")
            throw error
        }
    }
    
    var currentUID: String? {
        Auth.auth().currentUser?.uid
    }
    
    /**
     * 📂 SHELL FORGERY PATTERN
     * This function ensures that every authenticated user has a corresponding Firestore document.
     * By setting 'hasGrantedFreeCredits' to false, we "prime" the backend to trigger the
     * welcome gift function. This decouples user creation from credit granting for better reliability.
     */
    func ensureUserDocumentExists(userId: String) async {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        
        Log.debug("📂 UserDoc: Validating Firestore Identity document state for UID [\(userId)]...")
        
        do {
            // This is a 'get' call. If the user is returning, we find the doc.
            let doc = try await userRef.getDocument()
            
            if !doc.exists {
                Log.debug("📂 UserDoc: No Firestore Identity document found for [\(userId)]. Forging fresh shell...")
                
                // Create the initial Identity shell. The Cloud Function 'handleWelcomeGift'
                // is listening for this specific write event to build the Wallet.
                try await userRef.setData([
                    // NOTE: 'credits' has been removed! The wallet is built by the backend.
                    "isPremium": false,
                    "hasGrantedFreeCredits": false, // This is the trigger for the Cloud Function
                    "createdAt": FieldValue.serverTimestamp(),
                ])
                
                Log.debug("✅ UserDoc: Successfully forged fresh Identity shell for [\(userId)]. Waiting for server-side gift handshake...")
            } else {
                Log.debug("📂 UserDoc: ℹ️ Pre-existing Firestore Identity document verified for [\(userId)]. Skipping shell forgery.")
            }
        } catch {
            Log.error("❌ UserDoc: Firestore document check/creation failed for [\(userId)] with error: \(error.localizedDescription)")
        }
    }
}
