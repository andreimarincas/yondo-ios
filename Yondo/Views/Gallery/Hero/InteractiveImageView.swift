//
//  InteractiveImageView.swift
//  Yondo
//
//  Created by Andrei Marincas on 26.01.2026.
//

import UIKit
import SwiftUI
import Combine

class InteractiveImageView: UIView {
    let flyerImageView = UIImageView()
    let zoomableImageView = UIZoomableImageView()
    
    weak var coordinator: UIKitGalleryContainer.Coordinator?
    
    var imageProvider: FullSizeImageProvider?
    var cancellables = Set<AnyCancellable>()
    
    var onReadyForAnimation: (() -> Void)?
    private(set) var hasReportedReady = false
    
    // We'll use this to determine if we should be full-screen or grid-sized
    var sourceFrame: CGRect = .zero
    var isHeroMode: Bool = false
    var isFlightDone: Bool = false
    var triggerDismiss: Bool = false
    var columnCount: Int = 3
    var isDeleting: Bool = false
    var isInitialPage: Bool = false
    
    var onInteractionChanged: ((Bool) -> Void)?
    private(set) var isInteracting: Bool = false
    
    var panGesture: UIPanGestureRecognizer?
    var pinchGesture: UIPinchGestureRecognizer?
    
    // Tracking for scale/offset logic
    var cumulativeDistance: CGFloat = 0
    private var lastLocation: CGPoint = .zero
    
    var isDragging = false
    let dismissalThreshold: CGFloat = 80.0
    private let maxDragDistance: CGFloat = 500.0 // Used for scale math
    var lastDragScale: CGFloat = 1.0
    var isSnappingBack = false
    private var currentPinchScale: CGFloat = 1.0
    var currentPanTranslation: CGPoint = .zero
    
    var hasTriggeredHaptic = false
    var hasHitMinScaleHaptic: Bool = false
    var isScaleCurrentlyAboveOne: Bool = true
    var hasTriggeredMinScaleHaptic: Bool = false
    
    private var lastZoomVisibleState: Bool?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        guard !isDragging && !isSnappingBack else { return }
        
        super.layoutSubviews()
        
        // Handle the very first time we get a real size
        if !hasReportedReady && bounds.width > 0 {
            hasReportedReady = true
            applyLayoutWithoutAnimation()
            
            // Tell the coordinator to kick off the "Flight In" on the next run loop
            if isInitialPage && !isFlightDone {
                onReadyForAnimation?()
            }
        }
    }
    
    func updateLayerVisibility() {
        let zoomVisible = showsZoomableImageView
        guard zoomVisible != lastZoomVisibleState else { return }
        lastZoomVisibleState = zoomVisible
        
        Log.debug("updateLayerVisibility: Swapping to \(zoomVisible ? "Zoomer" : "Flyer")")
        
        // 2. Perform the Swap
        // We use alpha instead of isHidden so the transition can be animated if needed,
        // or performed instantly inside performWithoutAnimation blocks.
        
        // 🔑 THE "UNIFIED STACK" STRATEGY:
        // We keep both the Flyer (low-res/stable) and Zoomable (high-res/complex)
        // layers visible and overlapping during dismissal animations.
        //
        // WHY:
        // 1. If dismissing via the 'Close' button while zoomed in, the Zoomable view
        //    is already the visible one. Swapping to the Flyer mid-flight causes a
        //    visual "pop" because the scroll offset doesn't match a static frame.
        // 2. By transforming BOTH layers simultaneously, we ensure that if the
        //    high-res layer needs a millisecond to re-render during a fast shrink,
        //    the Flyer provides a solid visual backing so there's never a flicker.
        // 3. (triggerDismiss && lastDragScale == 1) handles the specific case where
        //    dismissal is triggered by a button tap rather than a pinch-drag.
        let forceZoomVisible = triggerDismiss && lastDragScale == 1
        self.zoomableImageView.alpha = (zoomVisible || forceZoomVisible) ? 1 : 0
        
        // If the Zoomer is visible and at scale 1.0 (settled), hide the flyer.
        // If we are animating (triggerDismiss), show BOTH to prevent flicker.
        let isSettled = zoomVisible && !isDragging && !isSnappingBack && !triggerDismiss
        self.flyerImageView.alpha = isSettled ? 0 : 1
    }
    
    @objc func handlePan(_ panGesture: UIPanGestureRecognizer) {
        let location = panGesture.location(in: self)
        let velocity = panGesture.velocity(in: self)
        
        switch panGesture.state {
        case .began:
            beginInteraction()
            
            // 🔑 This MUST execute so the first delta isn't huge
            lastLocation = location
            
        case .changed:
            // 🔑 FIX THE JUMP: Check if the number of touches just changed
            // If we don't do this, the 'location' jumps to the midpoint between two fingers instantly.
            let translation = panGesture.translation(in: self)
            
            // If the location distance is huge (like a finger landing),
            // we skip the distance math for this frame but keep the translation.
            let deltaX = location.x - lastLocation.x
            let deltaY = location.y - lastLocation.y
            let delta = sqrt(deltaX*deltaX + deltaY*deltaY)
            
            // Threshold to detect a 'touch jump' (usually > 50-100px in one frame)
            if delta < 100 && !isPinching {
                cumulativeDistance += delta
            }
            
            currentPanTranslation.x += translation.x
            currentPanTranslation.y += translation.y
            
            // Reset the gesture so we only get 'deltas'
            panGesture.setTranslation(.zero, in: self)
            lastLocation = location
            
            // Conditional High-Speed Check
            // We only allow the "Fast Hijack" after the user has moved at least 15 points.
            // This gives enough time for one or two frames of 'updateCombinedTransform'
            // to run, providing visual feedback.
            if cumulativeDistance > 15 && velocity.y > 1500 && isDragging && !isSnappingBack {
                initiateDismissal(withVelocity: true)
                return
            }
            
            updateCombinedTransform()
            
        case .ended, .cancelled, .failed:
            // GATEKEEPER: Only finalize if the pinch isn't still being held
            if !isPinching {
                finalizeInteraction(velocity: panGesture.velocity(in: self).y)
            }
            
        default: break
        }
    }
    
    @objc func handlePinch(_ pinchGesture: UIPinchGestureRecognizer) {
        switch pinchGesture.state {
        case .began:
            // Don't call beginInteraction() here if isDragging is already true
            // or it will reset your currentPanTranslation to zero!
            if !isDragging {
                beginInteraction()
            }
            
        case .changed:
            currentPinchScale *= pinchGesture.scale
            
            // 3. Reset the gesture scale to 1.0 so the next frame is a fresh delta
            pinchGesture.scale = 1.0
            
            // High-Speed Pinch Check
            // Velocity < -10 means they are pinching in VERY fast.
            // currentPinchScale < 0.9 ensures they've actually started the pinch.
            if pinchGesture.velocity < -10.0 && currentPinchScale < 0.9 && isDragging && !isSnappingBack {
                initiateDismissal(withVelocity: true)
                return
            }
            
            // Update visuals immediately
            updateCombinedTransform()
            
        case .ended, .cancelled, .failed:
            // GATEKEEPER: Only finalize if the pan isn't still being held
            if !isPanning {
                finalizeInteraction(velocity: 0)
            }
        default: break
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if isDragging {
            finalizeInteraction(velocity: 0)
        }
    }
    
    private var isPinching: Bool { pinchGesture?.state == .began || pinchGesture?.state == .changed }
    private var isPanning: Bool { panGesture?.state == .began || panGesture?.state == .changed }
    
    func beginInteraction() {
        guard !isDragging else { return }
        isDragging = true
        isInteracting = true
        
        // Notify the parent GalleryContainer to lock paging!
        onInteractionChanged?(true)
        
        // 1. Force the ScrollView to stop whatever it's doing
        zoomableImageView.scrollView.pinchGestureRecognizer?.isEnabled = false
        
        // We disable the internal pan immediately so it doesn't fight our vertical dismissal.
        zoomableImageView.scrollView.panGestureRecognizer.isEnabled = false
        
        prepareHeroFlightBack()
        
        // 🔑 LOCK the zoomer so it doesn't zoom in the background
        setZoomerLocked(true)
        
        // 2. 🔑 THE FIX: Aggressively silence the ScrollView's haptics
        // We disable bouncing so the ScrollView doesn't "snap" or haptic on release
        zoomableImageView.scrollView.bouncesZoom = false
        zoomableImageView.scrollView.bounces = false
        
        // 🧠 GESTURE HIJACK:
        // We toggle 'isEnabled' from false to true to "break" the ScrollView's
        // internal tracking of the current pinch. Without this "flip," if the user
        // starts a pinch-to-dismiss, the ScrollView would simultaneously try to
        // zoom the content, causing a jittery "double-scaling" effect.
        // This effectively resets the ScrollView's gesture state so WE own the touch.
        zoomableImageView.scrollView.pinchGestureRecognizer?.isEnabled = true
        
        resetInteractionState()
        resetHaptics()
        
        isScaleCurrentlyAboveOne = true
        
        HapticManager.shared.selectionGenerator.prepare()
    }
    
    private func resetInteractionState() {
        cumulativeDistance = 0
        lastDragScale = 1.0
        currentPinchScale = 1.0
        currentPanTranslation = .zero
    }
    
    var shouldDismissBasedOnState: Bool {
        // 1. If the user is rubber-banding (Scale > 1.0),
        // we should almost never dismiss on release.
        if lastDragScale >= 0.99 { return false }
        
        // 2. If the scale is small, it's a clear signal to dismiss.
        let isSmallEnough = lastDragScale < 0.8
        
        // 3. If they've moved it far, but ONLY if they've also
        // shrunk it at least a little bit.
        let isDistanceMet = cumulativeDistance > dismissalThreshold
        let hasShrunkAtAll = lastDragScale < 0.98
        
        return isSmallEnough || (isDistanceMet && hasShrunkAtAll)
    }
    
    func setZoomerLocked(_ locked: Bool) {
        // We don't disable the recognizer (that kills the touch)
        // Instead, we stop the ScrollView from actually changing its zoomScale
        zoomableImageView.scrollView.isScrollEnabled = !locked
        
        // This is the key: if locked, we force the zoom scale to stay at 1.0
        if locked {
            zoomableImageView.scrollView.setZoomScale(1.0, animated: false)
        }
    }
    
    private func finalizeInteraction(velocity: CGFloat) {
        // Prevent double-firing (important for animation stability)
        // If we already hijacked in '.changed', isDragging is already false.
        guard isDragging && !isSnappingBack else { return }
        
        let isFlickedDown = velocity > 500
        
        if shouldDismissBasedOnState || isFlickedDown {
            initiateDismissal(withVelocity: isFlickedDown)
        } else {
            // Reset local tracking for next time
            currentPinchScale = 1.0
            currentPanTranslation = .zero
            lastDragScale = 1.0
            snapBack() // snapBack handles setting isDragging to false in its completion
        }
    }
    
    private func updateCombinedTransform() {
        // If the high-speed logic (or a flick) sets this to false,
        // we stop all visual updates immediately.
        guard isDragging else { return }
        
        let panScale = 1.0 - (cumulativeDistance / maxDragDistance)
        
        // Use the values calculated in the gesture handlers
        var totalScale = panScale * currentPinchScale
        
        if totalScale > 1.0 {
            // Apply the classic Apple rubber band formula
            // This allows it to grow slightly (e.g., to 1.05) but never fly away
            totalScale = 1.0 + (log10(totalScale)) * 0.2
        } else {
            // Clamp for safety, but allow it to be sensitive
            totalScale = max(dynamicMinScale, min(totalScale, 0.999))
        }
        
        // While dragging, ONLY the flyer is visible.
        // This prevents the "overlap" jump.
        zoomableImageView.alpha = 0.0
        flyerImageView.alpha = 1.0
        
        self.lastDragScale = totalScale
        
        let transform = CGAffineTransform.identity
            .translatedBy(x: currentPanTranslation.x, y: currentPanTranslation.y)
            .scaledBy(x: totalScale, y: totalScale)
        
        flyerImageView.transform = transform
        flyerImageView.layer.cornerRadius = dynamicCornerRadius
        
        zoomableImageView.transform = transform
        zoomableImageView.layer.cornerRadius = dynamicCornerRadius
        
        coordinator?.updateDragScale(totalScale)
        
        triggerHapticIfNeeded(currentScale: totalScale)
    }
    
    private func snapBack() {
        guard !isSnappingBack else { return }
        
        self.isUserInteractionEnabled = false
        self.isSnappingBack = true
        
        // 🔑 THE FIX: Disable pinch and bouncing
        zoomableImageView.scrollView.pinchGestureRecognizer?.isEnabled = false
        zoomableImageView.scrollView.bouncesZoom = false
        
        // Safety: If for some reason the animation doesn't run, reset anyway
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.flyerImageView.transform = .identity
            self.flyerImageView.layer.cornerRadius = 0
            self.zoomableImageView.transform = .identity
            self.zoomableImageView.layer.cornerRadius = 0
            self.coordinator?.updateDragScale(1.0)
            
        } completion: { _ in
            self.resetPostInteraction()
        }
    }
    
    private func resetPostInteraction() {
        // 1. Reset all tracking
        self.currentPinchScale = 1.0
        self.currentPanTranslation = .zero
        self.cumulativeDistance = 0
        
        // 2. IMPORTANT: Turn off the dragging flag BEFORE the visibility swap
        self.isDragging = false
        self.isSnappingBack = false
        self.isInteracting = true
        
        // 🔑 UNLOCK the zoomer now that we are back at 1.0
        self.setZoomerLocked(false)
        
        self.hasTriggeredMinScaleHaptic = false // Reset for next time
        self.isScaleCurrentlyAboveOne = true    // Reset to default
        
        toggleInternalGestures(enabled: true)
        self.isUserInteractionEnabled = true
        self.updateLayerVisibility()
        self.onInteractionChanged?(false) // Unlock paging
    }
    
    private func toggleInternalGestures(enabled: Bool) {
        let scrollView = zoomableImageView.scrollView
        scrollView.pinchGestureRecognizer?.isEnabled = enabled
        scrollView.panGestureRecognizer.isEnabled = enabled
        scrollView.bouncesZoom = enabled
        scrollView.bounces = enabled
    }
    
    private var showsZoomableImageView: Bool {
        // Must be in Hero mode, NOT currently being dragged, and NOT mid-dismissal
        // AND we need to make sure the flight is actually finished!
        // This prevents the zoomer from appearing mid-air if updateLayerVisibility is accidentally called too early
        return isHeroMode && isFlightDone && !isDragging && !triggerDismiss && !isSnappingBack
    }
}

extension InteractiveImageView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 1. Safety first: No touches until the opening animation finishes
        guard isHeroMode && isFlightDone else { return false }
        
        let zoomScale = zoomableImageView.scrollView.zoomScale
        
        // 2. If the user has already zoomed in (even a tiny bit),
        // disable our custom dismissal gestures.
        // We use 1.01 to allow for tiny floating point rounding errors.
        if zoomScale > 1.01 {
            return false
        }
        
        // 3. Pan Gesture: Only allow dismissal drag if the image is at base scale.
        if let pan = panGesture, gestureRecognizer == pan {
            // 🔑 THE FIX:
            // If we are ALREADY interacting (e.g. started via pinch),
            // allow the pan to start regardless of direction.
            if isDragging { return true }
            
            // Otherwise, enforce the directional lock for the initial drag
            let velocity = pan.velocity(in: self)
            
            // 🧠 DIRECTIONAL LOCK:
            // If the horizontal velocity is greater than the vertical,
            // return 'false' so the InteractiveImageView ignores the touch.
            // This lets the paging ScrollView take over.
            // We use a 1.2x multiplier to give paging a slight "priority."
            return abs(velocity.y) > (abs(velocity.x) * 1.2)
        }
        
        // 4. Pinch Gesture:
        // We only want to "catch" the pinch if the user is pinching INWARD.
        // If they pinch OUTWARD from 1.0, let the ScrollView handle it.
        if let pinch = gestureRecognizer as? UIPinchGestureRecognizer {
            if pinch.scale < 1.0 {
                // 🔑 Kill the scrollview's ability to zoom immediately
                zoomableImageView.scrollView.pinchGestureRecognizer?.isEnabled = false
                zoomableImageView.scrollView.pinchGestureRecognizer?.isEnabled = true
                // (Toggling it off/on forces it to fail/reset)
                
                beginInteraction() // Start the flyer transition immediately
                return true
            }
            return false
        }
        
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 1. ALWAYS allow our own internal pan and pinch to work together.
        // This allows the "Pinch + Drag" move which feels very natural.
        let internalGestures = [panGesture, pinchGesture]
        if internalGestures.contains(gestureRecognizer) && internalGestures.contains(otherGestureRecognizer) {
            return true
        }
        
        // 2. DISABLE simultaneous recognition with the Paging ScrollView once we start dragging.
        // This ensures that if the user is dismissing, the gallery doesn't slide sideways.
        if isDragging {
            return false
        }

        return false // Default to exclusivity for stability
    }
}
