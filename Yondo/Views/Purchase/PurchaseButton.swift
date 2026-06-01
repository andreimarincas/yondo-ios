//
//  PurchaseButton.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.03.2026.
//

import SwiftUI
//import StoreKit

struct PurchaseButton: View {
    let product: YondoProduct
    let isPurchasing: Bool
    let isSuccess: Bool
    let isEnabled: Bool
    let statusBadge: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            Log.debug("🔘 Button: Physical tap confirmed for product ID [\(product.id)]. Triggering Haptics and closure.")
            HapticManager.shared.lightImpact()
            action()
        }) {
            HStack {
                productInfoLabels
                
                Spacer()
                
                statusTrailingView
                    .frame(minWidth: 60, minHeight: 24, alignment: .trailing)
            }
            .padding()
            .compositingGroup()
            .contentShape(Capsule())
        }
        .buttonStyle(PurchaseButtonStyle(colorScheme: colorScheme, isEnabled: isEnabled, isSuccess: isSuccess))
        .compositingGroup()
        .overlay(alignment: .trailing) {
            // Place the confetti in an overlay so it doesn't affect the button's shadow
            if isSuccess {
                ParticleBurstView()
                    .allowsHitTesting(false)
                    .padding(.trailing, 26)
                    .onAppear {
                        Log.debug("🎉 Button: Particle Burst view appeared for success product [\(product.id)].")
                    }
            }
        }
        .disabled(isPurchasing || isSuccess)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isPurchasing)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: product.displayPrice)
        .onChange(of: isSuccess) { _, success in
            if success {
                Log.debug("🎉 Button: Visually shifting to Success/Checkmark state for [\(product.id)].")
            }
        }
        .onChange(of: isPurchasing) { _, purchasing in
            if purchasing {
                Log.debug("⏳ Button: Shifting to Purchasing/Spinner state for [\(product.id)].")
            }
        }
    }

    // MARK: - Subviews

    private var productInfoLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(product.displayName)
                    .fontWeight(.semibold)
                    .foregroundStyle(colorScheme == .light ? Color(white: 0.15) : Color(white: 0.92))
                    .fontDesign(.rounded)
                    .baselineOffset(1)
                
                if let badge = statusBadge {
                    Text(badge).font(.caption).fontDesign(.rounded)
                }
            }
            
            Text(boldYondo(product.displayDescription))
                .font(.subheadline)
                .lineSpacing(1)
                .foregroundStyle(descriptionColor)
                .fontDesign(.rounded)
        }
        .opacity(isEnabled ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var statusTrailingView: some View {
        ZStack(alignment: .trailing) {
            if isSuccess {
                successCheckmark
            } else if isPurchasing {
                YondoSpinner(size: .small, style: .brand)
                    .frame(width: 60, alignment: .trailing)
                    .padding(.trailing, 2)
                    .transition(.opacity)
            } else {
                priceText
            }
        }
    }

    private var successCheckmark: some View {
        Color.clear
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    // The checkmark gets its own "celebratory" transition
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.2).combined(with: .opacity),
                        removal: .opacity
                    ))
                    // This spring has a lower dampingFraction to allow a tiny "bounce"
                    .animation(.spring(response: 0.4, dampingFraction: 0.4), value: isSuccess)
            )
            .frame(width: 60, height: 24, alignment: .trailing)
    }

    private var priceText: some View {
        Text(product.displayPrice)
            .font(.body.monospacedDigit())
            .fontWeight(.bold)
            .foregroundStyle(priceColor)
            .fontDesign(.rounded)
            .baselineOffset(1) // Set to 0 to keep the center vertical
            .opacity(isEnabled ? 1.0 : 0.6)
            .id(product.displayPrice)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
    }

    // MARK: - Helpers

    private var descriptionColor: Color {
        if isPurchasing {
            return Color.secondary.opacity(0.5)
        }
        return colorScheme == .light ? Color(white: 0.35) : Color(white: 0.65)
    }

    private var priceColor: Color {
        colorScheme == .light ? .yondoBrand : .yondoAccent.opacity(0.9)
    }
}

struct PurchaseButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme
    let isEnabled: Bool
    let isSuccess: Bool
    
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundStack(configuration))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 1. Physical press down effect
//            .scaleEffect(configuration.isPressed ? 0.999 : 1.0)
            // 2. Success "Pop" effect
//            .scaleEffect(isSuccess ? 1.025 : 1.0)
            .offset(y: configuration.isPressed ? 1.0 : 0)
            // Ensure we animate the success scale with a bouncy spring
//            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isSuccess)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    Log.debug("🔘 ButtonStyle: Tap Down detected (Spring offset triggered).")
                }
            }
    }

    @ViewBuilder
    private func backgroundStack(_ configuration: Configuration) -> some View {
        shape
            // FILL WITH SOLID COLOR FIRST (Stops the flicker)
            .fill(baseFillColor)
            .shadow(
                color: shadowColor(isPressed: configuration.isPressed),
                radius: isSuccess ? 2.5 : (configuration.isPressed ? 0 : 1.5), // Lift it higher on success
                x: 0,
                y: isSuccess ? (colorScheme == .dark ? 2 : 2.5) : 2
            )
            // OVERLAY THE GRADIENT (Keeps the UI pretty)
            .overlay(
                shape.fill(LinearGradient(
                    colors: configuration.isPressed ? touchDownColors : normalColors,
                    startPoint: .top, endPoint: .bottom
                ))
            )
            .overlay(topLightEffect(isPressed: configuration.isPressed))
            .overlay(borderOverlay(isPressed: configuration.isPressed))
            // Add the "Etched" inner shadow when pressed
            .overlay(etchedInnerShadow(isPressed: configuration.isPressed))
    }

    // MARK: - Sub-elements

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private func topLightEffect(isPressed: Bool) -> some View {
        shape.fill(LinearGradient(
            colors: [
                .white.opacity(isPressed ? (colorScheme == .light ? 0.3 : 0.02) : (colorScheme == .light ? 1.0 : 0.06)),
                .white.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .center // Ends halfway down for a sharp "top light" effect
        ))
        .blendMode(.screen) // Softens the white so it doesn't look like a solid block
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func borderOverlay(isPressed: Bool) -> some View {
        let normalColors = [
            colorScheme == .light ? Color.black.opacity(0.1) : .white.opacity(0.2),
            colorScheme == .light ? Color.black.opacity(0.05) : .white.opacity(0.05)
        ]
        let pressedColors = [
            colorScheme == .light ? Color.black.opacity(0.05) : .white.opacity(0.1),
            colorScheme == .light ? Color.black.opacity(0.05) : .white.opacity(0.2)
        ]
        shape.strokeBorder(
            LinearGradient(
                colors: isPressed ? pressedColors : normalColors,
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: colorScheme == .light ? (isPressed ? 0.5 : 1.0) : 0.5
        )
    }
    
    /// The secret to the "etched" look: A soft, dark inner shadow that appears when pressed.
    @ViewBuilder
    private func etchedInnerShadow(isPressed: Bool) -> some View {
        if isPressed {
            shape
                // Use .stroke instead of .strokeBorder to prevent a soft outer edge
                .stroke(
                    LinearGradient(
                        colors: [
                            colorScheme == .light ? Color.black.opacity(0.22) : .black.opacity(0.75),
                            colorScheme == .light ? Color.black.opacity(0.22) : .black.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    // Make the line thicker because half of it will be clipped away
                    lineWidth: colorScheme == .light ? 4.0 : 6.0
                )
                .blur(radius: 3)
                .clipShape(shape) // Chops off the outside half, leaving a perfect inner shadow
        }
    }

    // MARK: - Logic Helpers

    private var baseFillColor: Color {
        colorScheme == .dark ? Color(white: 0.15) : .white
    }

    private func shadowColor(isPressed: Bool) -> Color {
//        if isSuccess {
//            return .yondoSuccess.opacity(colorScheme == .dark ? 0.1 : 0.15)
//        } // Soft "Success" glow
        
        if isPressed || (!isEnabled && !isSuccess) { return .clear }
        return colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.0)
    }

    private var normalColors: [Color] {
        colorScheme == .light
            ? [Color(white: 0.97), Color(white: 0.93)]
            : [Color(white: 0.18), Color(white: 0.14)]
    }
    
    private var touchDownColors: [Color] {
//        colorScheme == .light ? [Color(white: 0.90), Color(white: 0.85)] : [Color(white: 0.22), Color(white: 0.18)]
        colorScheme == .light
            ? [Color(white: 0.95), Color(white: 0.91)]
            // FIXED: Dark mode now properly darkens when pressed, instead of getting brighter
            : [Color(white: 0.15), Color(white: 0.11)]
    }
}
