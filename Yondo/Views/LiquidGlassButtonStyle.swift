//
//  LiquidGlassButtonStyle.swift
//  Yondo
//
//  Created by Andrei Marincas on 05.04.2026.
//

import SwiftUI

struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    let captionMessage: String
    let isBusy: Bool
    let colorScheme: ColorScheme
    
    private let cornerRadius: CGFloat = 24
    
    @Binding var isDown: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isDown = newValue
            }
        
        let isActive = configuration.isPressed || isBusy
        
        VStack(spacing: 4) {
            Text("Create Yondo")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
            
            // Ensure the button doesn't resize when the caption appears
            Text(captionMessage.isEmpty ? " " : captionMessage)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(isEnabled ? (isActive ? .primary : .secondary) : .tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            buttonBackground(isPressed: isActive)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // A "heavy" feel that mimics physical materials
        .animation(.spring(response: 0.35, dampingFraction: 1.0), value: isDown)
    }
    
    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        if isPressed {
            ZStack {
                // The base brightness shift
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
                
                // The color tint on top
                colorScheme == .light
                    ? Color.yondoBrand.opacity(0.05) // Subtle brand wash
                    : Color.yondoDeep.opacity(0.08)  // Stronger depth wash
                
                // The subtle edge definition (Optional, but adds that "sharp" look)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
        }
    }
}
