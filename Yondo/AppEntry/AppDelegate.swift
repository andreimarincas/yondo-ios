//
//  AppDelegate.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.03.2026.
//

import UIKit
import FirebaseCore
import FirebaseAppCheck
import RevenueCat

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        Log.debug("🚀 AppDelegate: didFinishLaunchingWithOptions triggered. Beginning SDK boot-up sequence.")
        
        configureFirebase()
        configureRevenueCat()
        
        Log.debug("✅ AppDelegate: Boot-up sequence completed successfully.")
        return true
    }
    
    private func configureFirebase() {
        Log.debug("🔥 Firebase: Configuring AppCheck and core modules.")
        
        // Create a debug provider factory
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        Log.debug("🔥 Firebase: AppCheckDebugProviderFactory attached.")
        
        // Initialize Firebase
        
        // Check if the file exists in the bundle before configuring
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            Log.debug("🔥 Firebase: Found GoogleService-Info.plist at \(path). Running FirebaseApp.configure()")
            FirebaseApp.configure()
            Log.debug("✅ Firebase: Core SDK successfully configured.")
        } else {
            Log.error("❌ Firebase: 💥 GoogleService-Info.plist not found in bundle! Handshake will fail.")
        }
    }
    
    private func configureRevenueCat() {
        Log.debug("🐱 RevenueCat: Configuring SDK and retrieving API keys.")
        
        // Fetch from xcconfig via Info.plist
        let apiKey = Bundle.main.revenueCatKey
        
        if apiKey.isEmpty {
            Log.error("❌ RevenueCat: 💥 API Key is missing! Check your Secrets.xcconfig environment bindings.")
        } else {
            // We only print the first 8 characters for security, even in logs
            let maskedKey = apiKey.prefix(8) + "..."
            Log.debug("🐱 RevenueCat: Retrieved API key from info.plist (Masked: \(maskedKey))")
        }
        
        // Log level .debug is great for seeing transaction flows in the Xcode console
        Purchases.logLevel = .debug // Essential for testing in Sandbox!
        Log.debug("🐱 RevenueCat: Setting internal SDK logLevel to .debug.")
        
        Purchases.configure(withAPIKey: apiKey)
        Log.debug("🐱 RevenueCat: SDK configure() called.")
        
        Purchases.shared.delegate = IAPManager.shared
        Log.debug("🐱 RevenueCat: IAPManager.shared assigned as PurchasesDelegate.")
        
//        Purchases.shared.allowSharingAppStoreAccount = true
        
        Log.debug("✅ RevenueCat: SDK Initialization complete.")
    }
}

extension Bundle {
    var revenueCatKey: String {
        return object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
    }
}
