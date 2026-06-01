//
//  ShimmeringText.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.03.2026.
//

import SwiftUI

struct ShimmeringText: View {
    let message: String
    let colorScheme: ColorScheme
    
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var hueAnim: Double = -20.0
    
    var body: some View {
        let opticalKerning: CGFloat = colorScheme == .dark ? 0.2 : 0.1
        
        ZStack {
            // 1. Static Base Layer
            Text(message)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .kerning(opticalKerning)
                .foregroundStyle(
                    colorScheme == .dark
                        ? Color.yondoWhite.opacity(0.2) // Fainter "ghost" text
                        : Color.yondoMidnight.opacity(0.25) // Lighter "pencil" sketch text
                )
            
            // 2. Shimmer Layer
            Text(message)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .kerning(opticalKerning)
                .foregroundStyle(
                    LinearGradient(
                        colors: colorScheme == .dark ? [
                            .yondoBrand, .yondoGlow, .yondoAccent, .yondoBrand
                        ] : [
                            // Light Mode: Use the darker, readable brand colors to match the spinner
                            .yondoMidnight, .yondoDeep, .yondoBrand, .yondoMidnight
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // 🛑 Conditionally apply these! They destroy Light Mode text readability.
                .saturation(colorScheme == .dark ? 1.8 : 1.0) // Boosts the intensity of the brand colors
                .contrast(colorScheme == .dark ? 1.2 : 1.0)   // Sharpens the difference between the colors and the white glint
                .hueRotation(.degrees(colorScheme == .dark ? hueAnim : 0.0)) // This shifts the colors
                .mask(
                    GeometryReader { geo in
                        LinearGradient(
                            stops: colorScheme == .dark ? [
                                // Dark Mode: "The Polished Glint"
                                // Concentrated beam for higher perceived luminosity
                                .init(color: .clear, location: 0.25),
                                .init(color: .white, location: 0.5),
                                .init(color: .clear, location: 0.75)
                            ] : [
                                // Light Mode: "The Atmospheric Wash"
                                // Broad diffusion to prevent jitter on white
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 3)
                        .offset(x: -geo.size.width + (geo.size.width * 2 * shimmerOffset))
                    }
                )
        }
        .onAppear {
            let shimmerDuration: Double = colorScheme == .dark ? 3.0 : 4.0 // Slower in Light Mode
//            let shimmerDelay: Double = colorScheme == .dark ? 0.0 : 0.5   // Add a tiny pause for Light Mode
            
            withAnimation(
                .easeInOut(duration: shimmerDuration)
                .repeatForever(autoreverses: false)
//                .delay(shimmerDelay)
            ) {
                shimmerOffset = 1.0
                // Only rotate hue in Dark Mode to keep Light Mode clean
                if colorScheme == .dark {
                    hueAnim = 20.0
                }
            }
        }
    }
}
