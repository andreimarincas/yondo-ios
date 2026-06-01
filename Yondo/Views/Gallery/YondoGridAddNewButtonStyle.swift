//
//  YondoGridButtonStyle.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.01.2026.
//

import SwiftUI

struct YondoGridAddNewButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            .opacity(configuration.isPressed ? colorScheme == .light ? 0.6 : 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0) // Subtle "click" feel
            .animation(.interpolatingSpring(stiffness: 250, damping: 10), value: configuration.isPressed)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
