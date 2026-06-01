//
//  UICenteringScrollView.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

class UICenteringScrollView: UIScrollView {
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard let imageView = delegate?.viewForZooming?(in: self) as? UIImageView,
              let image = imageView.image,
              image.size.width > 0, image.size.height > 0
        else { return }
        
        // 🔑 THE REFINEMENT:
        // Only force the frame size if we are NOT currently in the middle of a
        // gesture-driven zoom or a bounce animation. This prevents the "jitter"
        // when the ScrollView is trying to snap back to 1.0.
        if zoomScale == 1.0 && !isZooming && !isZoomBouncing {
            let boundsSize = bounds.size
            let imageSize = image.size
            
            let widthScale = boundsSize.width / imageSize.width
            let heightScale = boundsSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)
            
            let newSize = CGSize(width: imageSize.width * minScale,
                                 height: imageSize.height * minScale)
            
            // Only update if the delta is significant to avoid redundant layout passes
            if abs(imageView.frame.size.width - newSize.width) > 0.1 {
                imageView.frame.size = newSize
                contentSize = newSize
            }
        }
        
        centerContent(imageView)
    }
    
    private func centerContent(_ zoomView: UIView) {
        let boundsSize = bounds.size
        var frameToCenter = zoomView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        zoomView.frame = frameToCenter
        Log.debug("centered")
    }
}
