//
//  DataTypes.swift
//  Yondo
//
//  Created by Andrei Marincas on 20.12.2025.
//

import Foundation

enum CameraError: Error {
    case videoDeviceUnavailable  // Indicates the video capture device is not available.
    case addInputFailed          // Indicates failure to add input to the capture session.
    case addOutputFailed         // Indicates failure to add output to the capture session.
    case setupFailed             // Indicates a general failure during camera setup.
}

enum PhotoCaptureError: Error {
    case noPhotoData             // Indicates that no photo data was captured.
}

/// A structure that represents a captured photo.
/// Contains the raw photo data.
struct Photo: Sendable {
    let data: Data               // The raw data of the captured photo.
}
