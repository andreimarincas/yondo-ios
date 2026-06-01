//
//  ScenesHomeView+Hero.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

extension ScenesHomeView {
    @ViewBuilder
    var heroOverlay: some View {
        if let entry = selectedEntry {
            fullSizeImageView(entry: entry)
                // We want the "Hero Container" to be considered the same view
                // regardless of which image is currently showing inside it.
//                .id(entry.id)
                .ignoresSafeArea()
                .zIndex(10) // Ensure it stays above the header and grid
                .environment(\.colorScheme, colorScheme == .dark || forceDarkMode ? .dark : .light)
        }
    }
    
    func fullSizeImageView(entry: GeneratedImage) -> FullSizeImageView {
        let isDeletingThisEntry = isPerformingDelete && selectedEntry == entry
        let screenBounds = UIScreen.main.bounds
        let fallbackFrame = CGRect(x: screenBounds.midX, y: screenBounds.midY, width: 0, height: 0)
        
        // 🔑 We use the dictionary to look up the LIVE frame of the CURRENT selectedEntry.
        // This ensures that as you swipe, the 'sourceFrame' passed down is always
        // the coordinates of the image currently being looked at.
        let liveFrame = allSourceFrames[entry.id] ?? fallbackFrame
        
        return FullSizeImageView(
            initialID: entry.id,
            entries: snapshottedImages,
            imageStore: imageStore,
            isPresented: Binding(
                get: { selectedEntry != nil },
                set: { if !$0 { selectedEntry = nil } }
            ),
            sourceFrame: liveFrame,
            onIndexChanged: { newID in
                // Update the signal. The .onChange above will catch this
                // and tell the ScrollViewReader to scroll.
                self.gallerySyncID = newID
                
                // Keep the 'selectedEntry' in sync so if they close,
                // they close on the right image.
                // 2. Update selectedEntry WITHOUT animation
                // This prevents the ZStack from trying to 'animate' the identity switch
                // 🛡️ Disable animations for this specific state change
                // to prevent the "Hero re-flight" flash.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if let nextEntry = snapshottedImages.first(where: { $0.id == newID }) {
                        self.selectedEntry = nextEntry
                    }
                }
            },
            columnsCount: currentColumnCount,
            triggerDismiss: $triggerDismiss,
            isVisualHeroMode: $isVisualHeroMode,
            isDeleting: isDeletingThisEntry,
            forceDarkMode: $forceDarkMode,
            starterImage: transitionImage, // 🔑 Pass image, let View make the Provider
            dragScale: $currentDragScale,
            isFlightCompleteBinding: $isFullSizeSettled
        )
    }
}
