//
//  View+Extensions.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.03.2026.
//

import SwiftUI
import UIKit

// MARK: - UIKit Navigation Helpers
extension View {
    func findNavigationController() -> UINavigationController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        return findNavigationController(from: rootViewController)
    }

    private func findNavigationController(from vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController { return nav }
        if let tab = vc as? UITabBarController {
            if let selected = tab.selectedViewController {
                return findNavigationController(from: selected)
            }
        }
        for child in vc.children {
            if let nav = findNavigationController(from: child) { return nav }
        }
        return nil
    }
}

struct LiquidBlurModifier: ViewModifier, Animatable {
    var threshold: CGFloat
    var intensity: CGFloat // This is what we animate

    // This tells SwiftUI: "Watch this value and give me every number in between"
    var animatableData: CGFloat {
        get { intensity }
        set { intensity = newValue }
    }

    func body(content: Content) -> some View {
        content.visualEffect { content, proxy in
            let frame = proxy.frame(in: .global)
            let currentY = frame.maxY
            let actualThreshold = threshold + 40
            
            let distance = max(0, currentY - actualThreshold)
            let progress = min(distance / 100, 1.0)
            let easedProgress = pow(progress, 3)
            
            return content
                .blur(radius: (easedProgress * 6.0) * intensity)
                .scaleEffect(1.0 - ((easedProgress * 0.04) * intensity))
                .opacity(1.0 - ((easedProgress * 0.1) * intensity))
        }
    }
}

extension View {
    func liquidBlur(threshold: CGFloat, intensity: CGFloat) -> some View {
        self.modifier(LiquidBlurModifier(threshold: threshold, intensity: intensity))
    }
}
