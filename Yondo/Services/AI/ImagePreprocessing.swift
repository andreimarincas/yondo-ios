//
//  ImagePreprocessing.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import UIKit

/// Protocol responsible for preparing and normalizing user selfies before sending them to the AI.
protocol ImagePreprocessing: Sendable {
    /// Prepares the given selfie image by applying necessary transformations such as resizing, formatting, and compression.
    ///
    /// - Parameter image: The original selfie image to be processed.
    /// - Returns: A `Data` object representing the processed image ready for AI consumption.
    /// - Throws: An error if the image cannot be processed or transformed as required.
    func prepareSelfie(_ image: UIImage) throws -> Data
}
