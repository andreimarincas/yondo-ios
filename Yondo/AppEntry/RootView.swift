//
//  RootView.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.02.2026.
//

import SwiftUI

struct RootView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var safeAreaInsets = EdgeInsets()
    
    // 🔑 This ensures the gallery (and its presented covers) survives AuthManager updates.
    @State private var mainGallery = ScenesHomeView()
    
    var body: some View {
        ZStack {
            // 🏠 The Permanent Home
            mainGallery
                .environmentObject(authManager)
                .environment(\.safeAreaInsets, safeAreaInsets)
                .ignoresSafeArea()
                .id("main-gallery")
                .onAppear {
                    Log.debug("🏠 RootView: ScenesHomeView mounted.")
                }
            
            // ⛈️ The Transient Overlay
            if !authManager.isInitialized {
                SplashView(showsSpinner: authManager.isSyncingSlowly)
                    .ignoresSafeArea()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
                    .id("splash-view")
                    .zIndex(1)
                    .onAppear { Log.debug("⏳ RootView: SplashView appeared.") }
                    .onDisappear { Log.debug("✨ RootView: SplashView dismissed.") }
            }
            
            Color.clear
                .measureSafeArea { insets in
                    safeAreaInsets = insets
                }
        }
        .task {
            Log.debug("🚀 RootView: Bootstrap triggered.")
            await authManager.bootstrap()
        }
        .onChange(of: authManager.isInitialized) { _, newValue in
            Log.debug("🔄 RootView: isInitialized changed to \(newValue)")
        }
    }
}

// The "No-Fuss" Helper
extension View {
    func measureSafeArea(onChange: @escaping (EdgeInsets) -> Void) -> some View {
        self.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.safeAreaInsets) }
                    // Update on rotation or Dynamic Island expansion
                    .onChange(of: proxy.safeAreaInsets) { _, newValue in
                        onChange(newValue)
                    }
            }
        )
    }
}
