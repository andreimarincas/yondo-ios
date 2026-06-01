//
//  YondoSpinner.swift
//  Yondo
//
//  Created by Andrei Marincas on 13.03.2026.
//

import SwiftUI
import UIKit

struct YondoSpinner: UIViewRepresentable {
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
            case .extraLarge: return 6.0
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
        Self.updateColors(for: uiView, style: style)
        
        if uiView.layer.animation(forKey: "outer_rotation") == nil {
            Self.addAnimation(to: uiView)
        }
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: size.value, height: size.value)
    }

    // MARK: - UIKit Bridge
    
    /// Call this from UIKit to get a ready-to-use spinner view
    static func create(size: SpinnerSize = .regular, style: SpinnerStyle = .brand) -> UIView {
        let view = UIView()
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
        let path = UIBezierPath(arcCenter: CGPoint(x: sizeVal/2, y: sizeVal/2),
                                radius: radius,
                                startAngle: -.pi / 2,
                                endAngle: .pi * 1.5,
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
        
        // Initial color setup
        updateColors(for: view, style: style)
        addAnimation(to: view)
    }
    
    private static func updateColors(for view: UIView, style: SpinnerStyle) {
        guard let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer else { return }
        
        switch style {
        case .system:
            let color = UIColor.label
            gradientLayer.colors = [
                color.withAlphaComponent(0.9).cgColor,
                color.withAlphaComponent(0.3).cgColor,
                color.withAlphaComponent(0.9).cgColor
            ]
        case .subtle:
            gradientLayer.colors = [
                UIColor.white.withAlphaComponent(0.6).cgColor,
                UIColor.white.withAlphaComponent(0.3).cgColor,
                UIColor.white.withAlphaComponent(0.6).cgColor
            ]
        case .ghost:
            gradientLayer.colors = [
                UIColor.white.withAlphaComponent(0.8).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor,
                UIColor.white.withAlphaComponent(0.8).cgColor
            ]
        case .brand:
            gradientLayer.colors = [
                UIColor(Color.yondoBrand).cgColor,
                UIColor(Color.yondoGlow).cgColor,
                UIColor(Color.yondoBrand).cgColor
            ]
        }
    }
    
    private static func addAnimation(to view: UIView) {
        guard let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer,
              let shapeLayer = gradientLayer.mask as? CAShapeLayer else { return }

        view.layer.removeAllAnimations()
        shapeLayer.removeAllAnimations()

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 2.0
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        rotation.fillMode = .forwards
        view.layer.add(rotation, forKey: "outer_rotation")

        let headAnim = CABasicAnimation(keyPath: "strokeEnd")
        headAnim.fromValue = 0
        headAnim.toValue = 1.0
        headAnim.duration = 1.0
        headAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let tailAnim = CABasicAnimation(keyPath: "strokeStart")
        tailAnim.fromValue = 0
        tailAnim.toValue = 1.0
        tailAnim.duration = 1.0
        tailAnim.beginTime = 0.5
        tailAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let strokeGroup = CAAnimationGroup()
        strokeGroup.animations = [headAnim, tailAnim]
        strokeGroup.duration = 1.5
        strokeGroup.repeatCount = .infinity
        strokeGroup.isRemovedOnCompletion = false
        strokeGroup.fillMode = .forwards
        shapeLayer.add(strokeGroup, forKey: "stroke_play")
    }
    
    // MARK: - Internal Subclass to handle system changes
    private class YondoSpinnerView: UIView {
        var size: SpinnerSize = .regular
        var style: SpinnerStyle = .brand
        
        init(size: SpinnerSize, style: SpinnerStyle) {
            self.size = size
            self.style = style
            super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.value, height: size.value)))
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private var traitRegistration: (any UITraitChangeRegistration)? = nil
        
        // This is the magic UIKit hook. It triggers whenever the tintColor
        // or dark/light mode changes on this specific view.
        override func tintColorDidChange() {
            super.tintColorDidChange()
            updateColors()
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                // Register for user interface style changes (iOS 17+)
                if #available(iOS 17.0, *) {
                    traitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (_: YondoSpinner.YondoSpinnerView, _: UITraitCollection) in
                        self.updateColors()
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
            guard let gradientLayer = self.layer.sublayers?.first as? CAGradientLayer else { return }
            
            if style == .system {
                let isDarkMode = traitCollection.userInterfaceStyle == .dark
                if isDarkMode {
                    // subtle
                    gradientLayer.colors = [
                        UIColor.white.withAlphaComponent(0.6).cgColor,
                        UIColor.white.withAlphaComponent(0.2).cgColor,
                        UIColor.white.withAlphaComponent(0.6).cgColor
                    ]
                } else {
                    // default to system
                    let color = UIColor.systemGray
                    gradientLayer.colors = [
                        color.withAlphaComponent(0.9).cgColor,
                        color.withAlphaComponent(0.2).cgColor,
                        color.withAlphaComponent(0.9).cgColor
                    ]
                }
            }
        }
    }
}
