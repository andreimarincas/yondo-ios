//
//  SelectionEmphasisModifier.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.01.2026.
//

import SwiftUI

struct SelectionEmphasisModifier: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .saturation(isSelected ? 1.0 : 0.85)
//            .contrast(isSelected ? 1.1 : 0.85)
//            .brightness(isSelected ? 0 : -0.12)
            .opacity(isSelected ? 1.0 : 0.7)
        //                    .blur(radius: isSelected ? 0 : 0.15)    // Optional: tiny blur for depth
    }
}

// Convenience extension to make it easier to call
extension View {
    func selectionEmphasis(isSelected: Bool) -> some View {
        self.modifier(SelectionEmphasisModifier(isSelected: isSelected))
    }
}
