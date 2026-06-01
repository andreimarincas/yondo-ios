//
//  InteractiveImageView+Haptics.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit

extension InteractiveImageView {
    func triggerHapticIfNeeded(currentScale: CGFloat) {
        // Only fire haptics while the user is actually touching the screen
        guard isDragging else { return }
        
        // 1. Point of No Return Haptic (Only fire once per direction)
        triggerPointOfNoReturnHaptic()
        
        // 2. The 1.0 "Notch"
        triggerNotchHaptic(currentScale: currentScale)
        
        // 3. The Minimum Floor (with logic lock)
        triggerMinScaleHaptic(currentScale: currentScale)
    }
    
    func resetHaptics() {
        hasTriggeredHaptic = false
        hasHitMinScaleHaptic = false
        hasTriggeredMinScaleHaptic = false
    }
}

private extension InteractiveImageView {
    func triggerPointOfNoReturnHaptic() {
        if shouldDismissBasedOnState {
            if !hasTriggeredHaptic {
                HapticManager.shared.softImpact(intensity: 0.7)
                hasTriggeredHaptic = true
            }
        } else {
            // Only reset if they move significantly back into the safe zone (e.g., distance < 60)
            // This prevents "flicker" haptics if they are sitting right on the 80px line.
            if cumulativeDistance < (dismissalThreshold - 20) && lastDragScale > 0.85 {
                hasTriggeredHaptic = false
            }
        }
    }
    
    func triggerNotchHaptic(currentScale: CGFloat) {
        let isAboveNow = currentScale >= 1.0

        if isAboveNow && !isScaleCurrentlyAboveOne {
            // Fired when crossing from below to above 1.0
            HapticManager.shared.select()
            isScaleCurrentlyAboveOne = true
        }
        else if currentScale < 0.98 {
            // This is the "reset" point.
            // We only unlock the haptic once they've pulled away significantly.
            isScaleCurrentlyAboveOne = false
        }
    }
    
    func triggerMinScaleHaptic(currentScale: CGFloat) {
        let isAtOrBelowFloor = currentScale <= dynamicMinScale
        
        if isAtOrBelowFloor {
            if !hasTriggeredMinScaleHaptic {
                HapticManager.shared.softImpact(intensity: 0.5)
                hasTriggeredMinScaleHaptic = true // Lock it
            }
        } else {
            // Only unlock when they pull back up significantly
            // (adds a tiny bit of "stickiness" to the floor)
            if currentScale > (dynamicMinScale + 0.02) {
                hasTriggeredMinScaleHaptic = false
            }
        }
    }
}
