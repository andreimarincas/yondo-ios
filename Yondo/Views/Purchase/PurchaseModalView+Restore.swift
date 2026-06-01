//
//  PurchaseModalView+Restore.swift
//  Yondo
//
//  Created by Andrei Marincas on 07.04.2026.
//

import SwiftUI

extension PurchaseModalView {
    var restorePurchasesSection: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 8)
            
            GlassEffectContainer(spacing: 0) {
                if isRestoring {
                    Button(action: {}) {
                        YondoSpinner(size: .small, style: colorScheme == .dark ? .subtle : .system)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 6)
                    }
                    .allowsHitTesting(false)
                    .buttonStyle(.glass)
                    .glassEffectID("spinner", in: glassTransitionSpace)
                    
                } else if showSuccess {
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Success!")
                        }
                        .yondoToolbarStyle(.standardSmall)
                        .padding(4)
                    }
                    .allowsHitTesting(false)
                    .tint(.green)
                    .buttonStyle(.glass)
                    .glassEffectID("successBtn", in: glassTransitionSpace)
                } else {
                    Button(action: {
                        Log.debug("🎭 PMV: 🔄 Tapped restore footer button.")
                        HapticManager.shared.lightImpact()
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            restore()
                        }
                    }) {
                        Text("Restore")
                            .yondoToolbarStyle(.standardSmall)
                            .padding(4)
                    }
                    .tint(.primary.opacity(0.85))
                    .buttonStyle(.glass)
                    .glassEffectID("restoreBtn", in: glassTransitionSpace)
                }
            }
            
            Spacer()
                .frame(height: 8)
            
            Text(captionMessage)
                .id(captionMessage)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(colorScheme == .dark ? Color(white: 0.5) : Color.secondary)
                .fontDesign(.rounded)
                .frame(minHeight: 22, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .contentTransition(.opacity)
                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: captionMessage)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom)
        .allowsHitTesting(!isInteractionDisabled && !showSuccess)
        // Swallows swipes on the footer area so the ScrollView behind
        // it cannot steal the touch and cancel the button's pressed state.
        .gesture(DragGesture())
    }
}
