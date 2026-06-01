//
//  WormSpinner.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.03.2026.
//

import SwiftUI
import UIKit

struct WormSpinner: UIViewRepresentable {
    enum SpinnerSize {
        case small, regular, large, extraLarge
        
        var value: CGFloat {
            switch self {
            case .small: return 16
            case .regular: return 20
            case .large: return 28
            case .extraLarge: return 80
            }
        }
        
        var weight: CGFloat {
            switch self {
            case .small: return 1.5
            case .regular: return 2.0
            case .large: return 3.0
            case .extraLarge: return 1
            }
        }
    }
    
    enum SpinnerStyle {
        case brand
        case subtle
        case system // Adaptive gray for both light/dark
        case ghost
    }
    
    var size: SpinnerSize = .regular
    var style: SpinnerStyle = .brand
    
    // MARK: - SwiftUI Bridge
    
    func makeUIView(context: Context) -> UIView {
        let container = YondoSpinnerView(size: size, style: style)
        
        // Call the static setup so UIKit and SwiftUI share the logic
        Self.configure(container, size: size, style: style)
        
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Essential: Re-configure colors if the system theme changes
        Self.updateColors(for: uiView, style: style, traitCollection: uiView.traitCollection)
        
        if uiView.layer.animation(forKey: "rotation") == nil {
            Self.addAnimation(to: uiView)
        }
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: size.value, height: size.value)
    }

    // MARK: - UIKit Bridge
    
    /// Call this from UIKit to get a ready-to-use spinner view
    static func create(size: SpinnerSize = .regular, style: SpinnerStyle = .brand) -> UIView {
        let view = YondoSpinnerView(size: size, style: style)
        configure(view, size: size, style: style)
        return view
    }

    // MARK: - Private Core Logic
    
    private static func configure(_ view: UIView, size: SpinnerSize, style: SpinnerStyle) {
        let sizeVal = size.value
        let lineWidth = size.weight
        let radius = (sizeVal - lineWidth) / 2
        
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: sizeVal),
            view.heightAnchor.constraint(equalToConstant: sizeVal)
        ])
        
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.backgroundColor = UIColor.clear.cgColor
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = CGRect(x: 0, y: 0, width: sizeVal, height: sizeVal)
        
        // Align the path perfectly with the gradient's native seam at 0 radians
        let path = UIBezierPath(arcCenter: CGPoint(x: sizeVal/2, y: sizeVal/2),
                                radius: radius,
                                startAngle: 0,
                                endAngle: .pi * 2,
                                clockwise: true)
        
        shapeLayer.path = path.cgPath
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor.black.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.lineCap = .round
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.type = .conic
        gradientLayer.frame = CGRect(x: 0, y: 0, width: sizeVal, height: sizeVal)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.mask = shapeLayer
        gradientLayer.backgroundColor = UIColor.clear.cgColor
        
        view.layer.addSublayer(gradientLayer)
        
        view.clipsToBounds = true
        
        // Initial color & animation setup
        updateColors(for: view, style: style, traitCollection: view.traitCollection)
        addAnimation(to: view)
    }
    
    // MARK: - Consolidated Color Logic
    
    fileprivate static func updateColors(for view: UIView, style: SpinnerStyle, traitCollection: UITraitCollection?) {
        guard let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer else { return }
        
        let isDarkMode = traitCollection?.userInterfaceStyle == .dark
        
        let clearColor: CGColor
        let solidColor: CGColor
        var midColor: CGColor? = nil
        
        // Set up our safe zones: 0.05 protects the clear tail, 0.95 protects the solid head
        var locations: [NSNumber] = [0.0, 0.05, 0.95, 1.0]
        
        switch style {
        case .brand:
            solidColor = UIColor(Color.yondoBrand).cgColor
            midColor = UIColor(Color.yondoGlow).cgColor
            clearColor = UIColor(Color.yondoBrand).withAlphaComponent(0.0).cgColor
            locations = [0.0, 0.05, 0.5, 0.95, 1.0]
            
        case .ghost:
            solidColor = UIColor.white.withAlphaComponent(0.3).cgColor
//            solidColor = UIColor.white.withAlphaComponent(0.75).cgColor
//            solidColor = UIColor.white.withAlphaComponent(1.0).cgColor
            clearColor = UIColor.white.withAlphaComponent(0.0).cgColor
            
        case .subtle:
            solidColor = UIColor.white.withAlphaComponent(0.6).cgColor
            clearColor = UIColor.white.withAlphaComponent(0.0).cgColor
            
        case .system:
            if isDarkMode {
                // Adaptive subtlety in dark mode
                solidColor = UIColor.white.withAlphaComponent(0.6).cgColor
                clearColor = UIColor.white.withAlphaComponent(0.0).cgColor
            } else {
                // Default system gray in light mode
                solidColor = UIColor.systemGray.withAlphaComponent(0.9).cgColor
                clearColor = UIColor.systemGray.withAlphaComponent(0.0).cgColor
            }
        }
        
        // Apply colors matching the location map
        if let mid = midColor {
            gradientLayer.colors = [clearColor, clearColor, mid, solidColor, solidColor]
        } else {
            gradientLayer.colors = [clearColor, clearColor, solidColor, solidColor]
        }
        gradientLayer.locations = locations
    }
    
    private static func addAnimation(to view: UIView) {
        guard let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer,
              let shapeLayer = gradientLayer.mask as? CAShapeLayer else { return }

        view.layer.removeAllAnimations()
        shapeLayer.removeAllAnimations()
        gradientLayer.removeAllAnimations()

        // 1. Safe Zones: Leave a gap for the rounded lineCaps to draw without crossing the seam
        shapeLayer.strokeStart = 0.05
        shapeLayer.strokeEnd = 0.95

        // 2. Continuous Linear Rotation
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        // Start at -90 degrees (12 o'clock) to preserve your original visual starting point
        rotation.fromValue = -CGFloat.pi / 2
        rotation.toValue = CGFloat.pi * 1.5
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        // Animate the entire view layer so the mask and gradient stay locked together
        view.layer.add(rotation, forKey: "rotation")
    }
    
    // MARK: - Internal Subclass to handle system changes
    
    private class YondoSpinnerView: UIView {
        var size: SpinnerSize
        var style: SpinnerStyle
        
        init(size: SpinnerSize, style: SpinnerStyle) {
            self.size = size
            self.style = style
            super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.value, height: size.value)))
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private var traitRegistration: (any UITraitChangeRegistration)? = nil
        
        override func tintColorDidChange() {
            super.tintColorDidChange()
            updateColors()
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                // Register for user interface style changes (iOS 17+)
                if #available(iOS 17.0, *) {
                    traitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: YondoSpinnerView, _: UITraitCollection) in
                        view.updateColors()
                    }
                }
                // Ensure colors are correct on first attach
                updateColors()
            } else {
                // View detached from window, clear registration
                if #available(iOS 17.0, *) {
                    traitRegistration = nil
                }
            }
        }

        deinit {
            if #available(iOS 17.0, *) {
                traitRegistration = nil
            }
        }
        
        func updateColors() {
            // Forward directly to the consolidated logic
            WormSpinner.updateColors(for: self, style: style, traitCollection: self.traitCollection)
        }
    }
}
