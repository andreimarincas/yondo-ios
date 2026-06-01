//
//  InteractiveImageView+Utils.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.02.2026.
//

import UIKit

extension InteractiveImageView {
    var dynamicCornerRadius: CGFloat {
        // 🛡️ Use the local value we JUST calculated in the gesture loop
        let currentScale = self.lastDragScale
        
        // 2. Map the progress (1.0 = Full Screen, 0.45 = Max Drag/Thumbnail size)
        // We normalize this so 0.0 is Full Screen and 1.0 is the "Home" state.
        let progress = (1.0 - currentScale) / (1.0 - dynamicMinScale)
        let clampedProgress = min(max(progress, 0), 1)
        
        // 3. Apply the radius
        // Full screen (progress 0) -> 0 radius
        // Home/Small (progress 1) -> 4 radius
        let targetRadius: CGFloat = 4.0 * (1.0 / currentScale)
        
        // Using a power of 2.0 makes the rounding "wait" until the image is
        // significantly smaller before it starts looking round.
        return pow(clampedProgress, 2.0) * targetRadius
    }
    
    var dynamicMinScale: CGFloat {
        // If 2 columns, thumbnails are roughly 50% width.
        // If 3 columns, thumbnails are roughly 33% width.
        // We set the minScale slightly higher than the actual thumb size
        // to ensure the "flight back" has some room to shrink into the grid.
        return columnCount <= 2 ? 0.55 : 0.42
    }
    
    func applyRubberBand(value: CGFloat, limit: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        if value <= limit { return value }
        // The classic Apple rubber-band formula: limit + (value - limit) * constant
        // For a more natural feel, we use a log-based approach:
        return limit + (1.0 + log10(value / limit)) * 0.1
    }
}
