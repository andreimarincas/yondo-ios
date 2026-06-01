//
//  SecondaryActionButton.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.03.2026.
//

import SwiftUI

struct SecondaryActionButton: View {
    let title: String
    let isEnabled: Bool
    
    // Configurable
    var accentColor: Color = .yondoBrand
    var secondaryColor: Color = .yondoInteractive
    var isMonospaced: Bool = false
    var minWidth: CGFloat? = nil
    
    let action: () -> Void
    
    /// Set this to true when the button is placed on an ultraThinMaterial or similar vibrant background
    var isOnMaterial: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            action()
        }) {
            Text(title)
                .font({
                    let font = Font.system(.headline, design: .rounded).weight(.semibold)
                    return isMonospaced ? font.monospacedDigit() : font
                }())
                // Add the subtle text shadow here for readability, matching PrimaryButtonStyle
                .shadow(
                    color: isEnabled ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.15) : .clear,
                    radius: isEnabled ? 1 : 0,
                    x: 0,
                    y: 1
                )
                .padding(.horizontal, 24)
                .frame(minWidth: minWidth)
                .frame(height: 46)
                .background(buttonBackground)
                .contentShape(Rectangle()) // Ensures the whole area is tappable
                .padding(.vertical, 8)     // Adds 8pt of invisible padding top/bottom
        }
        .buttonStyle(SecondaryButtonStyle())
        .foregroundStyle(textColor)
        .disabled(!isEnabled)
        // Keep the original animation logic for state swaps
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var buttonBackground: some View {
        ZStack {
            // Base fill with depth gradient
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [backgroundColor, secondaryBackgroundColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            if isEnabled {
                // The "Glass Edge" highlight
                Capsule()
                    .strokeBorder(highlightGradient, lineWidth: 1.0)
                    .blendMode(colorScheme == .dark ? .screen : .normal)
            }
        }
        // Subtle drop shadow for the button container
        .shadow(
            color: isEnabled
            ? (colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.1))
                : .clear,
            radius: colorScheme == .dark ? 2.0 : 1.5,
            x: 0,
            y: colorScheme == .dark ? 2 : 1.5
        )
    }
    
    // MARK: - Computed Properties
    
    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.3 : 0),
                Color.yondoDeep.opacity(colorScheme == .dark ? 0.0 : 0.3)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var backgroundColor: Color {
        if isEnabled { return accentColor }
        
        if isOnMaterial {
            // Anti-black hole: High contrast for Material/Blur backgrounds
            return colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
        } else {
            // Standard System-like disabled look (matches .borderedProminent)
            return colorScheme == .dark
                ? Color(white: 0.25)
                : Color(white: 0.9)
        }
    }
    
    private var secondaryBackgroundColor: Color {
        return isEnabled ? secondaryColor : backgroundColor
    }
    
    private var textColor: Color {
        if isEnabled {
            return .white
        }
        if isOnMaterial {
            // Legible high-contrast disabled text
            return colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4)
        } else {
            // Standard system-like washed out text
            return colorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.5)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0) // Dims slightly when pressed
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
