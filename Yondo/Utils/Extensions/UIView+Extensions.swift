//
//  UIView+Extensions.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit

extension UIView {
    /// Applies the high-quality rendering stack needed for Hero transitions and zooming.
    func applyHeroRenderingQuality() {
        self.layer.masksToBounds = true
        self.layer.allowsEdgeAntialiasing = true
        self.layer.minificationFilter = .trilinear
        self.layer.contentsScale = UIScreen.main.scale
    }
}
