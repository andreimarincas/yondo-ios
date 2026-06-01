//
//  HapticManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.12.2025.
//

import UIKit

/// Singleton manager for triggering haptic feedback throughout the app.
/// Provides impact, selection, and notification feedback generators.
final class HapticManager {
    static let shared = HapticManager()
    
    private(set) lazy var lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private(set) lazy var mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private(set) lazy var heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private(set) lazy var selectionGenerator = UISelectionFeedbackGenerator()
    private(set) lazy var notificationGenerator = UINotificationFeedbackGenerator()
    private(set) lazy var softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private(set) lazy var rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    
    private init() {
        // The init is now empty and near-instant
//        Log.debug("📳 Haptics: Initializing singleton and preparing engine hardware.")
    }
    
    /// Call this when the app reaches an idle state (e.g. ScenesHomeView onAppear)
    /// to wake up the hardware without blocking a button tap.
    func prewarm() {
        Task(priority: .background) {
            // Accessing them here triggers the lazy initialization
            // and hardware prep off the main thread.
            lightImpactGenerator.prepare()
            mediumImpactGenerator.prepare()
            selectionGenerator.prepare()
            notificationGenerator.prepare()
            softImpactGenerator.prepare()
            rigidGenerator.prepare()
            
            Log.debug("📳 Haptics: Background pre-warm complete.")
        }
    }
    
    /// Trigger light impact feedback.
    func lightImpact() {
        Log.debug("📳 Haptics: Dispatching lightImpact.")
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare()  // ready for next
    }
    
    func softImpact(intensity: CGFloat = 1.0) {
        Log.debug("📳 Haptics: Dispatching softImpact (Intensity: \(intensity)).")
        softImpactGenerator.impactOccurred(intensity: intensity)
        softImpactGenerator.prepare()
    }
    
    func mediumImpact(intensity: CGFloat = 1.0) {
        Log.debug("📳 Haptics: Dispatching mediumImpact (Intensity: \(intensity)).")
        mediumImpactGenerator.impactOccurred(intensity: intensity)
        mediumImpactGenerator.prepare()
    }
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        Log.debug("📳 Haptics: Dispatching impact style [\(style.rawValue)].")
        switch style {
        case .light:
            lightImpactGenerator.impactOccurred()
            lightImpactGenerator.prepare()
        case .medium:
            mediumImpactGenerator.impactOccurred()
            mediumImpactGenerator.prepare()
        case .heavy:
            heavyImpactGenerator.impactOccurred()
            heavyImpactGenerator.prepare()
        case .soft:
            softImpactGenerator.impactOccurred()
            softImpactGenerator.prepare()
        case .rigid:
            // Added modern UIKit fallback support (iOS 13+)
            rigidGenerator.impactOccurred()
            rigidGenerator.prepare()
        @unknown default:
            Log.debug("📳 Haptics: Style default fallback triggered.")
            lightImpactGenerator.impactOccurred()
            lightImpactGenerator.prepare()
        }
    }
    
    /// Trigger selection change feedback.
    func select() {
        Log.debug("📳 Haptics: Dispatching select.")
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()  // ready for next
    }
    
    /// Trigger success notification feedback.
    func success() {
        Log.debug("📳 Haptics: Dispatching notification sequence SUCCESS.")
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()  
    }
    
    func failure() {
        Log.debug("📳 Haptics: Dispatching notification sequence FAILURE (Error).")
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
    
    func softSuccess() {
        Log.debug("📳 Haptics: Dispatching custom 'softSuccess' sequence (Light -> 0.2s pause -> Medium).")
        
        self.lightImpactGenerator.prepare()
        self.lightImpactGenerator.impactOccurred(intensity: 0.5)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Log.debug("📳 Haptics: Completing 'softSuccess' sequence on main thread.")
            self.mediumImpactGenerator.prepare()
            self.mediumImpactGenerator.impactOccurred(intensity: 0.8)
        }
    }
}
