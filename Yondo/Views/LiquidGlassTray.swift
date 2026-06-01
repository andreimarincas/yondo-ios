//
//  LiquidGlassTray.swift
//  Yondo
//
//  Created by Andrei Marincas on 05.04.2026.
//

import SwiftUI

enum LiquidGlassTrayLayoutConstants {
    static let trayHeight: CGFloat = 91
    static let trayPadding: CGFloat = 20
    static let trayCornerRadius: CGFloat = 32
}

struct LiquidGlassTray<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    
    let isEnabled: Bool
    let isPressed: Bool
    let cornerRadius: CGFloat
    let content: Content
    
    init(
        isEnabled: Bool,
        isPressed: Bool,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.isPressed = isPressed
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(10)
                .frame(maxWidth: .infinity)
        }
        .frame(height: LiquidGlassTrayLayoutConstants.trayHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background {
            ZStack {
                Color.clear
                    .glassEffect(
                        .regular.tint(
                            isEnabled ?
                                (colorScheme == .light
                                    ? Color.yondoBrand.opacity(0.05) // Subtle brand wash
                                    : Color.yondoDeep.opacity(0.08))  // Stronger depth wash
                                : .clear
                        ),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .compositingGroup()
        }
        .brightness(
            isEnabled ?
                (colorScheme == .dark ?
                    (isPressed ? 0.15 : 0.0) : // Brighter pop in Dark
                    (isPressed ? -0.04 : 0.0))  // Slight dimming for "depth"
                : 0.0
        )
        .saturation(
            isEnabled ?
                // Adds a tiny bit of "color life" when pressed
                (colorScheme == .dark ?
                    (isPressed ? 2.0 : 1.2) :
                    (isPressed ? 1.2 : 1.0))   // Very subtle color boost, not 0.0
                : 1.0
        )
        .contrast(
            isEnabled ?
                (colorScheme == .dark ?
                    (isPressed ? 1.6 : 1.1) :
                    (isPressed ? 1.05 : 1.0))  // Keep it near 1.0 to avoid "mud"
                : 1.0
        )
        .scaleEffect(isPressed ? 0.97 : 1.0) // Added for tactile feedback
        .animation(.spring(response: 0.35, dampingFraction: 1.0), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}
