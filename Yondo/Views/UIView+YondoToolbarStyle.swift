//
//  ToolbarButtonType.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.02.2026.
//

import SwiftUI

enum ToolbarButtonType {
    case dismiss    // The 16.5pt Bold xmark
    case standard   // Trash, Share, etc.
    case standardBold
    case standardSmall
    case label      // "Create New Yondo" text
    case prominent
    
    var opacity: CGFloat {
        switch self {
        case .label: return 0.85
        default: return 1.0
        }
    }
    
    var fontWeight: Font.Weight {
        switch self {
        case .dismiss, .standardBold, .label, .prominent: return .bold
        case .standard, .standardSmall: return .semibold
        }
    }
    
    var fontSize: CGFloat {
        switch self {
        case .dismiss:        return 16.5
        case .standard:       return 17
        case .standardBold:   return 16
        case .standardSmall:  return 16.5
        case .label:          return 15
        case .prominent:      return 30.0
        }
    }
}

extension View {
    func yondoToolbarStyle(
        _ type: ToolbarButtonType = .standard,
        weight: Font.Weight? = nil
    ) -> some View {
        self.font(.system(
                size: type.fontSize,
                weight: weight ?? type.fontWeight,
                design: .rounded)
            )
            .if(type.opacity < 1.0) { view in
                view.foregroundStyle(.primary.opacity(type.opacity))
            }
    }
}

// Simple helper to allow conditional modifiers
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
