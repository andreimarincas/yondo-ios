//
//  ImagePreprocessor.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import UIKit

/// Concrete implementation of `ImagePreprocessing`.
///
/// Responsible for preparing user selfies before they are sent to the AI image generation API.
/// This includes deterministic resizing and encoding to match external API requirements.
///
/// Design notes:
/// - Stateless aside from configuration.
/// - Pure transformation: no disk I/O, no side effects.
/// - Safe to reuse across requests.
final class ImagePreprocessor: ImagePreprocessing {

    struct Configuration {
        let targetSize: CGSize
        let scale: CGFloat

        static let openAI = Configuration(
            targetSize: CGSize(width: 512, height: 512),
            scale: 1.0
        )
    }

    private let config: Configuration

    init(config: Configuration = .openAI) {
        Log.debug("ImagePreprocessor initialized with targetSize=\(config.targetSize), scale=\(config.scale)")
        self.config = config
    }

    func prepareSelfie(_ image: UIImage) throws -> Data {
        Log.debug("Preparing selfie image")
        let resized = try resize(image)
        Log.debug("Selfie resized successfully, encoding to PNG")
        return try pngData(from: resized)
    }

    // MARK: - Private

//    private func resize(_ image: UIImage) throws -> UIImage {
//        Log.debug("Resizing image to \(config.targetSize)")
//        UIGraphicsBeginImageContextWithOptions(
//            config.targetSize,
//            false,
//            config.scale
//        )
//
//        image.draw(in: CGRect(origin: .zero, size: config.targetSize))
//
//        guard let resized = UIGraphicsGetImageFromCurrentImageContext() else {
//            Log.error("Image resize failed")
//            UIGraphicsEndImageContext()
//            throw ImagePreprocessorError.resizeFailed
//        }
//
//        UIGraphicsEndImageContext()
//        return resized
//    }
    
    private func resize(_ image: UIImage) throws -> UIImage {
        Log.debug("Resizing image to \(config.targetSize)")

        // 1. Configure the format to match your specific scale requirements
        let format = UIGraphicsImageRendererFormat()
        format.scale = config.scale // Uses your 1.0 setting
        format.opaque = false       // false = handles transparency (Alpha channel)

        // 2. Initialize the modern renderer
        let renderer = UIGraphicsImageRenderer(size: config.targetSize, format: format)

        // 3. Perform the drawing within the renderer's private context
        // This is safe to run on background threads because it does not touch the global context stack.
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: config.targetSize))
        }

        // Note: UIGraphicsImageRenderer.image is guaranteed to return a UIImage
        // unless the size is zero, making the old guard let check largely unnecessary.
        return resized
    }

    private func pngData(from image: UIImage) throws -> Data {
        Log.debug("Encoding image to PNG data")
        guard let data = image.pngData() else {
            Log.error("PNG encoding failed")
            throw ImagePreprocessorError.encodingFailed
        }
        return data
    }
}

enum ImagePreprocessorError: Error {
    case resizeFailed
    case encodingFailed
}
