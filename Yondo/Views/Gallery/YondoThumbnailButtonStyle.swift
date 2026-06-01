//
//  YondoThumbnailButtonStyle.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.01.2026.
//

import SwiftUI

struct YondoThumbnailButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPressedBinding: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            // 💧 LIQUID INTERACTION
            // Instead of a dimming overlay, we use a subtle 'sheen' on press
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(configuration.isPressed ? (colorScheme == .dark ? 0.08 : 0.15) : 0))
                    .blendMode(.screen)
            }
            // 💧 SURFACE TENSION
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interpolatingSpring(stiffness: 250, damping: 10), value: configuration.isPressed)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressedBinding = newValue // Synchronize the lock
            }
    }
}
