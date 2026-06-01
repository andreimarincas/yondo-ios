//
//  Color+Extensions.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.12.2025.
//

import SwiftUI

extension Color {
//    static let sceneAccent = Color.blue.opacity(0.24)
//    static let sceneAccent = Color("sceneAccent")
}

import SwiftUI

extension Color {
    static let yondoDeep = Color(hex: "#08428C")        // Deep Navy
    static let yondoBrand = Color(hex: "#0798F2")       // Solid Blue
    static let yondoAccent = Color(hex: "#16DCF2")      // Electric Cyan
    static let yondoGlow = Color(hex: "#2EF2F2")        // Ultra Light Cyan
//    static let yondoGlowDim = Color(hex: "#24CACA")     // slightly dimmer cyan
    static let yondoOrange = Color(hex: "#E67E22")      // Burnt Orange
    static let yondoOrangeDeep = Color(hex: "#D35400")  // Richer, "Inky" orange for Light Mode
//    static let yondoViolet = Color(hex: "#8E44AD")      // Wisteria/Amethyst — A deep, saturated purple
    static let yondoMidnight = Color(hex: "#031D3D")    // A rich, deep navy that replaces black
//    static let yondoBrandLight = Color(hex: "#59BFFF")  // A clean, airy sky blue
    static let yondoWhite = Color(hex: "#F2F9FF")       // A very faint blue-white for highlights
    static let yondoInteractive = Color(hex: "#00A3FF") // Vibrant Action Blue
    
    // A vibrant, neon-leaning green that glows against YondoMidnight
    static let yondoSuccess = Color(hex: "#2BFD9E")
}

// Helper to use HEX codes directly
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

extension UIColor {
    static let dynamicSegmentUnselected = UIColor { traits in
        return traits.userInterfaceStyle == .dark
            ? UIColor(.yondoWhite.opacity(0.5))    // Dark Mode color
            : UIColor(.yondoMidnight.opacity(0.7)) // Light Mode color
    }
}

extension Color {
    // For labels on the main view background
    static func yondoSecondaryText(for scheme: ColorScheme) -> Color {
        scheme == .light ? .yondoMidnight.opacity(0.6) : .yondoWhite.opacity(0.4)
    }
    
    // For labels inside a Gray/Tinted Container (like the Picker)
    static func yondoContainerSecondaryText(for scheme: ColorScheme) -> Color {
        scheme == .light ? .yondoMidnight.opacity(0.8) : .yondoWhite.opacity(0.6)
    }
}
