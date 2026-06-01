//
//  GlassSecondaryButton.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.01.2026.
//

import SwiftUI

struct GlassSecondaryButton: View {
    var title: String
    var action: () -> Void
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            if isEnabled {
                action()
            }
        }) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundColor(isEnabled ? .white : Color.white.opacity(0.6))
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .frame(minWidth: 100)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .light
                                    ? [Color.white.opacity(0.25), Color.white.opacity(0.1)]
                                    : [Color.black.opacity(0.3), Color.black.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .background(
                            Capsule()
                                .stroke(Color.yondoAccent.opacity(0.4), lineWidth: 1)
                        )
                        .glassEffect(.regular.interactive())
                        .shadow(color: isPressed ? .clear : Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                )
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
