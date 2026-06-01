//
//  CreateNewGridItem.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.01.2026.
//

import SwiftUI

struct CreateNewGridItem: View {
    @Environment(\.colorScheme) var colorScheme
    let columnCount: Int
    
    @State private var isVisible = false
    
    // Dynamic size based on density
    private var iconSize: CGFloat {
        columnCount <= 2 ? 28 : 22
    }
    
    var body: some View {
        ZStack {
            // 1. The "Indentation"
            // Instead of a border, we use a subtle inner glow/shadow effect
            GridPlaceholder()
                .opacity(colorScheme == .light ? 0.2 : 0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            Color.primary.opacity(0.05),
                            lineWidth: 1
                        )
                )
            
            if isVisible {
                plusButtonStack
                    .scaleEffect(isVisible ? 1 : 0.8)
                    .offset(y: -1)
                    .transition(.opacity)
                    // 2. The Refraction (The "Liquid" part)
                    // This makes the icon feel like it's underwater or inside the glass
//                    .blur(radius: isVisible ? 0 : 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .aspectRatio(1, contentMode: .fill)
        .contentShape(Rectangle())
        .onAppear(perform: animateIn)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var plusButtonStack: some View {
        ZStack {
            baseIconLayer
//            bloomLayer
            specularHighlightLayer
        }
    }
    
    @ViewBuilder
    private var baseIconLayer: some View {
        let circleOpacity = 1.0 //colorScheme == .dark ? 0.4 : 0.45
        let plusOpacity = 1.0 //colorScheme == .dark ? 0.8 : 0.9
        
        Image(systemName: "plus.circle.fill")
            .font(.system(size: iconSize, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                // 1. THE PLUS: In Light Mode, we give it a tiny shadow to pop from the gradient
                (colorScheme == .light ? Color.white : Color.black),
                    .opacity(plusOpacity),
                
                // 2. THE CIRCLE: Sharpened gradient
                LinearGradient(
                    colors: [
                        .yondoAccent.opacity(circleOpacity),
                        .yondoBrand.opacity(circleOpacity + 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // This shadow only affects the "Plus" and the "Circle" edges,
            // preventing the "mushy" look in Light Mode.
            // 2. TIGHTER SHADOW: Use a darker shadow in Light Mode to simulate the "edge" of the glass
//            .shadow(color: .black.opacity(colorScheme == .light ? 0.2 : 0), radius: 0.5, x: 0, y: 0.5)
    }
    
//    @ViewBuilder
//    private var bloomLayer: some View {
//        Image(systemName: "plus.circle.fill")
//            .font(.system(size: iconSize, weight: .semibold))
//            .foregroundStyle(Color.yondoAccent)
//            .opacity(colorScheme == .dark ? 0.2 : 0.15)
//            .blur(radius: colorScheme == .dark ? 2.5 : 1.2)
//            .blendMode(.plusLighter) // Makes the "glow" feel more like light
//    }
    
    @ViewBuilder
    private var specularHighlightLayer: some View {
        Image(systemName: "plus.circle.fill") // The "Light Hit"
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.6 : 0.9),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.6, y: 0.4) // "Trap" the light in the top corner
                )
            )
            // 3. BLEND MODE SWAP: 'Screen' kills Light Mode. 'Overlay' preserves detail.
            .blendMode(colorScheme == .dark ? .screen : .overlay)
            .opacity(colorScheme == .dark ? 0.8 : 1.0) // Keeps the "shine" strong while the colors are ghosted
    }
    
    // MARK: - Actions
    
    private func animateIn() {
        // Match thumbnail fade-in timing
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = true
        }
    }
}
