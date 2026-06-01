//
//  PulseIcon.swift
//  Yondo
//
//  Created by Andrei Marincas on 13.03.2026.
//

import SwiftUI
import UIKit

struct PulseIcon: UIViewRepresentable {
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: UIImage(named: "LaunchIcon"))
        imageView.contentMode = .scaleAspectFit
        
        // 1. Opacity Animation (The Fade)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.7
        
        // 2. Scale Animation (The Breath)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.98
        
        // 3. Group them together
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 0.75
        group.fillMode = .removed
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.autoreverses = true
        group.repeatCount = 1
        group.isRemovedOnCompletion = false
        group.beginTime = CACurrentMediaTime()
        
        imageView.layer.add(group, forKey: "breathing_pulse")
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Leave empty. We don't want SwiftUI touching this.
    }
}
