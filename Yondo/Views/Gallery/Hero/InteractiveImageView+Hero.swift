//
//  InteractiveImageView+Hero.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit

extension InteractiveImageView {
    func updateHeroState(isHero: Bool, sourceFrame: CGRect, animated: Bool = false, force: Bool = false) {
        // Save data even if we don't animate yet
        self.sourceFrame = sourceFrame
        
        // If we don't have bounds yet, we can't calculate 'To' frames.
        guard bounds.width > 0 else {
            self.isHeroMode = isHero
            return
        }
        
        // Since the Coordinator knows explicitly that it's time for the "Initial Flight,"
        // we shouldn't rely on a state-change check. We should tell the view to ignore the guard just this once.
        if !force {
            guard self.isHeroMode != isHero || self.sourceFrame != sourceFrame else { return }
        }
        
        self.isHeroMode = isHero
        self.sourceFrame = sourceFrame
        
        if animated {
            if !isHero && !isDragging {
                zoomableImageView.scrollView.setZoomScale(1.0, animated: true)
            }
            
            // The "Flight" Animation
            let duration: CGFloat = isHero ? 0.38 : 0.32
            let damping: CGFloat = isHero ? 0.88 : 1.0
            let opacity: CGFloat = isHero ? 1.0 : (triggerDismiss && isDeleting ? 0.3 : 1.0)
            
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: damping, initialSpringVelocity: 0) {
                // This now uses the clean frame logic
                self.updateLayout()
                
                // We call layoutIfNeeded on 'self' to ensure constraints (like the ones in UIZoomableImageView) animate too.
                self.layoutIfNeeded()
                
                self.alpha = opacity
                
            } completion: { _ in
                // 🔑 The flight is officially over
                if isHero {
                    self.finalizeHeroArrival()
                }
            }
        } else {
            updateLayout()
            
            if isHero {
                // Ensure visibility is correct for starting state
                self.flyerImageView.alpha = 1
                self.zoomableImageView.alpha = 0
                
                self.coordinator?.setFlightComplete(true)
                
                updateLayerVisibility()
            }
        }
    }
    
    private func finalizeHeroArrival() {
        // 1. Set local flag so gestures are accepted
        self.isFlightDone = true
        
        // 2. Notify parent
        self.coordinator?.setFlightComplete(true)
        
        // 3. Perform the visual swap immediately
        self.updateLayerVisibility()
        
        // 4. Force alpha swap to ensure the ZoomableImageView is the one receiving touches
        UIView.animate(withDuration: 0.1) {
            self.flyerImageView.alpha = 0
            self.zoomableImageView.alpha = 1
        }
    }
    
    func prepareHeroFlightBack() {
        // 1. Ensure the Flyer is at the exact center before we show it
        updateLayout()
        
        // 2. Perform the actual view swap and image sync
        // This makes Flyer alpha 1 and Zoomer alpha 0
        updateLayerVisibility()
        
        // 3. Reset the Flyer's transform
        // This ensures we start the drag from a 'clean' 1.0 scale at the screen center
        flyerImageView.transform = .identity
        
        // 4. Clean up the Zoomer for its next use
        // We do this AFTER the swap so the user doesn't see the image 'snap'
        // to scale 1.0 before it starts dragging.
        zoomableImageView.scrollView.setZoomScale(1.0, animated: false)
    }
    
    func initiateDismissal(withVelocity: Bool = false) {
        // 1. Kill the engine immediately
        isDragging = false
        // isInteracting stays true because we are in the "final flight" home
        
        // Keep it locked so it doesn't "jump" during the final exit animation
        setZoomerLocked(true)
        
        // 🔑 THE FIX: Disable everything that could trigger a haptic
        zoomableImageView.scrollView.pinchGestureRecognizer?.isEnabled = false
        zoomableImageView.scrollView.bouncesZoom = false
        
        // 2. Normalize the visual state
        // If it was a high-speed flick/pinch, we use a faster animation (0.1)
        // If it's a standard release, we use a slightly softer one (0.15)
        let duration = withVelocity ? 0.1 : 0.15
        
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            let safeScale = max(self.dynamicMinScale, self.lastDragScale)
            self.flyerImageView.transform = CGAffineTransform.identity
                .translatedBy(x: self.currentPanTranslation.x, y: self.currentPanTranslation.y)
                .scaledBy(x: safeScale, y: safeScale)
            
            // Also ensure corner radius is synced for the flight
            self.flyerImageView.layer.cornerRadius = self.dynamicCornerRadius
        }
        
        // We stop updating the transform here.
        // The next call to updateLayout() inside the animation block
        // will provide the 'To' value (sourceFrame).
        
        // 3. Hand off to the coordinator
        coordinator?.triggerDismissal()
    }
}
