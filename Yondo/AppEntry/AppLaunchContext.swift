//
//  AppLaunchContext.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.02.2026.
//

/// Manages the global lifecycle state for the app's initial boot.
enum AppLaunchContext {
    /// A one-way "Cold Start" flag.
    /// - True: The app is in its first 500ms of life. Animations are disabled
    ///   to allow for "Instant-On" snapping if the disk cache is hot.
    /// - False: The app has settled. Animations are enabled for a "Graceful Arrival"
    ///   of content and a smooth user experience.
    /// Note: This is never reset to true during the app's process lifetime.
    static var isAppLaunching = true
    
    /// Time window to allow for "Instant-On" snapping (seconds)
    static let snapWindow: Double = 0.5
    
    /// Max time to wait for images before forcing a fade-in (seconds)
    static let safetyFallbackTimeout: Double = 1.5
}
