//
//  ScenesHomeView+Logic.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

extension ScenesHomeView {
    
    // MARK: - Actions
    
    func handleDidAddNewImage(entry: GeneratedImage, scrollProxy: ScrollViewProxy) {
        // 1. Safety Check: Don't move the floor while the Hero is in the air
        guard selectedEntry == nil && !isVisualHeroMode else {
            // Optional: you could save this entry to 'pendingScrollEntry' here
            return
        }
        
        // 2. Proximity Check: Is the user actually looking at the top?
        // -100 to -200 is usually the sweet spot for "Near Top"
        
        // Check if user is near the top relative to the header
        let isNearTop = scrollOffset > -250
        
        if isNearTop {
            // 2. Sync the snapshot FIRST
            // We use a specific animation so the new item slides in
            // Using a slightly slower spring for the addition
            // to give the grid time to rearrange columns if needed.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                self.snapshottedImages = imageStore.entries
                
                scrollProxy.scrollTo("SCROLL_TOP_ID", anchor: .top)
            }
        } else {
            // Silent update for background/deep gallery scenarios
            // The user stays where they are, but the new image will be
            // waiting for them when they manually scroll up.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                self.snapshottedImages = imageStore.entries
            }
        }
    }
    
    func handleDeleteAction() {
        guard let entry = selectedEntry else { return }
        
        // 1. Lock the UI so the user can't tap anything else
        withAnimation(.easeInOut(duration: 0.2)) {
            isPerformingDelete = true // This triggers the Grid Item dimming
            isSelectionLocked = true
        }
        
        self.triggerDismiss.toggle()
        
        // 3. Wait for the 'Flight' to finish before removing data
        // This matches the spring duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            
            // Animate the grid items sliding into the new gap
            // Ensure the snapshot sync and selection clearing happen in the same transaction
            // The spring animation here will now also handle the
            // transition between 3-columns and 2-columns if the threshold is hit.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                // Remove from the source of truth
                imageStore.delete(entry: entry)
                
                // IMMEDIATELY sync the local snapshot so the grid gap closes
                // while the selectedEntry is being nil-ed out.
                snapshottedImages = imageStore.entries
                
                // Clear the selection
                selectedEntry = nil
            } completion: {
                // 🏁 THE UNIFIED RESET
                // This fires exactly when the 0.5s spring finishes.
                withAnimation(.easeInOut(duration: 0.4)) {
                    isPerformingDelete = false
                    isSelectionLocked = false
                    triggerDismiss = false
                }
            }
            
            // Haptic feedback for the "poof" disappearance
            HapticManager.shared.softSuccess()
        }
    }
    
    // Hero Dismissal Sync
    func handleOnChangeOfVisualHeroMode(_ isHero: Bool) {
        // If we just finished a delete, the snapshot is already current.
        // Skip the catch-up to avoid a double-animation.
        guard !isHero, !isPerformingDelete else { return }
        
        // 🔑 THE "CATCH-UP" LOGIC
        // Once the Hero mode ends (isHero becomes false),
        // we check if our snapshot is out of date and sync it.
        
        let actualEntries = imageStore.entries
        
        if snapshottedImages.count != actualEntries.count {
            // Wait slightly for the dismissal to settle before sliding items
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    snapshottedImages = actualEntries
                }
            }
        }
    }
}
