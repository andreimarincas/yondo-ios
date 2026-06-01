//
//  AsyncThumbnailView.swift
//  Yondo
//
//  Created by Andrei Marincas on 20.01.2026.
//

import SwiftUI

// Helper view to load thumbnails asynchronously
struct AsyncThumbnailView<Content: View>: View {
    let entry: GeneratedImage
    let index: Int
    @ObservedObject var imageStore: ImageStore
    var loadHighRes: Bool = false
    let content: (Image) -> Content
    let onLoaded: ((UIImage) -> Void)
    
    @State private var thumbnail: UIImage?
    @State private var showLoading = false
    @State private var didTimeout = false
    @State private var opacity: Double = 0 // Start invisible
    @State private var hasReportedReady = false
    
    init(entry: GeneratedImage,
         index: Int,
         imageStore: ImageStore,
         loadHighRes: Bool,
         @ViewBuilder content: @escaping (Image) -> Content,
         onLoaded: @escaping ((UIImage) -> Void)
    ) {
        self.entry = entry
        self.index = index
        self.imageStore = imageStore
        self.content = content
        self.onLoaded = onLoaded
        
        // Pre-populate thumbnail from cache to avoid flashing the spinner
        if let cached = imageStore.thumbnail(for: entry) {
            _thumbnail = State(initialValue: cached)
            _opacity = State(initialValue: 1.0) // No fade for cached items
        } else {
            _thumbnail = State(initialValue: nil)
            _opacity = State(initialValue: 0.0) // Prepared to fade in
        }
    }
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                content(Image(uiImage: thumbnail))
                    .opacity(opacity)
                    .transition(.opacity)
            } else {
                // Always show placeholder if thumbnail is missing
                GridPlaceholder()
                
                if showLoading && !didTimeout {
                    RefractionShimmerView()
                        .mask(RoundedRectangle(cornerRadius: 4))
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear {
            /* 🐕 WATCHDOG MONITOR:
             * If you see more than 12-15 of these logs firing simultaneously
             * during a Cold Start, the 'VIP Staging' logic is leaking.
             * We only want the visible rows to 'appear' initially to keep
             * the Main Thread footprint light enough to avoid 0x8BADF00D.
             */
            Log.debug("🚀 VIP Cell Ready: \(entry.id) at index \(index)")
            
            reportIfReady()
        }
        // 🔑 THE SAFETY NET: If the view is swapped but not "appeared",
        // onChange will catch the new entry and report readiness.
        .onChange(of: entry.id, initial: false) { _, _ in
            reportIfReady()
        }
        .task(id: entry.id) {
            // 1. STAGGERED START
            // Prioritize the first few rows during App Launch to keep the UI responsive.
            if AppLaunchContext.isAppLaunching {
                let rowNumber = Double(index / 3)
                // Row 0: 0ms, Row 1: 5ms, Row 2: 10ms...
                // This slight delay prevents thread-pool saturation on the first frame.
                let delay = rowNumber * 5
                Log.debug("⏳ [STAGGER] Delaying Row \(Int(rowNumber)) by \(Int(delay))ms")
                try? await Task.sleep(for: .milliseconds(delay))
            }
            
            // 2. LOAD SEQUENCE
            // This will check cache first, then fetch from disk/network if needed.
            await loadImage()
        }
    }
}

private extension AsyncThumbnailView {
    func loadImage() async {
        // 1. Check Cache First
        let hasThumbnail = updateFromCache()
        
        if hasThumbnail {
            reportIfReady()
            // If we don't need high-res, we are done.
            // If we DO need high-res, we DON'T return, and we DON'T resetUI.
            if !loadHighRes { return }
        } else {
            // 2. Only reset UI (show placeholder) if we have NO image at all
            resetUI()
        }
        
        do {
            // 3. Debounce only if we are about to hit the disk/network
            // We can skip or shorten this if we already have a thumbnail showing
            // If we scroll past, this task cancels here.
            try await Task.sleep(for: .milliseconds(hasThumbnail ? 5 : 10))
            
            // 4. Secondary cache check (in case background threads finished)
            if !hasThumbnail && updateFromCache() {
                reportIfReady()
                if !loadHighRes { return }
            }
            
            // Start a background timer for the spinner/timeout
            let timerTask = startTimeoutTask()
            
            let result = await (
                loadHighRes
                    ? imageStore.loadFullImage(for: entry)
                    : imageStore.loadThumbnail(for: entry)
            )
            
            timerTask.cancel()
            processResult(result)
            
        } catch {
            // Cancellation handled automatically
        }
    }
    
    func updateFromCache() -> Bool {
        guard let cached = imageStore.thumbnail(for: entry) else { return false }
        thumbnail = cached
        opacity = 1.0
        return true
    }
    
    func resetUI() {
        thumbnail = nil
        opacity = 0
        showLoading = false
        didTimeout = false
    }
    
    @MainActor
    func updateUI(with image: UIImage, animate: Bool) {
        if animate {
            withAnimation(.easeIn(duration: 0.25)) {
                self.showLoading = false
                self.thumbnail = image
                self.opacity = 1.0
            }
        } else {
            // Use a transaction to explicitly disable all animations
            // for this state change.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.showLoading = false
                self.thumbnail = image
                self.opacity = 1.0
            }
        }
    }
    
    func processResult(_ result: UIImage?) {
        if let loaded = result {
            let shouldAnimate = !AppLaunchContext.isAppLaunching
            updateUI(with: loaded, animate: shouldAnimate)
            reportIfReady(force: loadHighRes)
        } else {
            showLoading = false // Ensure we hide shimmer on failure too
        }
    }
    
    func startTimeoutTask() -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            showLoading = true
            
            try? await Task.sleep(for: .seconds(3.5)) // exactly 3 full shimmer loops
            guard !Task.isCancelled else { return }
            didTimeout = true
            showLoading = false
        }
    }
    
    // Ensure reporting doesn't cause a re-entrant update cycle
    func reportIfReady(force: Bool = false) {
        guard !hasReportedReady || force else { return }
        let currentID = entry.id
        
        // Use the current local state if available, otherwise check cache
        if let readyImage = thumbnail ?? imageStore.thumbnail(for: entry) {
            hasReportedReady = true
            
            MainActor.assumeIsolated {
                guard self.entry.id == currentID else { return }
                onLoaded(readyImage)
            }
        }
    }
}
