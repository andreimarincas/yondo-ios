//
//  UIKitGalleryContainer.swift
//  Yondo
//
//  Created by Andrei Marincas on 02.02.2026.
//

import SwiftUI
import UIKit

struct UIKitGalleryContainer: UIViewRepresentable {
    let entries: [GeneratedImage]
    @Binding var currentIndex: Int
    let starterImage: UIImage?
    let imageStore: ImageStore
    let sourceFrame: CGRect
    let columnCount: Int
    let isDeleting: Bool
    @Binding var isVisualHeroMode: Bool
    @Binding var dragScale: CGFloat
    @Binding var triggerDismiss: Bool
    @Binding var isFlightComplete: Bool
    @Binding var forceDarkMode: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> GalleryContainerView {
        let container = GalleryContainerView()
        
        // Sync index changes back to SwiftUI
        container.onIndexChanged = { newIndex in
            self.currentIndex = newIndex
        }
        
        container.configure(
            with: entries,
            startIndex: currentIndex,
            imageStore: imageStore,
            starterImage: starterImage,
            columnCount: columnCount,
            isDeleting: isDeleting,
            coordinator: context.coordinator
        )
        
        return container
    }
    
    // This is called immediately after makeUIView
    // and whenever any @Binding or @ObservedObject changes.
    func updateUIView(_ uiView: GalleryContainerView, context: Context) {
        uiView.isFlightDone = isFlightComplete
        uiView.setNeedsLayout()
        
        // Ensure all views have the current environment settings
        // We loop through the internal array to keep them all in sync
        for view in uiView.imageViews {
            view.columnCount = columnCount
            view.isDeleting = isDeleting
            view.triggerDismiss = triggerDismiss
        }
        
        // Handle the Hero State for the CURRENT visible view
        guard currentIndex < uiView.imageViews.count else { return }
        let currentImageView = uiView.imageViews[currentIndex]
        
        // Sync the flight state specifically for the active image
        currentImageView.isFlightDone = isFlightComplete
        
        // 🔑 THE FIX: Identify if this is a "Silent Sync"
        // If the user is dragging the ScrollView, or if the ScrollView is still
        // settling (decelerating), we do NOT want to animate the hero state.
        let isUserSwiping = uiView.scrollView.isDragging || uiView.scrollView.isDecelerating
        
        // Handle the Hero State (The Flight)
        // Only call this if the bounds are ready.
        // The internal guard in updateHeroState will prevent redundant animations.
        if currentImageView.bounds.width > 0 && currentImageView.hasReportedReady {
            currentImageView.updateHeroState(
                isHero: isVisualHeroMode,
                sourceFrame: sourceFrame,
                animated: !isUserSwiping // 🛑 Disable animation if we are mid-swipe
            )
        } else {
            // 🔑 THE SILENT SYNC:
            // If we aren't ready to animate yet, just sync the values silently
            // Sets the data so that when layoutSubviews fires, it knows the target state.
            currentImageView.isHeroMode = isVisualHeroMode
            currentImageView.sourceFrame = sourceFrame
        }
        
        // Manage memory for the neighbors
        uiView.updateLoadingStates(currentIndex: currentIndex)
        
        // Force visibility sync for swiping smoothness
        let range = max(0, currentIndex - 1)...min(uiView.imageViews.count - 1, currentIndex + 1)
        for index in range {
            // THE HAND-OFF
            // This ensures that when isFlightComplete hits 'true' or isVisualHeroMode hits 'false',
            // the UI layers actually swap.
            uiView.imageViews[index].updateLayerVisibility()
        }
    }
    
    static func dismantleUIView(_ uiView: GalleryContainerView, coordinator: Coordinator) {
        // 1. Stop the scroll view from sending any more delegate callbacks
        uiView.scrollView.delegate = nil
        
        // 2. Iterate through all cached image views
        for imageView in uiView.imageViews {
            // Stop Combine subscriptions and resolution upgrades
            imageView.stopLoading()
            
            // Break the weak reference to the coordinator explicitly
            imageView.coordinator = nil
            
            // Clear images to free up texture memory immediately
            imageView.setImage(nil)
        }
        
        // 3. Clear the array to release the InteractiveImageView instances
        // (The GalleryContainerView itself will be deallocated by SwiftUI shortly)
    }
    
    class Coordinator: NSObject {
        var parent: UIKitGalleryContainer
        
        init(_ parent: UIKitGalleryContainer) {
            self.parent = parent
        }
        
        func triggerInitialFlight(view: InteractiveImageView) {
            // Only kick off the "Entry Flight" if we are actually in Hero mode.
            // If we aren't, it means SwiftUI hasn't flipped the switch yet.
            // We'll let updateUIView handle it later once isVisualHeroMode becomes true.
            guard self.parent.isVisualHeroMode else { return }
            
            // Safety Guard: If the user managed to trigger a dismiss or drag
            // before the first layout pass, don't force a flight.
            guard !self.parent.triggerDismiss else { return }
            
            // Use a slight dispatch to ensure we are out of the layout cycle
            DispatchQueue.main.async {
                view.updateHeroState(
                    isHero: true,
                    sourceFrame: self.parent.sourceFrame,
                    animated: true,
                    force: true // 🔑 Bypasses the silent sync guard
                )
            }
        }
        
        func updateDragScale(_ scale: CGFloat, animated: Bool = false) {
            let update = { self.parent.dragScale = scale }
            
            if Thread.isMainThread && !animated {
                update() // Apply immediately for 120Hz tracking
            } else {
                DispatchQueue.main.async {
                    if animated {
                        // Match the timing of your snapBack
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { update() }
                    } else {
                        // Keep it instant for 1:1 finger tracking during pan
                        update()
                    }
                }
            }
        }
        
        func triggerDismissal() {
            DispatchQueue.main.async {
                self.parent.triggerDismiss = true
            }
        }
        
        func toggleDarkMode() {
            DispatchQueue.main.async {
                self.parent.forceDarkMode.toggle()
            }
        }
        
        func setFlightComplete(_ isComplete: Bool) {
            DispatchQueue.main.async {
                self.parent.isFlightComplete = isComplete
            }
        }
    }
}
