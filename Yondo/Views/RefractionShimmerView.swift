//
//  RefractionShimmerView.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

struct RefractionShimmerView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    
    // MARK: - Refined Gradient Colors
    private var shimmerColors: [Color] {
        let isDark = colorScheme == .dark
        let highlight = isDark ? Color.white.opacity(0.4) : Color.white.opacity(0.8)
        let edge = isDark ? Color.white.opacity(0.1) : Color.yondoAccent.opacity(0.05)
        
        return [.clear, edge, highlight, edge, .clear]
    }
    
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: shimmerColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * 0.7) // Limit width to keep the glint sharp
                .rotationEffect(.degrees(30))
                .opacity(isAnimating ? 0.3 : 0.8)
                // Scale Y massively to cover rotation, but keep X smaller for sharpness
                .scaleEffect(x: 1.0, y: 3.5)
                .offset(x: isAnimating ? geo.size.width * 1.5 : -geo.size.width * 1.5)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }
        }
    }
}
