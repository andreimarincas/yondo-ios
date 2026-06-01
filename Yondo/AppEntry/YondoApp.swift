//
//  YondoApp.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.12.2025.
//

import SwiftUI
import SwiftData

@main
struct YondoApp: App {
    // Register the delegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Using a static ID to track if the App process itself is killed/restarted
    private let appInstanceID = UUID().uuidString
    
    // Initialize the container for RemoteGeneration
    // Using 'let' ensures the container is created once and persists
    let sharedModelContainer: ModelContainer = {
        Log.debug("🚀 App: Initializing SwiftData ModelContainer.")
        let schema = Schema([
            RemoteGeneration.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            Log.debug("✅ App: SwiftData ModelContainer successfully established.")
            
            // Warming up the persistent store on a background thread
            Task.detached {
                Log.debug("⚡ SwiftData: Background warm-up started")
                // Create a background ModelContext to initialize the persistent stack
                let warmupContext = ModelContext(container)
                warmupContext.autosaveEnabled = false
                // Perform a harmless fetch to ensure the store is loaded
                do {
                    let descriptor = FetchDescriptor<RemoteGeneration>(predicate: nil, sortBy: [])
                    _ = try warmupContext.fetch(descriptor)
                } catch {
                    Log.debug("ℹ️ SwiftData: Warm-up fetch encountered an error: \(error.localizedDescription)")
                }
                Log.debug("✅ SwiftData: Background warm-up finished.")
            }
            
            return container
        } catch {
            Log.error("❌ App: Fatal Error! Could not create SwiftData ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        Log.debug("🚀 App: init() triggered. Setting up global UIKit styles and scene builders.")
        Log.debug("🎬 App: [Instance \(appInstanceID)] init() triggered.")
        
        // UI Infrastructure (Keep here)
        configureGlobalStyles()
        
        // SwiftData & Manager setup
        // Since this is now lazy, it won't crash even if AppDelegate hasn't finished.
        SceneBuilderManager.shared.setup(with: sharedModelContainer)
        Log.debug("✅ App: SceneBuilderManager attached to persistent container context.")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    Log.debug("🖼️ App: RootView appeared in WindowGroup [Instance \(appInstanceID)].")
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    // MARK: - Setup
    
    private func configureGlobalStyles() {
        Log.debug("🎨 AppStyle: Applying global UIKit overrides.")
        configureSegmentedControlAppearance()
        configureNavigationBarAppearance()
    }
    
    private func configureSegmentedControlAppearance() {
        // Segmented Control
        let segmentAppearance = UISegmentedControl.appearance()
        segmentAppearance.selectedSegmentTintColor = UIColor(.yondoBrand)
        
        // Makes the non-selected parts look more like glass
        segmentAppearance.backgroundColor = UIColor.systemFill.withAlphaComponent(0.1)
        
        // Set the Rounded Font for the UNSELECTED state
        segmentAppearance.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 13, weight: .medium).rounded(),
            .foregroundColor: UIColor.dynamicSegmentUnselected
        ], for: .normal)
        
        // Set the Rounded Font for the SELECTED state
        segmentAppearance.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 13, weight: .bold).rounded(), // Bold makes it "pop"
            .foregroundColor: UIColor.white
        ], for: .selected)
        
        Log.debug("🎨 AppStyle: UISegmentedControl global appearance constraints applied.")
    }
    
    private func configureNavigationBarAppearance() {
        // Navigation Bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground() // Liquid Glass look
        navAppearance.shadowColor = .clear // Extra insurance against the line
        
//        let barButtonAppearance = UIBarButtonItemAppearance(style: .plain)
//        
//        let attributes: [NSAttributedString.Key: Any] = [
//            .font: UIFont.systemFont(
//                ofSize: ToolbarButtonType.dismiss.fontSize,
//                weight: ToolbarButtonType.dismiss.fontWeight.uiFontWeight()).rounded(),
//            .foregroundColor: UIColor.red//label.withAlphaComponent(ToolbarButtonType.dismiss.opacity)
//        ]
//        
//        // Apply attributes to all states (normal and pressed)
//        barButtonAppearance.normal.titleTextAttributes = attributes
//        barButtonAppearance.highlighted.titleTextAttributes = attributes
//        
//        // 2. Apply to Back Button specifically
//        navAppearance.backButtonAppearance = barButtonAppearance
//        
//        let imageConfig = UIImage.SymbolConfiguration(pointSize: 16.5, weight: .bold)
//        let backImage = UIImage(systemName: "chevron.left", withConfiguration: imageConfig)
//        navAppearance.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        
        // This targets the "New Yondo" title when it's small (Inline)
//        navAppearance.titleTextAttributes = [
//            .font: UIFont.systemFont(ofSize: 17, weight: .semibold).rounded(),
//            .foregroundColor: UIColor.label
//        ]
        
        // This targets it if you ever use Large Titles
//        navAppearance.largeTitleTextAttributes = [
//            .font: UIFont.systemFont(ofSize: 34, weight: .bold).rounded()
//        ]
        
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        
        Log.debug("🎨 AppStyle: UINavigationBar liquid glass/transparent constraints applied.")
    }
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets = EdgeInsets()
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

extension UIFont.Weight {
    init(_ fontWeight: Font.Weight) {
        switch fontWeight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .regular: self = .regular
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .black: self = .black
        default: self = .regular
        }
    }
}

extension Font.Weight {
    func uiFontWeight() -> UIFont.Weight {
        return UIFont.Weight(self)
    }
}

