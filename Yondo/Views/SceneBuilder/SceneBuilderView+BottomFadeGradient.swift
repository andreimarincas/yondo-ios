//
//  SceneBuilderView+BottomFadeGradient.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    var bottomFadeGradient: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        // This "Anchor" stop ensures the fade starts softly
                        // and gets fully opaque exactly where the tray begins.
                        .init(color: colorScheme == .dark ? .black : .white, location: 0.7),
                        .init(color: colorScheme == .dark ? .black : .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .bottom)
            .frame(height: LiquidGlassTrayLayoutConstants.trayHeight + 80)
            .allowsHitTesting(false)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.4), // Fade starts here
                        .init(color: .black, location: 0.5), // Fully opaque for a moment
//                        .init(color: .clear, location: 0.6)  // Becomes clear exactly where glass starts
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Ensure the initial state is strictly enforced
            .opacity(isAnimatingIn ? 1.0 : 0.0)
            .offset(y: isAnimatingIn ? 0 : 60)
            // Apply the animation ONLY to this specific rectangle
            .animation(
                .spring(response: 0.6, dampingFraction: 0.8).delay(0.25),
                value: isAnimatingIn
            )
    }
}
