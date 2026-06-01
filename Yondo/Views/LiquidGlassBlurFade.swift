//
//  LiquidGlassBlurFade.swift
//  Yondo
//
//  Created by Andrei Marincas on 05.04.2026.
//

import SwiftUI

struct LiquidGlassBlurFade: View {
    @Environment(\.colorScheme) var colorScheme
    
    let isPressed: Bool
    
    var body: some View {
        ZStack {
            Color.clear
                .glassEffect(
                    .regular.tint(
                        colorScheme == .light ? Color(white: 0.96) : Color.black
                    ),
                    in: Rectangle()
                )
                .ignoresSafeArea(.container, edges: .bottom)
                .padding(.bottom, -300) // Ensures blur extends past the screen edge
        }
        .frame(height: LiquidGlassTrayLayoutConstants.trayHeight + 80)
        .allowsHitTesting(false) // Clicks pass through the blur to the ScrollView
        .mask {
            ZStack(alignment: .bottom) {
                // 1. The Main Gradient Fade
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.6), location: 0.22),
                        .init(color: .black.opacity(0.8), location: 0.5),
                        .init(color: .black.opacity(1.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(.container, edges: .bottom)
                .padding(.bottom, -300)
                
                // 2. The "Cutter" (Creates a hole for the Tray)
                RoundedRectangle(cornerRadius: LiquidGlassTrayLayoutConstants.trayCornerRadius, style: .continuous)
                    // INSET BY 1: Creates a sub-pixel "light trap" that forces the tray's
                    // glass rim to sample blurred pixels instead of sharp background content.
                    // This prevents high-contrast "light leaks" and ensures a uniform glow.
                    .inset(by: 1)
                    .frame(height: LiquidGlassTrayLayoutConstants.trayHeight)
                    .padding(.horizontal, LiquidGlassTrayLayoutConstants.trayPadding)
                    .padding(.bottom, LiquidGlassTrayLayoutConstants.trayPadding)
                    .blendMode(.destinationOut)
                    .scaleEffect(isPressed ? 0.97 : 1.0)
            }
            .compositingGroup()
            .animation(.spring(response: 0.35, dampingFraction: 1.0), value: isPressed)
        }
    }
}
