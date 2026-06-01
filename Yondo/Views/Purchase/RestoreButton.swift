//
//  RestoreButton.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.03.2026.
//

import SwiftUI

struct RestoreButton: View {
    let isRestoring: Bool
    let showSuccess: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if showsSpinner {
                    Group {
                        YondoSpinner(size: .small, style: colorScheme == .dark ? .subtle : .system)
                    }
                    .frame(width: 36, height: 36)
                    
                } else if showSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Success!")
                            .shadow(
                                color: isEnabled ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.15) : .clear,
                                radius: isEnabled ? 1 : 0,
                                x: 0,
                                y: 1
                            )
                    }
                    .padding(.horizontal, 16)
                } else {
                    Text("Restore")
                        .shadow(
                            color: isEnabled ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.15) : .clear,
                            radius: isEnabled ? 1 : 0,
                            x: 0,
                            y: 1
                        )
                        .padding(.horizontal, 24)
                }
            }
            .font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .frame(alignment: .center)
            .frame(height: 36)
            .background(buttonBackground)
        }
        .buttonStyle(SecondaryButtonStyle())
        .foregroundStyle(textColor)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 44)
        .frame(minWidth: 44)
        .disabled(!isEnabled)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isRestoring)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSuccess)
        .animation(.easeInOut(duration: 0.2), value: !isEnabled)
    }
    
    private var showsSpinner: Bool {
        isRestoring && !showSuccess
    }
    
    private var backgroundColor: Color {
        // Single source of truth for color
        if showSuccess {
            Color.green
        } else if isRestoring || !isEnabled {
            // Anti-black hole: Use white with low opacity in Dark Mode
            colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
        } else {
            Color.yondoBrand
        }
    }
    
    private var secondaryBackgroundColor: Color {
        if showSuccess {
            Color.green
        } else if isRestoring || !isEnabled {
            // Anti-black hole: Use white with low opacity in Dark Mode
            colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
        } else {
            isEnabled ? Color.yondoInteractive : Color.yondoBrand
        }
    }
    
    private var textColor: Color {
        if showSuccess || isEnabled {
            return .white // Bright and readable when active or successful
        }
        
        // Legible disabled text that doesn't "wash out"
        return colorScheme == .dark
            ? Color.white.opacity(0.5)  // Soft white for dark mode
            : Color.black.opacity(0.4)  // Soft black/dark gray for light mode
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
            
            if isEnabled && !showsSpinner {
                // The "Glass Edge" highlight
                Capsule()
                    .strokeBorder(highlightGradient, lineWidth: 1.0)
                    .blendMode(colorScheme == .dark ? .screen : .normal)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var highlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.3 : 0.5),
                .white.opacity(0.2),
                Color.yondoDeep.opacity(0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
