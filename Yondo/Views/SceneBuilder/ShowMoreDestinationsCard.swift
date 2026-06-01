//
//  ShowMoreDestinationsCard.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import SwiftUI

private let cardRadius: CGFloat = 22

struct ShowMoreDestinationsCard: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.shared.mediumImpact(intensity: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                action()
            }
        }) {
            ZStack {
                // The "Glass Architectural" Rim
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(colorScheme == .dark ? 0.2 : 0.5), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                VStack(spacing: 8) {
                    PlusIconGlassView(isPressed: isPressed)
                    
                    VStack(spacing: 2) {
                        Text("More")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        
                        Text("Destinations")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    // Text dims and slightly shrinks to "recede"
                    .opacity(isPressed ? 0.7 : 1.0)
                    .scaleEffect(isPressed ? 0.98 : 1.0)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
        }
        .buttonStyle(ShowMoreDestinationsButtonStyle(externalIsPressed: $isPressed, onTrigger: action))
        .animation(.spring(duration: 0.25, bounce: 0.3), value: isPressed)
    }
}

// MARK: - Reusable Subviews
struct PlusIconGlassView: View {
    let isPressed: Bool // 👈 New parameter
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [.yondoInteractive, .yondoBrand],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .rotationEffect(.degrees(isPressed ? 45 : 0)) // 💧 Liquid twist
            .scaleEffect(isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isPressed)
            .padding(12)
            .background {
                ZStack {
                    // 1. The Base
                    Circle()
                        .fill(colorScheme == .light ? Color.white.opacity(0.9) : Color.white.opacity(0.1))
                        // ADD THIS: Increases contrast against the card background when pressed
                        .overlay {
                            if colorScheme == .light {
                                Circle()
                                    .stroke(Color.black.opacity(isPressed ? 0.05 : 0), lineWidth: 0.5)
                            }
                        }
                    
                    // 2. Animated Specular Highlight
                    // We layer the highlight and animate its total opacity
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(colorScheme == .light ? 0.8 : 0.5), .clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        // This is where the magic happens:
                        // 1.0 intensity when idle, 0.3 when pressed
                        .opacity(isPressed ? 0.3 : 1.0)
                    
                    // 3. The Rim
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
                // Animate the shadow and the highlight opacity together
                .animation(.spring(duration: 0.25, bounce: 0.3), value: isPressed)
                // Subtle shadow shift
                .shadow(color: .black.opacity(colorScheme == .light ? 0.04 : 0.08),
                        radius: isPressed ? 2 : 4,
                        y: isPressed ? 1 : 2)
            }
    }
}

// MARK: - Dedicated Button Style
struct ShowMoreDestinationsButtonStyle: ButtonStyle {
    @Binding var externalIsPressed: Bool
    let onTrigger: () -> Void
    
    @State private var isAnimatingPress = false
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || isAnimatingPress
        
        configuration.label
            .background {
                // 1. Dynamic Lighting Background
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: backgroundColors(isPressed: isPressed),
                            // THE PICKY TWEAK: Shifting light source to center on press
                            startPoint: isPressed ? .center : .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                // 2. Dynamic Inner Border
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? .white.opacity(isPressed ? 0.08 : 0.15)
                            : .black.opacity(isPressed ? 0.00 : 0),
                        lineWidth: isPressed ? 1.5 : 1
                    )
            }
            .scaleEffect(isPressed ? 0.94 : 1.0)
//            .brightness(isPressed ? -0.05 : 0)
//            .shadow(
//                color: colorScheme == .light ? .black.opacity(isPressed ? 0.05 : 0.1) : .clear,
//                radius: isPressed ? 2 : 6,
//                y: isPressed ? 1 : 3
//            )
            // Combined Animations
//            .animation(.interpolatingSpring(stiffness: 250, damping: 12), value: configuration.isPressed)
            .animation(
                isPressed
                    ? .spring(response: 0.15, dampingFraction: 0.85)
                    : .spring(response: 0.4, dampingFraction: 0.45),
                value: isPressed
            )
//            .animation(.spring(duration: 0.22, bounce: 0.3), value: isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    handlePress()
                } else {
                    handleRelease(configuration: configuration)
                }
            }
    }
    
    private func handlePress() {
        externalIsPressed = true
        isAnimatingPress = true
//        HapticManager.shared.softImpact(intensity: 0.8)
    }
    
    private func handleRelease(configuration: Configuration) {
        // 💧 THE PLAYFUL BOUNCE:
        // We let the spring finish its 'rebound' for 0.2s before firing.
        // This makes it feel like the action is a RESULT of the button snapping back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            // The asymmetric animation defined in makeBody will take over here.
//            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isAnimatingPress = false
                externalIsPressed = false
//            }
            
            // Fire haptic at the moment of peak "snap"
//            HapticManager.shared.mediumImpact(intensity: 0.6)
            
            // Finally, trigger the modal
            // 3. Trigger modal ONLY after the bounce has visually peaked
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
//                guard !configuration.isPressed else { return }
//                onTrigger()
//            }
        }
    }
    
//    private func handleInteraction(pressed: Bool) {
//        if pressed {
//            externalIsPressed = true
//            isAnimatingPress = true
//            HapticManager.shared.softImpactGenerator.prepare()
//            HapticManager.shared.softImpact(intensity: 0.75)
//        } else {
//            // MATCH: The 0.08s bridge that ensures a "full press" visual
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
//                withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
//                    isAnimatingPress = false
//                    externalIsPressed = false
//                }
//            }
//        }
//    }
    
    // MARK: - Helper Logic
    private func backgroundColors(isPressed: Bool) -> [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(isPressed ? 0.08 : 0.12), Color.white.opacity(0.04)]
        } else {
            return [Color.yondoDeep.opacity(isPressed ? 0.05 : 0.08), Color.yondoDeep.opacity(0.04)]
        }
    }
    
//    private func handleHapticsAndState(pressed: Bool) {
//        if pressed {
//            HapticManager.shared.softImpactGenerator.prepare()
//            HapticManager.shared.softImpact(intensity: 0.75)
//            isAnimatingPress = true
//        } else {
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
//                withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
//                    isAnimatingPress = false
//                }
//            }
//        }
//    }
}
