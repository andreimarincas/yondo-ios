//
//  ZoomableImageView.swift
//  Yondo
//
//  Created by Andrei Marincas on 26.12.2025.
//

import SwiftUI

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let backgroundColor: UIColor?
    var isInteractionEnabled: Bool = true
    var onDismiss: (() -> Void)?
    var onBackgroundTap: (() -> Void)?
    
    // 🔑 The Optional Binding from the outside
    private var externalZoomScale: Binding<CGFloat>?
    private var externalIsZooming: Binding<Bool>?
    
    // 🔑 Internal fallback state
    @State private var internalZoomScale: CGFloat = 1.0
    @State private var internalIsZooming: Bool = false

    // Custom Init to handle the optionality
    init(image: UIImage,
         zoomScale: Binding<CGFloat>? = nil,
         isZooming: Binding<Bool>? = nil,
         backgroundColor: UIColor? = .black,
         isInteractionEnabled: Bool = true,
         onBackgroundTap: (() -> Void)? = nil) {
        self.image = image
        self.externalZoomScale = zoomScale
        self.externalIsZooming = isZooming
        self.backgroundColor = backgroundColor
        self.isInteractionEnabled = isInteractionEnabled
        self.onBackgroundTap = onBackgroundTap
    }

    // A helper to get the "active" value
    var currentZoomScale: CGFloat {
        externalZoomScale?.wrappedValue ?? internalZoomScale
    }
    
    var currentIsZooming: Bool {
        externalIsZooming?.wrappedValue ?? internalIsZooming
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, onDismiss: onDismiss, onBackgroundTap: onBackgroundTap)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 3
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = backgroundColor
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
//        scrollView.alwaysBounceVertical = true // Ensure it always bounces so we can pull
        scrollView.bounces = true
        
        // 🔑 Toggle interaction based on SwiftUI state
        scrollView.isUserInteractionEnabled = isInteractionEnabled
        
        // 1. Calculate Initial Frame
        let containerSize = UIScreen.main.bounds.size
        let imageSize = image.size
        
        guard imageSize.width > 0, imageSize.height > 0 else {
            return scrollView
        }
        
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        
        let initialFrame = CGRect(
            x: 0, y: 0,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        let imageView = UIImageView(frame: initialFrame)
        imageView.image = image
        imageView.contentMode = .scaleAspectFill // Better for exact frame fits
        imageView.clipsToBounds = true

        scrollView.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        context.coordinator.onDismiss = onDismiss
        
        // Whenever the scrollview lays out, tell the coordinator to center the image.
        scrollView.onLayout = {
            context.coordinator.centerImage()
        }
        
        // 2. Initial Center
        context.coordinator.centerImage()

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scrollView.addGestureRecognizer(tap)
        
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Keep coordinator's reference to parent fresh
        context.coordinator.parent = self
        
        if scrollView.isUserInteractionEnabled != isInteractionEnabled {
            scrollView.isUserInteractionEnabled = isInteractionEnabled
        }
        
        // 🔑 Sync scale from SwiftUI -> UIKit (if you ever set zoomScale = 1.0 from a button)
        if abs(scrollView.zoomScale - currentZoomScale) > 0.01 {
            scrollView.setZoomScale(currentZoomScale, animated: true)
        }
        
        if let imageView = context.coordinator.imageView, imageView.image != image {
            imageView.image = image
            // Re-calculate frame if high-res aspect ratio differs from thumb
            let containerSize = scrollView.bounds.size
            let ratio = min(containerSize.width / image.size.width, containerSize.height / image.size.height)
            let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            
            imageView.frame = CGRect(origin: .zero, size: newSize)
            scrollView.contentSize = newSize
            context.coordinator.centerImage()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        
        var parent: ZoomableImageView
        
        var onDismiss: (() -> Void)?
        var onBackgroundTap: (() -> Void)? = nil
        
        let doubleTapZoomScale: CGFloat = 2.5
        
        init(_ parent: ZoomableImageView, onDismiss: (() -> Void)? = nil, onBackgroundTap: (() -> Void)? = nil) {
            self.parent = parent
            self.onDismiss = onDismiss
            self.onBackgroundTap = onBackgroundTap
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            
            // 🔑 The Magic: Check if the tap is inside the image frame
            let location = gesture.location(in: scrollView)
            
            if !imageView.frame.contains(location) {
                // Tapped the transparent "glass" margins
                onBackgroundTap?()
            }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: scrollView)
                let zoomRect = zoomRectForScale(scale: doubleTapZoomScale, center: location)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
        
        private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
            guard let scrollView = scrollView else { return .zero }

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
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
            
            let newScale = scrollView.zoomScale
            
            // 🔑 Sync the UIKit scale back to SwiftUI Binding
            // Use a small threshold check to avoid unnecessary state updates
            if abs(parent.currentZoomScale - newScale) > 0.01 {
                DispatchQueue.main.async {
                    // Update external if exists, otherwise internal
                    if let external = self.parent.externalZoomScale {
                        external.wrappedValue = newScale
                    } else {
                        self.parent.internalZoomScale = newScale
                    }
                }
            }
            
//            // 🔑 The "Liquid" Trigger
//            // When the user pinches below 0.9, we start the hero return
//            if scrollView.zoomScale < 0.9 {
//                // We force the zoom back to 1.0 instantly so the
//                // matchedGeometryEffect doesn't look warped
//                scrollView.setZoomScale(1.0, animated: false)
//                
//                DispatchQueue.main.async {
//                    self.onDismiss?()
//                }
//            }
            
//            // 🔑 Detect "Pinch to Dismiss"
//            // If the user pinches below 0.85 scale, trigger dismissal
//            if scrollView.zoomScale < 0.85 {
//                // We use a slight delay or a state change to trigger the binding
//                DispatchQueue.main.async {
//                    self.onDismiss?()
//                }
//            }
        }
        
//        func scrollViewDidScroll(_ scrollView: UIScrollView) {
//            if scrollView.zoomScale <= scrollView.minimumZoomScale {
//                let yOffset = scrollView.contentOffset.y
//                if yOffset < 0 {
//                    // Use a slight dampening (0.7) so the image doesn't
//                    // fly away from the finger too fast
//                    let newOffset = CGSize(width: 0, height: -yOffset * 0.7)
//                    
//                    // Only update if the change is significant to reduce "noise"
//                    if abs(dragOffset.height - newOffset.height) > 0.5 {
//                        DispatchQueue.main.async {
//                            self.dragOffset = newOffset
//                        }
//                    }
//                }
//            }
//        }
        
//        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
//            let yOffset = scrollView.contentOffset.y
//            // If pulled down far enough, trigger dismissal
//            if yOffset < -120 {
//                DispatchQueue.main.async {
//                    self.onDismiss?()
//                }
//            } else {
//                // Snap back
//                withAnimation(.interactiveSpring()) {
//                    self.dragOffset = .zero
//                }
//            }
//        }
        
        // Inside ZoomableImageView.Coordinator
//        func scrollViewDidScroll(_ scrollView: UIScrollView) {
//            // 🔑 THE PULL-TO-DISMISS LOGIC
//            // Only trigger if we are at minimum zoom (not zooming into a detail)
//            if scrollView.zoomScale <= scrollView.minimumZoomScale {
//                let yOffset = scrollView.contentOffset.y
//                
//                // If user pulls down (yOffset becomes negative)
//                if yOffset < -60 {
//                    // Optional: You could pass a 'progress' value to SwiftUI here
//                    // to dim the background as the user pulls.
//                }
//                
//                // Trigger dismissal on release if offset is high enough
//                if !scrollView.isDragging && yOffset < -100 {
//                    DispatchQueue.main.async {
//                        self.onDismiss?()
//                    }
//                }
//            }
//        }
        
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            if parent.currentIsZooming == true {
                DispatchQueue.main.async {
                    if let externalIsZooming = self.parent.externalIsZooming {
                        externalIsZooming.wrappedValue = false
                    } else {
                        self.parent.internalIsZooming = false
                    }
                }
            }
        }
        
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            if parent.currentIsZooming == false {
                DispatchQueue.main.async {
                    if let externalIsZooming = self.parent.externalIsZooming {
                        externalIsZooming.wrappedValue = true
                    } else {
                        self.parent.internalIsZooming = true
                    }
                }
            }
        }
        
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if parent.currentIsZooming == true {
                DispatchQueue.main.async {
                    if let externalIsZooming = self.parent.externalIsZooming {
                        externalIsZooming.wrappedValue = false
                    } else {
                        self.parent.internalIsZooming = false
                    }
                }
            }
        }

        func centerImage() {
            guard let scrollView = scrollView, let imageView = imageView else { return }

            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            // Horizontal centering
            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }

            // Vertical centering
            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }

            imageView.frame = frameToCenter
        }
    }
}

class CenteringScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
