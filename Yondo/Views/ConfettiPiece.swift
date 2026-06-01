//
//  ConfettiPiece.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.01.2026.
//

import SwiftUI

struct ConfettiPiece: View {
    let color: Color
    @State private var position: CGPoint = .zero
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = Double.random(in: 0.7...1.3)
    @State private var rotation: Double = 0

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 4)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(x: position.x, y: position.y)
            .onAppear {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 20...50)
                let randomRotation = Double.random(in: 90...360)
                
                // NEW: Randomize how heavy this specific piece is
                let gravityDrop = CGFloat.random(in: 30...70)
                
                // 1. THE INITIAL BURST
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                    position.x = cos(angle) * distance
                    position.y = sin(angle) * distance
                    rotation = randomRotation
                }
                
                // 2. THE GRAVITY FALL (Where you use gravityDrop)
                // We target position.y specifically to pull it down over time
                withAnimation(.easeIn(duration: 1.5).delay(0.1)) {
                    position.y += gravityDrop // This creates the "falling" effect
                    opacity = 0
                    scale = 0.3
                }
            }
    }
}

struct ParticleBurstView: View {
    let colors: [Color] = [.green, .yellow, .blue, .white, .pink, .purple]
    
    var body: some View {
        ZStack {
            ForEach(0..<18) { i in
                ConfettiPiece(color: colors.randomElement() ?? .green)
            }
        }
        // Apply it here!
//        .drawingGroup()
        // This ensures the particles don't block button taps
        .allowsHitTesting(false)
    }
}

struct CelebrationModifier: ViewModifier {
    let trigger: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            // The underlying button or view
            content
            
            // The celebration layer
            if trigger {
                ParticleBurstView()
                    .allowsHitTesting(false) // Don't block taps
            }
        }
        .onChange(of: trigger) { _, newValue in
            if newValue {
                // Trigger the physical feedback
//                let generator = UIImpactFeedbackGenerator(style: .medium)
//                generator.impactOccurred()
            }
        }
    }
}

// 2. Wrap it in an extension for easy use
extension View {
    func celebration(trigger: Bool) -> some View {
        self.modifier(CelebrationModifier(trigger: trigger))
    }
}
