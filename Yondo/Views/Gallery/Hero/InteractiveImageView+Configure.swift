//
//  InteractiveImageView+Configure.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit
import Combine

extension InteractiveImageView {
    func configure(with entry: GeneratedImage, starterImage: UIImage?, imageStore: ImageStore) {
        // 1. Avoid redundant re-configuration
        guard self.imageProvider?.entry.id != entry.id else { return }
        
        // 2. Clean up old subscriptions if this view is being reused
        cancellables.removeAll()
        
        // 3. Create the provider (Keep it idle/passive)
        self.imageProvider = FullSizeImageProvider(
            entry: entry,
            starterImage: starterImage,
            imageStore: imageStore
        )
        
        // 4. Set the initial low-res image immediately for the Hero Flight
        setInitialImage(entry: entry, imageStore: imageStore)
    }
    
    func startLoading() {
        // 🛡️ IMPORTANT: If we're already loading, don't restart the task!
        // Prevent multiple subscriptions to the same provider
        guard cancellables.isEmpty else { return }
        
        // Start the high-res upgrade process in the provider
        imageProvider?.startUpgradeCycle()
        
        // Listen for the "Resolution Pop" only when this view is active/near-active
        imageProvider?.$displayImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                if let image = image {
                    self?.setImage(image)
                }
            }
            .store(in: &cancellables)
    }
    
    func stopLoading() {
        // 1. Kill the Combine subscription to stop the "Resolution Pop"
        cancellables.removeAll()
        
        // 2. Stop the provider's active tasks (Network/Disk)
        imageProvider?.stopUpgradeCycle()
        
        // 3. DORMANT RESET:
        // Reset zoom scale to 1.0. This is a safety net for "distant" jumps
        // and ensures the coordinate system is centered before memory flushing.
        resetZoom(animated: false)
        
        // 4. MEMORY FLUSH:
        // Revert to the lightweight thumbnail. This releases the high-res
        // CGImage texture from the GPU's memory buffer.
        downgradeImage()
    }
    
    func setImage(_ image: UIImage?) {
        // 🔑 Optimization: identity check
        // Check if we actually have anything to do.
        // We only exit if BOTH views already have this exact object.
        if flyerImageView.image === image && zoomableImageView.imageView.image === image {
            return
        }
        
        // Initial Load (First frame)
        // 🔑 ADD: If we are actively interacting, don't do the cross-dissolve.
        // Just update the data so it's ready for when they release.
        guard flyerImageView.image != nil || isDragging || isSnappingBack else {
            flyerImageView.image = image
            zoomableImageView.configure(with: image)
            return
        }
        
        // The Swap Logic
        // If we are currently "In Flight" (transitioning from grid) or dragging,
        // we want an INSTANT swap. This maintains the "Growing" illusion.
        let isTransitioning = !isFlightDone
        
        if isTransitioning || isDragging || isSnappingBack {
            // Instant swap: No animation, no flash, just data update.
            self.flyerImageView.image = image
        } else {
            // The image is already full screen and settled.
            // NOW we can use a gentle fade to "sharpen" it without breaking the hero effect.
            UIView.transition(with: flyerImageView,
                              duration: 0.2,
                              options: .transitionCrossDissolve,
                              animations: {
                self.flyerImageView.image = image
            }, completion: nil)
        }

        // ALWAYS sync the zoom layer if it doesn't have this image yet
        zoomableImageView.configure(with: image)
    }
}

private extension InteractiveImageView {
    func setInitialImage(entry: GeneratedImage, imageStore: ImageStore) {
        if let initial = self.imageProvider?.displayImage {
            self.setImage(initial)
        } else if let immediateThumb = imageStore.thumbnail(for: entry) {
            // 🔑 Sync the provider so its 'currentWidth' logic is accurate
            self.imageProvider?.displayImage = immediateThumb
            self.setImage(immediateThumb)
        }
    }
    
    func downgradeImage() {
        if let entry = imageProvider?.entry,
           let thumb = imageProvider?.imageStore.thumbnail(for: entry) {
            
            // We use the direct setter to avoid any cross-dissolve overhead
            // since this is happening behind the scenes.
            if self.flyerImageView.image !== thumb {
                self.flyerImageView.image = thumb
            }
            if self.zoomableImageView.imageView.image !== thumb {
                self.zoomableImageView.configure(with: thumb)
            }
        }
    }
}
