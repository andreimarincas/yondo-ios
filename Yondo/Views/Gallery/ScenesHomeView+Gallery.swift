//
//  ScenesHomeView+Gallery.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

extension ScenesHomeView {
    @ViewBuilder
    func galleryGrid() -> some View {
        let columns = gridColumns(for: snapshottedImages.count)
        
        LazyVGrid(columns: columns, spacing: 4) {
            // 1. Image Grid Items
            ForEach(Array(snapshottedImages.enumerated()), id: \.element.id) { index, entry in
                gridItem(entry: entry, index: index)
                    .id(entry.id) // 🔑 Force SwiftUI to link the identity to the ID, not the index
                    .trackFrame(id: entry.id, space: "gallery_space")
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
            }
            
            // 2. Add New Button
            if !snapshottedImages.isEmpty {
                addNewButton(columnCount: columns.count)
            }
        }
        .background(gridHeightTracker)
        .padding(.horizontal, 4)
        .blur(radius: currentBlurRadius)
        .opacity(isVisualHeroMode ? 0.85 : 1.0)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: isVisualHeroMode)
    }
    
    private func gridItem(entry: GeneratedImage, index: Int) -> GridItemContainer {
        // High res is only necessary when tiles are large (2 columns)
        let useHighRes = (currentColumnCount == 2)
        let isDeletingThisItem = isPerformingDelete && selectedEntry?.id == entry.id
        
        return GridItemContainer(
            entry: entry,
            index: index,
            highResMode: useHighRes,
            selectedEntry: $selectedEntry,
            isVisualHeroMode: $isVisualHeroMode,
            imageStore: imageStore,
            isDeleting: isDeletingThisItem,
            onSelect: { loadedImage in
                self.isSelectionLocked = true
                self.transitionImage = loadedImage
                self.triggerDismiss = false
                self.currentDragScale = 1.0
                self.isFullSizeSettled = false
            },
            onLoaded: { _ in
                handleDidLoad(entry: entry, index: index)
            }
        )
    }
    
    @ViewBuilder
    private func addNewButton(columnCount: Int) -> some View {
        Button {
            HapticManager.shared.mediumImpact()
            
            // Small delay to allow haptic feedback to be felt before transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showCreateFlow = true
            }
        } label: {
            CreateNewGridItem(columnCount: columnCount)
                .frame(maxWidth: .infinity) // Ensure it pushes to the edges of the column
        }
        .buttonStyle(YondoGridAddNewButtonStyle())
    }
    
    private func handleDidLoad(entry: GeneratedImage, index: Int) {
        // 🛡️ DUPLICATE GUARD: If we've already tracked this item, bail early.
        // This prevents redundant state-recalculations that can hang the Main Thread.
        guard !loadedImageIds.contains(entry.id) else { return }
        
        // Add the ID to our tracker
        loadedImageIds.insert(entry.id)
        
        // If we've reached our threshold, trigger the swap
        if !isGridFullyRendered {
            // Priority Check
            // Ensure that at least the first 6 images are definitely loaded
            // before we even consider flipping the switch.
            let priorityImagesAreReady = priorityLaunchIDs.isSubset(of: loadedImageIds)
            
            if priorityImagesAreReady && loadedImageIds.count >= priorityCount {
                revealTask?.cancel()
                
                // Wrap in withAnimation to ensure a smooth transition
                // and use MainActor to ensure UI updates are thread-safe.
                revealTask = Task { @MainActor in
                    // Wait for a "Quiet Window" (50ms)
                    // This ensures that if 5 images finish at once,
                    // we only animate once after the last one settles.
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled else { return }
                    
                    // Using withAnimation here is safe because we've filtered out
                    // the "thundering herd" of duplicate reports.
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.isGridFullyRendered = true
                    }
                    printWatchdogHealth()
                }
            }
        }
    }
    
    func scrollEntryToVisible(_ entryID: UUID, scrollProxy: ScrollViewProxy) {
        guard let targetFrame = allSourceFrames[entryID] else { return }
        
        // Use 40 as the standard "forgiveness" zone for 3-column thumbnails
        let buffer: CGFloat = 40
        let screenHeight = UIScreen.main.bounds.height
        let visibleTop = dynamicHeaderHeight + buffer
        let visibleBottom = screenHeight - buffer
        
        var anchor: UnitPoint? = nil
        
        if targetFrame.minY < visibleTop {
            // Snap to the bottom of the header
            // 🔑 Calculate exactly where the header ends as a percentage of the screen
            // The reason we do this is because scrollview ignores top safe area where
            // the contents slide under the glass header
            let headerPercentage = visibleTop / screenHeight
            anchor = UnitPoint(x: 0.5, y: headerPercentage)
            
        } else if targetFrame.maxY > visibleBottom {
            // Snap to the bottom of the screen
            // Here, the bottom anchor respects the bottom safe area
            anchor = .bottom
        }
        
        if let anchor = anchor {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(entryID, anchor: anchor)
            }
        }
    }
}

extension ScenesHomeView {
    
    var priorityCount: Int {
        // If we have total images, we want 12 (4 rows of 3).
        // If the user has fewer than 12 total, we wait for all of them.
        min(imageStore.entries.count, ImageStore.priorityLoadingCount)
    }
    
    private var gridHeightTracker: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { self.contentHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, newSize in
                    self.contentHeight = newSize
                }
        }
    }
    
    func gridColumns(for imagesCount: Int) -> [GridItem] {
        let cols = columnCount(for: imagesCount)
        return Array(repeating: GridItem(.flexible(), spacing: 4), count: cols)
    }
    
    func columnCount(for imagesCount: Int) -> Int {
        // We count 'count + 1' because the "Add New" square takes up a slot.
        // We stay in 2 columns until we have more than 4 items (including the '+' button).
        let totalSlots = imagesCount + 1
        let cols = totalSlots <= 4 ? 2 : 3
        return cols
    }
    
    var currentColumnCount: Int {
        columnCount(for: snapshottedImages.count)
    }
    
    var currentBlurRadius: CGFloat {
        guard isVisualHeroMode else { return 0 }
        
        // 1. Map dragScale (1.0 -> 0.5) to progress (1.0 -> 0.0)
        let progress = max(0, min(1, (currentDragScale - 0.5) / 0.5))
        
        // 2. Use a "slow-out" curve.
        // This keeps the blur at nearly full strength for the first half of the drag.
        let easedProgress = pow(progress, 0.7)
        
        // 3. The "Inky Floor"
        // We set a hard minimum. Even at min scale, it stays blurry.
        let floor: CGFloat = 1.0
        let range: CGFloat = 8.0 //11.0
        
        return floor + (easedProgress * range)
    }
}
