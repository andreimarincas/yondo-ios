//
//  YondoPrimaryButtonStyle.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.01.2026.
//

import SwiftUI

private let buttonRadius: CGFloat = 22

struct YondoPrimaryButtonStyle: ButtonStyle {
    let captionMessage: String
    let isDisabled: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        // Combine states for logical checks
        let isDownOrDisabled = isPressed || isDisabled

        VStack(spacing: 2) {
            Text("Create Yondo")
//                .font(.headline.weight(.semibold))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundColor(.white)
            
            if !captionMessage.isEmpty {
                Text(captionMessage)
//                    .font(.caption)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundColor(
                        colorScheme == .light
                        ? .white.opacity(isDisabled ? 0.6 : 0.8) // Dim text when disabled
                        : isPressed ? Color.yondoGlow.opacity(0.6) : Color.white.opacity(0.8)
                    )
            }
        }
        // First shadow: The tight label shadow
        .shadow(color: !isDownOrDisabled ? Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15) : .clear,
                radius: !isDownOrDisabled ? 1 : 0, x: 0, y: 1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            buttonBackground(isPressed: isPressed)
        )
        .clipShape(RoundedRectangle(cornerRadius: buttonRadius, style: .continuous))
        .background {
            if isPressed {
                // This is the "Socket" edge that stays still while the button moves
                RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
                    .stroke(
                        colorScheme == .light
                        ? Color.white //.yondoDeep.opacity(0.15)
                        : Color.white.opacity(0.1),
                        lineWidth: colorScheme == .light ? 2.0 : 1.0
                    )
                    //.offset(y: 0.5) // Sit slightly below the button's origin
                    .offset(y: 1.0)
            }
        }
        .overlay(buttonOverlay(isPressed: configuration.isPressed))
        .scaleEffect(isDownOrDisabled ? 0.98 : 1.0)
        .offset(y: isDownOrDisabled ? 1.5 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDownOrDisabled)
    }
    
    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        if colorScheme == .light {
            ZStack {
                if isDisabled {
                    // LIGHT DISABLED: Muted, deeper tones so it's not washed out
                    LinearGradient(
                        colors: [Color.yondoDeep.opacity(0.4), Color.yondoDeep.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        colors: isPressed ? [Color.yondoBrand, Color.yondoMidnight] : [Color.yondoAccent, Color.yondoBrand],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                
                // Hide gloss highlight when disabled for a "matte" inactive feel
                if !isDisabled {
                    RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isPressed ? 0.05 : 0.15), Color.clear],
//                                colors: [Color.white.opacity(isPressed ? 0.1 : 0.2), Color.white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.overlay) // Overlay often looks "glassier" than Screen
                        //.blendMode(.screen)
                }
            }
        } else {
            // DARK MODE: Uses midnight blue instead of black
            LinearGradient(
                colors: isDisabled ? [Color.yondoBrand.opacity(0.5), Color.yondoMidnight.opacity(0.7)] :
                        (isPressed ? [Color.yondoDeep, Color.yondoMidnight] : [Color.yondoBrand, Color.yondoDeep]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    @ViewBuilder
    private func buttonOverlay(isPressed: Bool) -> some View {
        ZStack {
            // 1. The Main Gradient Rim
            RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: overlayGradientColors(isPressed: isPressed),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isPressed ? 1.0 : 1.2
                )
            
            // 2. The Sunken "Inner Shadow" (The button's internal depth)
            if isPressed {
                RoundedRectangle(cornerRadius: buttonRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.black.opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 3
                    )
                    .blur(radius: 2)
                    .mask(RoundedRectangle(cornerRadius: buttonRadius, style: .continuous))
            }
        }
    }

    private func overlayGradientColors(isPressed: Bool) -> [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(isDisabled ? 0.1 : (isPressed ? 0.15 : 0.45)),
                .clear
            ]
        } else {
            if isDisabled {
                return [Color.black.opacity(0.1), Color.black.opacity(0.05)]
            } else {
                return [
                    Color.white.opacity(isPressed ? 0.0 : 0.3), // Light catch on top
                    Color.yondoDeep.opacity(isPressed ? 0.2 : 0.1) // Depth on bottom
                ]
            }
        }
    }
}
