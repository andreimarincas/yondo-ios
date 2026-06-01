//
//  FirebaseImagePreprocessor.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.03.2026.
//

import UIKit
import os

struct FirebaseImagePreprocessor: ImagePreprocessing, Sendable {
    
    /// Prepares a selfie for AI generation by squaring it and compressing to JPEG.
    /// - Parameter image: The raw UIImage from the camera or library.
    /// - Returns: Compressed JPEG data.
    func prepareSelfie(_ image: UIImage) throws -> Data {
        // 1. Determine the square dimensions (e.g., 1024x1024)
        let targetSize = CGSize(width: 512, height: 512)
//        let targetSize = CGSize(width: 1024, height: 1024)
        
        // 2. Create the square crop/resize
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaledImage = renderer.image { _ in
            let side = min(image.size.width, image.size.height)
            let originX = (image.size.width - side) / 2
            let originY = (image.size.height - side) / 2
            
            let cropRect = CGRect(x: -originX, y: -originY, width: image.size.width, height: image.size.height)
            
            // Draw the image into the square context, maintaining aspect fill
            let ratio = targetSize.width / side
            let drawRect = CGRect(
                x: cropRect.origin.x * ratio,
                y: cropRect.origin.y * ratio,
                width: image.size.width * ratio,
                height: image.size.height * ratio
            )
            
            image.draw(in: drawRect)
        }
        
        // 3. Compress to JPEG (0.8 is the "Sweet Spot" for AI detail vs. size)
        guard let data = scaledImage.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "ImagePreprocessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
        }
        
        Log.debug("Image prepared: \(data.count / 1024) KB")
        return data
    }
}
