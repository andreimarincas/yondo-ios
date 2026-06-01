//
//  View+LiquidDesign.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.01.2026.
//

import SwiftUI

extension View {
    func liquidInnerShadow(radius: CGFloat = 10, opacity: Double = 0.3) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 12) // Matches your image corner radius
                .stroke(Color.black.opacity(opacity), lineWidth: 4)
                .blur(radius: radius)
                .mask(self) // Keeps the shadow inside the image
        )
    }
}
