//
//  ImageShareProvider.swift
//  Yondo
//
//  Created by Andrei Marincas on 04.02.2026.
//

import SwiftUI
import Combine

/// Height for small detent
private let smallHeight: CGFloat = 150

@MainActor
class ImageShareProvider: ObservableObject {
    @Published var showsSheet: Bool = false
    @Published var hostIsActive: Bool = false
    
    let resetStream = PassthroughSubject<Void, Never>()
    let metadataStream = PassthroughSubject<ImageMetadataProvider, Never>()
    private(set) var currentMetadata: ImageMetadataProvider?
    private(set) var currentRequestID: UUID?
    
    private let imageStore: ImageStoring?
    private var loadingTask: Task<Void, Never>?
    
    init(imageStore: ImageStoring? = nil) {
        self.imageStore = imageStore
    }
    
    enum ShareSource {
        case entry(GeneratedImage)
        case direct(full: UIImage, thumb: UIImage?)
    }
    
    /// Determines if the share action is available.
    ///
    /// We check two flags to prevent "Lifecycle Collisions":
    /// 1. `showsSheet`: The SwiftUI state driving the sheet presentation.
    /// 2. `hostIsActive`: Set to false only when `dismantleUIViewController` is called.
    ///
    /// This ensures the user cannot trigger a new share session until the previous
    /// UIKit 'Beast' (UIActivityViewController) has been fully torn down,
    /// avoiding "ghosting" artifacts and empty sheet states during rapid taps.
    var canShare: Bool {
        !showsSheet && !hostIsActive
    }
    
    func share(_ source: ShareSource) {
        guard canShare else { return }
        hostIsActive = true
        
        loadingTask?.cancel()
        resetStream.send()
        
        let requestID = UUID()
        self.currentRequestID = requestID
        
        showsSheet = true
        
        loadingTask = Task {
            let images = await fetchImages(from: source)
            guard !Task.isCancelled, self.currentRequestID == requestID else { return }
            
            guard let highRes = images.full else {
                cancel(specificID: requestID)
                // TODO: Show error?
                return
            }
            let thumb = images.thumb ?? highRes
            let metadata = ImageMetadataProvider(image: highRes, thumbnail: thumb)
            
            guard !Task.isCancelled, self.currentRequestID == requestID else { return }
            
            self.currentMetadata = metadata
            metadataStream.send(metadata)
        }
    }
    
    /// Smart Cancel
    /// If specificID is provided, only cancel if it matches the current one.
    /// If no ID is provided (manual cancel button), cancel everything.
    func cancel(specificID: UUID? = nil) {
        if let specificID = specificID {
            guard specificID == currentRequestID else {
                // The task running is NEWER than the one trying to cancel it.
                // Do nothing. Let the new task live.
                return
            }
        }
        
        loadingTask?.cancel()
        loadingTask = nil
        currentMetadata = nil
        currentRequestID = nil
        showsSheet = false
    }
    
    private func fetchImages(from source: ShareSource) async -> (thumb: UIImage?, full: UIImage?) {
        switch source {
        case .entry(let entry):
            guard let store = imageStore else {
                Log.error("Missing image store.")
                return (nil, nil)
            }
            let full = await store.loadFullImage(for: entry)
            let thumb = await store.loadThumbnail(for: entry)
            return (thumb: thumb, full: full)
            
        case .direct(let full, let thumb):
            return (thumb: thumb, full: full)
        }
    }
}
