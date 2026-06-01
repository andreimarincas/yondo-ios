//
//  UIZoomableImageView.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.01.2026.
//

import UIKit

class UIZoomableImageView: UIView {
    let scrollView = UICenteringScrollView()
    let imageView = UIImageView()
    
    var onBackgroundTap: (() -> Void)?
    var onImageTap: (() -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?
    
    private let doubleTapZoomScale: CGFloat = 2.5
    
    private var imageTap: UITapGestureRecognizer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        self.isUserInteractionEnabled = true
        
        // 1. ScrollView Setup
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        // 2. ImageView Setup
        imageView.contentMode = .scaleAspectFill
        imageView.applyHeroRenderingQuality()
        scrollView.addSubview(imageView)
        
        // 3. Constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // 4. Gestures
        let bgTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        bgTap.delegate = self
        scrollView.addGestureRecognizer(bgTap)
        
        let imgTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        imgTap.delegate = self
        scrollView.addGestureRecognizer(imgTap)
        self.imageTap = imgTap
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        imgTap.require(toFail: doubleTap)
    }
    
    func configure(with image: UIImage?) {
        let imageSize = image?.size ?? .zero
        
        // 0. Guard against zero bounds OR zero image size (division by zero protection)
        guard self.bounds.width > 0, imageSize.width > 0, imageSize.height > 0 else {
            imageView.image = image
            return // Exit early; don't do scale math
        }
        
        // 1. If bounds are zero, we can't do math yet.
        // Wait for the next layout pass.
        guard self.bounds.width > 0 else {
            imageView.image = image // Set image anyway so it's ready
            return
        }
        
        let containerSize = self.bounds.size
        
        // 2. Calculate the "Aspect Fit" scale
        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        
        let newSize = CGSize(width: imageSize.width * minScale,
                             height: imageSize.height * minScale)
        
        // 🔑 THE FIX:
        // If the user is already zoomed in (even by 0.001),
        // don't touch the frame or contentSize, as it will break the active pinch.
        guard scrollView.zoomScale == 1.0 else {
            if imageView.image !== image { imageView.image = image }
            return
        }
        
        // If the scrollview is currently "disabled" (because we're dragging the flyer),
        // do not allow it to update its zoom logic or content size.
        guard scrollView.pinchGestureRecognizer?.isEnabled == true else { return }
        
        // 3. Only update if the image or size actually changed
        if imageView.image !== image || scrollView.contentSize != newSize {
            imageView.image = image
            
            // This keeps the current X and Y, but changes Width and Height
            imageView.frame.size = newSize
            
            scrollView.contentSize = newSize
            
            // Only reset if NOT currently interacting
            if !scrollView.isZooming && !scrollView.isZoomBouncing {
                 scrollView.setZoomScale(1.0, animated: false)
            }
            
            // 🔑 Re-center immediately so the origin isn't (0,0) (don't wait for layoutSubviews)
            centerImage()
            
            // If you want to be 100% sure the subviews (scrollView) update too:
            setNeedsLayout()
        }
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // 🔑 THE LOCK: If the user is zoomed in even a little bit,
        // we ignore taps to avoid theme-flip bugs and layout jitters.
        guard scrollView.zoomScale <= scrollView.minimumZoomScale else { return }
        
        let location = gesture.location(in: scrollView)
        let isTapOnImage = imageView.frame.contains(location)
        
        if gesture == imageTap {
            if isTapOnImage {
                // Image tap by the imageTap gesture, which requires the doubleTap gesture to fail
                onImageTap?()
            }
        } else {
            if !isTapOnImage {
                // Background tap by the bgTap gesture, which does not require the doubleTap gesture to fail
                
                // Tapped the transparent "glass" margins
                onBackgroundTap?()
            }
        }
    }
    
    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = gesture.location(in: scrollView)
            let zoomRect = zoomRectForScale(scale: doubleTapZoomScale, center: location)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }
    
    private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
        let size = CGSize(
            width: scrollView.bounds.size.width / scale,
            height: scrollView.bounds.size.height / scale
        )

        let origin = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )

        return CGRect(origin: origin, size: size)
    }
    
    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        // Horizontal centering
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = floor((boundsSize.width - frameToCenter.size.width) / 2)
        } else {
            frameToCenter.origin.x = 0
        }

        // Vertical centering
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = floor((boundsSize.height - frameToCenter.size.height) / 2)
        } else {
            frameToCenter.origin.y = 0
        }
        
        // Only set the frame if it actually changed.
        // Setting the frame triggers a layout pass which is expensive during a 60fps zoom.
        if !imageView.frame.equalTo(frameToCenter) {
            imageView.frame = frameToCenter
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // If we have bounds now, but our contentSize is still zero,
        // it means the initial configure() failed the math guard.
        // We need to re-run it to ensure the image actually has a size.
        if self.bounds.width > 0 && scrollView.contentSize == .zero {
            if let currentImage = imageView.image {
                configure(with: currentImage)
            }
        }
    }
}

extension UIZoomableImageView: UIScrollViewDelegate {
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        onZoomChanged?(scrollView.zoomScale)
    }
}

extension UIZoomableImageView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 1. Allow double-tap and single-tap to cooperate (one waits for the other to fail)
        if gestureRecognizer is UITapGestureRecognizer, otherGestureRecognizer is UITapGestureRecognizer {
            return true
        }
        
        // 2. 🛡️ PROTECT THE DRAG:
        // If the parent InteractiveImageView is currently dragging (dismissing),
        // we do NOT want the ScrollView to be zooming or panning.
        // Since this view doesn't know about 'isDragging' directly,
        // we rely on the fact that InteractiveImageView disables the ScrollView's gestures.
        
        // 2. 🔑 THE ENABLER: Allow the ScrollView's pinch/pan to "listen"
        // even if the parent InteractiveImageView is currently "dragging".
        // This is what allows the ScrollView to catch the baton during the hand-off.
//        if gestureRecognizer.view is UIScrollView || otherGestureRecognizer.view is UIScrollView {
//            return true
//        }
        
        return false
    }
}
