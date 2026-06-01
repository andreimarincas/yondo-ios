//
//  FullSizeImageProvider.swift
//  Yondo
//
//  Created by Andrei Marincas on 26.01.2026.
//

import SwiftUI
import Combine

@MainActor
class FullSizeImageProvider: ObservableObject {
    @Published var displayImage: UIImage?
    
    private(set) var entry: GeneratedImage
    let imageStore: ImageStore
    private var loadingTask: Task<Void, Never>?
    private var startTime: CFTimeInterval?
    
    // Constants for better readability
    private let midResThreshold: CGFloat = 600
    private let debounceDelayNanoseconds: UInt64 = 200_000_000
    
    init(entry: GeneratedImage, starterImage: UIImage?, imageStore: ImageStore) {
        self.entry = entry
        self.imageStore = imageStore
        self.displayImage = starterImage
    }
    
    func startUpgradeCycle() {
        stopUpgradeCycle() // Reusing the stop logic to ensure clean state
        startTime = CACurrentMediaTime()
        
        loadingTask = Task(priority: .userInitiated) {
            await performUpgrade()
        }
    }
    
    private func performUpgrade() async {
        // 1. Quick Cache/Thumbnail check
        if currentWidth < midResThreshold {
            // Check memory cache
            if let cached = imageStore.thumbnail(for: entry) {
                updateDisplayImage(with: cached, label: "Cache")
            }
            
            if Task.isCancelled { return }
            
            // Check disk for better thumbnail
            if currentWidth < midResThreshold {
                if let midRes = await imageStore.loadThumbnail(for: entry, allowGeneration: false) {
                    if Task.isCancelled { return }
                    updateDisplayImage(with: midRes, label: "Mid-Res")
                }
            }
        }
        
        // 2. Debounce and Load Full-Res
        do {
            try await Task.sleep(nanoseconds: debounceDelayNanoseconds)
            
            if let fullRes = await imageStore.loadFullImage(for: entry) {
                if Task.isCancelled { return }
                
                updateDisplayImage(with: fullRes, label: "Full-Res")
                logCompletion()
            }
        } catch {
            // Silent return on cancellation
        }
    }
    
    func stopUpgradeCycle() {
        loadingTask?.cancel()
        loadingTask = nil
    }
    
    // MARK: - Helpers
    
    private var currentWidth: CGFloat {
        displayImage?.size.width ?? 0
    }
    
    private func updateDisplayImage(with image: UIImage, label: String) {
        guard image !== displayImage else { return }
        
        let currentArea = (displayImage?.size.width ?? 0) * (displayImage?.size.height ?? 0)
        let newArea = image.size.width * image.size.height
        
        if newArea > currentArea || displayImage == nil {
            self.displayImage = image
            Log.debug("📸 [Provider] Updated to \(label) (\(Int(image.size.width))x\(Int(image.size.height)))")
        }
    }
    
    private func logCompletion() {
        guard let start = startTime else { return }
        let duration = CACurrentMediaTime() - start
        Log.debug("✅ [Provider] Full-Res ready in \(String(format: "%.2f", duration))s")
    }
    
    deinit {
        loadingTask?.cancel()
    }
}
