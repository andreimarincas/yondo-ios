//
//  InteractiveImageView+Layout.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit

extension InteractiveImageView {
    func updateLayout(forceToGrid: Bool = false, forceToHero: Bool = false) {
        let effectiveHeroMode: Bool
        if forceToGrid {
            effectiveHeroMode = false
        } else if forceToHero {
            effectiveHeroMode = true
        } else {
            effectiveHeroMode = isHeroMode
        }
        
        if effectiveHeroMode {
            // Fill center
            applyHeroLayout()
        } else {
            // Grid Size (The "Source")
            applyGridLayout()
        }
    }
    
    func applyLayoutWithoutAnimation() {
        UIView.performWithoutAnimation {
            // We only want to 'forceToGrid' if we are actually the image
            // that is supposed to perform the Hero animation.
            if isInitialPage && !isFlightDone {
                // This is the starting image: Start at the grid, wait for flight
                self.updateLayout(forceToGrid: true)
            } else {
                // This is a neighbor: Snap to full size immediately
                // We set isFlightDone to true so the correct layers show up
                self.isFlightDone = true
                self.updateLayout(forceToHero: true)
                self.updateLayerVisibility()
            }
        }
    }
}

private extension InteractiveImageView {
    func applyHeroLayout() {
        let side = self.bounds.width
        let middle = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        
        flyerImageView.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        flyerImageView.center = middle
        
        zoomableImageView.bounds = self.bounds
        zoomableImageView.center = middle
        
        flyerImageView.layer.cornerRadius = 0
        zoomableImageView.layer.cornerRadius = 0
        zoomableImageView.imageView.layer.cornerRadius = 0
    }
    
    func applyGridLayout() {
        // This is what you found worked best.
        // Setting .frame on a transformed view technically "clears"
        // the transform's influence for the next layout pass.
        flyerImageView.frame = sourceFrame
        zoomableImageView.frame = sourceFrame
        
        let dynamicRadius: CGFloat
        if flyerImageView.transform != .identity {
            // Release of interactive dismiss
            
            // A corner radius of 4 on a 0.5 scale image visually looks like a radius of 2.
            // By setting it to 8, we are compensating for that scale so it looks like a 4 to the human eye.
            dynamicRadius = 4.0 * (1.0 / lastDragScale)
            
        } else {
            // Simple close
            dynamicRadius = 4
        }
        
        self.flyerImageView.layer.cornerRadius = dynamicRadius
        self.zoomableImageView.layer.cornerRadius = dynamicRadius
        self.zoomableImageView.imageView.layer.cornerRadius = dynamicRadius
    }
}
