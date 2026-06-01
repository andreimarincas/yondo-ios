//
//  YondoGlassButtonStyle.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.02.2026.
//

import SwiftUI

struct YondoGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.bold)
            .foregroundStyle(.white)
            // A microscopic shadow to prevent "bleeding" into the blue background
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 1, x: 0, y: 1)
            .padding(.vertical, 18)
            .padding(.horizontal, 32)
            .background { glassPortalBackground(configuration: configuration) }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            // 1. Core Shadow: Dark and tight to ground the button
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.1),
                radius: 5, x: 0, y: 4
            )
            // 2. The "Aura": Very subtle colored glow
            .shadow(
                color: Color.yondoInteractive.opacity(colorScheme == .dark ? 0.2 : 0.1),
                radius: configuration.isPressed ? 4 : (colorScheme == .dark ? 20 : 12),
                x: 0, y: 8
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
    
    private func glassPortalBackground(configuration: Configuration) -> some View {
        ZStack {
            basePortalGradient(configuration: configuration)
            specularStack(configuration: configuration)
            innerAtmosphericShadow
        }
    }
    
    private func basePortalGradient(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.yondoBrand, .yondoDeep], // Use solid blue to deep navy
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // 1. SATURATION: Increases on press to make the blue "pop"
            .saturation(configuration.isPressed ? 1.3 : 1.0)
            
            // 2. BRIGHTNESS: Slightly darker on press to show "depth"
            // In Dark mode, we drop it less (-0.03) so it doesn't disappear.
            .brightness(configuration.isPressed ? (colorScheme == .dark ? -0.03 : -0.07) : 0)
            
            // 3. THE "INNER GLOW" OVERLAY:
            // Only shows up (or gets stronger) when pressed
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.2 : 0), lineWidth: 1)
                    .blur(radius: 1)
            }
    }
    
    private func cornerGlint(configuration: Configuration) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    // Use yondoGlow for a "colored" light hit instead of pure white
                    colors: [.yondoGlow.opacity(colorScheme == .dark ? 0.5 : 0.25), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 60
                )
            )
            .frame(width: 120, height: 120)
            // 🔑 THE FIX: Move it FURTHER out (-70) rather than in (-45)
            // This makes the highlight "shrink" into the corner
            .offset(
                x: configuration.isPressed ? -75 : -60,
                y: configuration.isPressed ? -75 : -60
            )
            // Dim the opacity slightly on press so it doesn't "pop" too hard in dark mode
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            // It also subtly shrinks, suggesting the "surface" moved away from the light
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .blur(radius: 5)
            .blendMode(colorScheme == .dark ? .plusLighter : .normal)
            // Smooth out the movement
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
    
    private var innerAtmosphericShadow: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            // Use yondoMidnight instead of black for a "colorful" shadow
            .stroke(Color.yondoMidnight.opacity(0.3), lineWidth: 2)
            .blur(radius: 3)
            .offset(y: 2)
            .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func specularStack(configuration: ButtonStyleConfiguration) -> some View {
        Group {
            // A. The "Top Lip" Highlight (No change here)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.6 : 0.3),
                            .white.opacity(0.1),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                // Fade the rim slightly as it recedes
                .opacity(configuration.isPressed ? 0.5 : 1.0)
            
            // B. THE FIXED CORNER GLINT
            // By using an overlay with .topLeading alignment, (0,0) is now the corner.
            .overlay(alignment: .topLeading) {
                cornerGlint(configuration: configuration)
            }
            
            // C. The "Fresnel" Refraction (Inner Glow)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                // 🔑 Lower opacity in Light Mode (0.08) vs Dark Mode (0.15)
                .stroke(.white.opacity(colorScheme == .dark ? 0.15 : 0.08), lineWidth: 4)
                .mask(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(lineWidth: 10)
                        .blur(radius: 8)
                )
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
        .blendMode(.plusLighter) // Makes the white pop without washing out the blue
        .mask(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
