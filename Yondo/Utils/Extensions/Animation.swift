//
//  Animation.swift
//  Yondo
//
//  Created by Andrei Marincas on 04.02.2026.
//

import SwiftUI

extension Animation {
    /// The "Jolly" spring. Used for sheets and big modal expansions.
    /// Feels like a soft bubble stretching.
    static var liquid: Animation {
        .spring(response: 0.55, dampingFraction: 0.72)
    }
    
    /// Snappy and energetic. Perfect for button presses and small toggles.
    static var pop: Animation {
        .spring(response: 0.3, dampingFraction: 0.6)
    }
    
    /// Subtle and professional. Use for fading text or minor transitions.
    static var gentle: Animation {
        .spring(response: 0.45, dampingFraction: 1.0)
    }
}

extension Animation {
    /// For quick, mechanical reactions (buttons, haptics, toggles)
    static let yondoSnappy = Animation.spring(response: 0.25, dampingFraction: 0.7)
    
    /// For layout transitions and image fades (screen swaps, large overlays)
    static let yondoSmooth = Animation.spring(response: 0.35, dampingFraction: 0.9)
}
