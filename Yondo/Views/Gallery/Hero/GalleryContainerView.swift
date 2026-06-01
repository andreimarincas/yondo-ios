//
//  GalleryContainerView.swift
//  Yondo
//
//  Created by Andrei Marincas on 02.02.2026.
//

import UIKit

class GalleryContainerView: UIView, UIScrollViewDelegate {
    var isFlightDone: Bool = false
    
    let scrollView = UIScrollView()
    private(set) var imageViews: [InteractiveImageView] = []
    
    private var initialStartIndex: Int = 0
    private var hasPerformedInitialScroll = false
    private var currentIndex: Int = 0
    
    // Callbacks to sync back to SwiftUI
    var onIndexChanged: ((Int) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScrollView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupScrollView() {
        scrollView.isPagingEnabled = true
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        addSubview(scrollView)
    }

    func configure(
        with entries: [GeneratedImage],
        startIndex: Int,
        imageStore: ImageStore,
        starterImage: UIImage?,
        columnCount: Int,
        isDeleting: Bool,
        coordinator: UIKitGalleryContainer.Coordinator
    ) {
        // Prevent re-building the entire array if entries haven't changed
        guard imageViews.isEmpty else { return }
        
        self.initialStartIndex = startIndex
        self.currentIndex = startIndex
        
        for (index, entry) in entries.enumerated() {
            let imageView = InteractiveImageView()
            imageView.isInitialPage = (index == initialStartIndex)
            imageView.coordinator = coordinator
            imageView.columnCount = columnCount // Set here
            imageView.isDeleting = isDeleting
            
            // Only the STARTING image gets the starterImage (the low-res transition thumb)
            let isInitialPage = (index == startIndex)
            imageView.configure(
                with: entry,
                starterImage: isInitialPage ? starterImage : nil,
                imageStore: imageStore
            )
            
            // Lock horizontal paging when a vertical dismissal starts
            imageView.onInteractionChanged = { [weak self] isInteracting in
                self?.scrollView.isScrollEnabled = !isInteracting
                self?.onInteractionChanged?(isInteracting)
            }
            
            // Initial Flight trigger
            imageView.onReadyForAnimation = { [weak imageView] in
                guard let view = imageView, index == startIndex else { return }
                coordinator.triggerInitialFlight(view: view)
            }

            scrollView.addSubview(imageView)
            imageViews.append(imageView)
        }
        
        setNeedsLayout()
    }
    
    func updateLoadingStates(currentIndex: Int) {
        for (index, view) in imageViews.enumerated() {
            // Sliding Window: Load current, previous, and next
            if abs(index - currentIndex) <= 1 {
                view.startLoading()
            } else {
                view.stopLoading()
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // 1. Use floor or round to ensure we aren't dealing with .333 widths
        let w = floor(bounds.width)
        let h = bounds.height
        guard w > 0 else { return }
        
        let gutter: CGFloat = 40
        
        // We make the scrollView slightly wider than the screen
        // so that 'paging' happens every (width + gutter) points.
        // 2. Ensure the ScrollView frame is an integer width
        let totalPageWidth = floor(w + gutter)
        scrollView.frame = CGRect(x: 0, y: 0, width: totalPageWidth, height: h)
//        scrollView.frame = bounds
        
        scrollView.contentSize = CGSize(width: totalPageWidth * CGFloat(imageViews.count), height: h)
//        scrollView.contentSize = CGSize(width: (w + gutter) * CGFloat(imageViews.count) - gutter, height: h)
        
        // THE FIX: Add 1 pixel of 'overhang' to the width
        // This ensures the image edge always covers the mathematical boundary.
        let overhungWidth = w + 0 //5.0 // 4.0 for the nudge + 1.0 for right-side safety
        
        // 1. Only position the image views if we haven't scrolled to the start yet,
        // OR if the user isn't currently interacting/dragging.
        if !hasPerformedInitialScroll {
            for (i, view) in imageViews.enumerated() {
                // Force the X-origin to be an exact multiple
                // For the first image (i = 0):
                // (0 * 430) - 0.5 = -0.5
                // The image starts 0.5pt off-screen to the left and ends 0.5pt into the gutter on the right.
                let xOrigin = (CGFloat(i) * totalPageWidth)
                
                view.frame = CGRect(x: xOrigin, y: 0, width: overhungWidth, height: h)
                view.clipsToBounds = true
            }
            
            let offset = CGFloat(initialStartIndex) * totalPageWidth
            scrollView.contentOffset = CGPoint(x: offset, y: 0)
            hasPerformedInitialScroll = true
        } else {
            // 2. Optimization: If we are already initialized, only update frames
            // if the container size actually changed (e.g. rotation),
            // but AVOID doing this during a gesture.
            for (i, view) in imageViews.enumerated() {
                let xOrigin = (CGFloat(i) * totalPageWidth)
                let targetFrame = CGRect(x: xOrigin, y: 0, width: overhungWidth, height: h)
                
                // Only force the frame if it's significantly different
                // AND the view isn't currently the "Hero" being dragged.
                if !view.isInteracting && !view.triggerDismiss {
                    if view.frame != targetFrame {
                        view.frame = targetFrame
                    }
                }
            }
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let w = scrollView.bounds.width
        guard w > 0 else { return }
        
        let offsetX = scrollView.contentOffset.x
        // Calculate the 'floating' index (e.g., 1.2 means we are 20% into the next page)
        let floatingIndex = offsetX / w
        
        // 1. Calculate the target index based on where the user is "leaning"
        // Using a 0.5 threshold (round) is standard, but you can adjust
        // to 0.7 if you want the user to have to swipe "further" to trigger the sync.
        let targetIndex = Int(round(floatingIndex))
        
        // 2. Ensure the index is valid and has actually changed
        if targetIndex != self.currentIndex && targetIndex >= 0 && targetIndex < imageViews.count {
            self.currentIndex = targetIndex
            
            // 🔑 Report immediately to SwiftUI mid-swipe
            onIndexChanged?(targetIndex)
        }
        
        // The current main page
        let primaryIndex = Int(round(floatingIndex))
        
        // The neighbor we are moving toward
        let neighborIndex = floatingIndex > CGFloat(primaryIndex)
            ? primaryIndex + 1
            : primaryIndex - 1

        // Trigger loading for primary and its immediate neighbor
        // Clamp the indices to avoid array out of bounds
        let indicesToWarm = [primaryIndex, neighborIndex].filter { $0 >= 0 && $0 < imageViews.count }
        
        // The Performance Loop
        for (index, imageView) in imageViews.enumerated() {
            if indicesToWarm.contains(index) {
                imageView.startLoading()
            } else {
                // If the image is not a neighbor, stop the high-res task
                // and potentially clear the high-res image from memory.
                imageView.stopLoading()
            }
        }
        
        updateParallaxOffset()
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        handlePageLanding()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // If it's not going to decelerate, it means the user stopped exactly on a page
        if !decelerate {
            handlePageLanding()
        }
    }
    
    private func handlePageLanding() {
        guard !imageViews.isEmpty, imageViews.indices.contains(self.currentIndex) else { return }
        
        // Force the scroll view to snap to the exact integer offset
        // to kill any sub-pixel floating values.
        let w = floor(scrollView.bounds.width) // This includes the gutter now
        if w > 0 {
            let page = round(scrollView.contentOffset.x / w)
            let snappedX = page * w
            if scrollView.contentOffset.x != snappedX {
                scrollView.setContentOffset(CGPoint(x: snappedX, y: 0), animated: true)
            }
        }
        
        /*let w = scrollView.bounds.width
        guard w > 0 else { return }
        
        // Note: The isDragging and isDecelerating flags often become false
        // just before the scrollViewDidEndDecelerating or scrollViewDidEndDragging
        // delegates finish executing.
        
        let index = Int(round(scrollView.contentOffset.x / w))
        
        // 🛡️ THE VALUE GUARD
        // If the index hasn't actually changed, stop here.
        // This prevents redundant SwiftUI re-renders.
        guard index != self.currentIndex else { return }
        self.currentIndex = index
        
        // 1. Finalize the index for the UI (SwiftUI headers, etc.)
        // We don't need the isDragging guard here because the Value Guard
        // ensures we only fire this when a meaningful move happens.
        onIndexChanged?(index)*/
        
        // We no longer need the gesture guard here!
        // The logic in scrollViewDidScroll handles the index sync.
        // Use this strictly for deep memory cleanup.
        let index = self.currentIndex
        // 2. CLEANUP: This is the important part of the landing.
        // We now stop loading images that are far away (outside the 3-image window).
        for (i, view) in imageViews.enumerated() {
            // If the view is not the one we are currently looking at
            if i != index {
                // Reset its zoom scale back to 1.0
                // This ensures that if the user scrolls back to it,
                // it starts "fresh" and full-frame.
                view.resetZoom(animated: false)
            }
            
            if abs(i - index) > 1 {
                view.stopLoading()
            }
        }
    }
}

private extension GalleryContainerView {
    func updateParallaxOffset() {
        // Since we did: scrollView.frame = CGRect(x: 0, y: 0, width: w + gutter, height: h)
        // scrollView.bounds.width IS the pageWidth (screen width + 40)
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        
        let centerX = scrollView.contentOffset.x + (pageWidth / 2)
        
        // Use the same bounds.width for calculations
        let lowerBound = Int(floor(scrollView.contentOffset.x / pageWidth))
        let upperBound = Int(ceil(scrollView.contentOffset.x / pageWidth))
        let range = max(0, lowerBound)...min(imageViews.count - 1, upperBound)
        
        for index in range {
            let imageView = imageViews[index]
            
            // The distance from the center of the image to the center of the scroll window
            let distanceToCenter = imageView.center.x - centerX
            let percentage = distanceToCenter / pageWidth
            
            imageView.updateParallaxOffset(percentage: percentage)
        }
    }
}

/// 🪄 THE "GHOST INSET" CORRECTION
/// In Light Mode, the SwiftUI-to-UIKit bridge or system safe areas can
/// introduce an invisible 4pt horizontal nudge.
/// We apply a constant -4.0 offset to 'pull' the image back to the true
/// screen edge, ensuring the left-side '1px line' is buried and the
/// image is perfectly centered within the display bounds.
private let systemAlignmentOffset: CGFloat = -4.0

extension InteractiveImageView {
    func updateParallaxOffset(percentage: CGFloat) {
        guard isFlightDone else { return }
        guard !isInteracting && !triggerDismiss else { return }
        
        // 1. LOWER INTENSITY:
        // 0.2 means the image only slides 20% of its width.
        // This is the "sweet spot" for depth without motion sickness.
        let intensity: CGFloat = 0.22
        let maxOffset = self.bounds.width * intensity
        
        // 2. SMOOTHER CURVE:
        // Changed from 0.8 to 1.0.
        // A linear 1:1 ratio feels much more grounded and less "twitchy."
        let horizontalTranslation = (-percentage * maxOffset) + systemAlignmentOffset
        
        // 3. APPLY TRANSFORM
        let parallaxTransform = CGAffineTransform(translationX: horizontalTranslation, y: 0)
        
        self.flyerImageView.transform = parallaxTransform
        self.zoomableImageView.transform = parallaxTransform
    }
    
    func resetZoom(animated: Bool) {
        if zoomableImageView.scrollView.zoomScale > 1.0 {
            zoomableImageView.scrollView.setZoomScale(1.0, animated: false)
        }
        
        // Safety: If the user zoomed in, they might have panned away from the center.
        // This ensures the image is re-centered.
        self.zoomableImageView.scrollView.contentOffset = .zero
        
        // Also reset the parallax transforms just in case
        if !animated {
            self.flyerImageView.transform = .identity
            self.zoomableImageView.transform = .identity
        }
    }
}
