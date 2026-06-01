//
//  InteractiveImageView+Setup.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit

extension InteractiveImageView {
    func setupView() {
        self.clipsToBounds = true
        
        setupFlyerImageView()
        setupZomableImageView()
        
        addGestureRecognizers()
    }
}

private extension InteractiveImageView {
    func setupFlyerImageView() {
        flyerImageView.isUserInteractionEnabled = true
        flyerImageView.contentMode = .scaleAspectFill // Better for exact frame fits
        flyerImageView.applyHeroRenderingQuality()
        addSubview(flyerImageView)
    }
    
    func setupZomableImageView() {
        zoomableImageView.alpha = 0
        zoomableImageView.isUserInteractionEnabled = true
        zoomableImageView.layer.masksToBounds = true
        zoomableImageView.applyHeroRenderingQuality()
        
        zoomableImageView.onBackgroundTap = { [weak self] in
            self?.coordinator?.triggerDismissal()
        }
        zoomableImageView.onImageTap = { [weak self] in
            self?.coordinator?.toggleDarkMode()
        }
        
        addSubview(zoomableImageView)
    }
    
    func addGestureRecognizers() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        self.addGestureRecognizer(pan)
        self.panGesture = pan
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        self.addGestureRecognizer(pinch)
        self.pinchGesture = pinch
    }
}
