//
//  YondoDivider.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.01.2026.
//

import SwiftUI

struct YondoDivider: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. THE HAIRLINE: This is the sharp specular edge
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.5 : 0.2),
                            .white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: colorScheme == .dark ? 0.33 : 0.5)
            
            // 2. THE GLOW: Your original refraction gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            // The "Catch" - This highlight defines the edge
                            .init(color: lightCatchColor, location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1.0)
                //.frame(height: 1.5) // A bit thicker so the gradient has room to "glow"
                // Using .screen in dark mode makes the specular edge "glow" over content
                .blendMode(colorScheme == .light ? .multiply : .screen)
        }
    }
    
    private var lightCatchColor: Color {
        if colorScheme == .light {
            // In Light Mode, we want a subtle "shadow" seam to define the start of the glass
            return Color.yondoDeep.opacity(0.15)
        } else {
            // In Dark Mode, a subtle "light" seam catches the reflection
            return Color.white.opacity(0.25)
        }
    }
}
