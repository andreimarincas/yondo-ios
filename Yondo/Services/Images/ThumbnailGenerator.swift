//
//  ThumbnailGenerator.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import UIKit
import ImageIO
import UniformTypeIdentifiers

struct ThumbnailGenerator {
    
    /// High-performance generation using ImageIO to avoid memory spikes
    nonisolated static func generate(from image: UIImage, size: CGSize) async -> UIImage {
        // If we already have the image in memory, we can use CIImage or
        // convert to data to leverage the high-performance sub-sampling.
        // For a new save, it's often best to use the data directly.
        guard let data = image.jpegData(compressionQuality: 1.0) else { return image }
        return generateFromDisk(data: data, maxPixelSize: Int(max(size.width, size.height))) ?? image
    }
    
    nonisolated static func generateFromDisk(data: Data, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // Respects EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    nonisolated static func generateFromURL(_ url: URL, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        // This points to the disk; it doesn't "load" the file until the thumbnail is requested
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

extension ThumbnailGenerator {
    /// Specifically for UI elements that require square avatars/previews
    nonisolated static func generateSquare(from image: UIImage, maxPixelSize: Int) async -> UIImage {
        // Using your original cropping logic but wrapped in the Generator
        guard let cgImage = image.cgImage else { return image }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let length = min(width, height)
        
        let origin = CGPoint(x: (width - length) / 2, y: (height - length) / 2)
        let rect = CGRect(origin: origin, size: CGSize(width: length, height: length))
        
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        
        // Convert cropped CGImage to a Source (Data)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString, 1, nil
        ) else { return image }
        
        CGImageDestinationAddImage(destination, cropped, nil)
        CGImageDestinationFinalize(destination)
        
        // generateFromDisk gives us the raw downsampled pixels
        guard let diskImage = generateFromDisk(data: data as Data, maxPixelSize: maxPixelSize),
              let finalCGImage = diskImage.cgImage else {
            return image
        }
        
        // 🚀 THE FIX: Re-apply the original EXIF orientation to the final UIImage
        return UIImage(cgImage: finalCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
