//
//  UIImage+Extensions.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.12.2025.
//

import UIKit

extension UIImage {
    @MainActor
    /// Returns a UIImage mirrored and rotated to match the front camera preview.
    static func fromCapturedCGImage(_ cgImage: CGImage, mirrorSelfie: Bool) -> UIImage {
        if mirrorSelfie {
            // Front camera images usually need to be mirrored/rotated
            // depending on how the hardware buffers are delivered.
            // .leftMirrored is common for front-facing portrait selfies.
            return UIImage(cgImage: cgImage, scale: 1.0, orientation: .leftMirrored)
        } else {
            return UIImage(cgImage: cgImage)
        }
    }
}

extension UIImage {
    static func solidColor(_ color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
}
