//
//  LiquidGlassSecondaryButton.swift
//  Yondo
//
//  Created by Andrei Marincas on 28.03.2026.
//

import SwiftUI
import Combine

struct LiquidGlassSecondaryButton: View {
    let title: String
    let isEnabled: Bool
    
    var isProcessing: Bool = false
    
    // Configurable - Now defaulting to your vibrant palette
    var accentColor: Color = .yondoBrand
    var secondaryColor: Color = .yondoAccent
    var isMonospaced: Bool = false
    var minWidth: CGFloat? = nil
    
    let action: () -> Void
    
    /// Set this to true when the button is placed on an ultraThinMaterial or similar vibrant background
    var isOnMaterial: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            action()
        }) {
            Group {
                if isProcessing {
                    AnimatedProcessingLabel(baseText: title)
                } else {
                    Text(title)
                }
            }
            .font({
                let font = Font.system(.subheadline, design: .rounded).weight(.semibold)
                return isMonospaced ? font.monospacedDigit() : font
            }())
            .frame(minWidth: minWidth)
            .padding(.vertical, 6)
//            .padding(.horizontal, 20)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .tint(.primary)
        .disabled(!isEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEnabled)
    }
}

struct AnimatedProcessingLabel: View {
    var baseText: String = "Processing"
    
    @State private var step = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 0) {
            Text(baseText)
            
            // The dots take up physical space even when transparent (opacity 0)
            HStack(spacing: 0) {
                Text(".").opacity(step >= 1 ? 1 : 0)
                Text(".").opacity(step >= 2 ? 1 : 0)
                Text(".").opacity(step >= 3 ? 1 : 0)
            }
            // Optional: You can add a slight animation to the opacity
            .animation(.easeInOut(duration: 0.2), value: step)
        }
        .onReceive(timer) { _ in
            step = (step + 1) % 4 // Cycles: 0, 1, 2, 3
        }
        .onAppear {
            step = 0
        }
    }
}
