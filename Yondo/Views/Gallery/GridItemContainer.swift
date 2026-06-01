//
//  GridItemContainer.swift
//  Yondo
//
//  Created by Andrei Marincas on 25.01.2026.
//

import SwiftUI

struct GridItemContainer: View {
    let entry: GeneratedImage
    let index: Int
    let highResMode: Bool
    @Binding var selectedEntry: GeneratedImage?
    @Binding var isVisualHeroMode: Bool
    @ObservedObject var imageStore: ImageStore
    @State var sourceFrame: CGRect = .zero
    let isDeleting: Bool
    
    var onSelect: (UIImage?) -> Void
    var onLoaded: ((UIImage) -> Void)
    
    @State private var currentImage: UIImage?
    @State private var isReady = false
    @State private var isPressedInternal = false
    @State private var heroTookOff: Bool = false
    @State private var pressStartTime: Date? = nil
    
    var body: some View {
        ZStack {
            Button {
                handleSelect()
            } label: {
                thumbnailView
            }
            .buttonStyle(YondoThumbnailButtonStyle(isPressedBinding: $isPressedInternal))
            .disabled(!isReady)
            .contentShape(Rectangle())
            .onChange(of: selectedEntry) { _, newValue in
                // If the user swiped TO this entry while in Hero mode,
                // we need to "claim" the heroTookOff state instantly.
                if newValue?.id == entry.id && isVisualHeroMode {
                    heroTookOff = true
                } else if newValue?.id != entry.id {
                    // If it's not me, or the hero mode is off, I should be visible.
                    heroTookOff = false
                }
            }
            .onChange(of: isPressedInternal) { _, isPressed in
                if isPressed {
                    pressStartTime = Date()
                }
            }
        }
    }
    
    private func handleSelect() {
        onSelect(currentImage)
        
        // Calculate how long the user held the button
        let holdDuration = Date().timeIntervalSince(pressStartTime ?? Date())
        let springSettlingTime: TimeInterval = 0.22
        
        // If they held it longer than the animation, 0 delay.
        // Otherwise, wait only for the remainder of the animation time.
        let remainingDelay = max(0, springSettlingTime - holdDuration)
        
        // DELAY the hero trigger to allow the "bounce up" to finish
        // 0.15s - 0.2s is the sweet spot for a "playful" feel
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
            executeHeroLaunch()
        }
    }
    
    private func executeHeroLaunch() {
        // We use a non-animated block to hide the source thumbnail immediately
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedEntry = entry
            
            // Small buffer to ensure the 'flyer' in the other view is rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                heroTookOff = true
                pressStartTime = nil
            }
        }
    }
    
    private var thumbnailView: some View {
        AsyncThumbnailView(
            entry: entry,
            index: index,
            imageStore: imageStore,
            loadHighRes: highResMode,
            content: { image in
                image
                    .resizable()
                    .antialiased(true)
                    .interpolation(.high) // 👈 This maps to high-quality filtering in the render pipeline
                    .forceSquareLayout()
                    .liquidPressVisuals(isPressed: isPressedInternal, opacity: opacity)
                    .heroRenderingLogic(opacity: opacity, isPressed: isPressedInternal, heroTookOff: heroTookOff)
                
            }, onLoaded: { [entryID = entry.id, onLoaded] image in
                MainActor.assumeIsolated {
                    guard self.entry.id == entryID else { return }
                    currentImage = image
                    isReady = true
                    onLoaded(image)
                }
            }
        )
    }
    
    private var opacity: Double {
        let isSelected = selectedEntry?.id == entry.id
        
        if isSelected {
            // 🔑 THE SWIPE SYNC:
            // If this is the selected entry AND the hero is active,
            // hide the thumbnail regardless of whether it "launched" from here.
            
            // 0.01 keeps it in the hierarchy, which keeps GeometryReader
            // updates stable while the full-size image is open.
            // If you used 0.0, some versions of SwiftUI might stop updating the geo.frame,
            // which would break the "Return" animation of your Hero transition.
            return (heroTookOff || isVisualHeroMode) ? 0.01 : 1.0
        }
        
        // Limbo/Deletion State:
        // If we aren't selected anymore (Hero is over), but we are
        // marked for deletion, stay dimmed while the grid transition runs.
        if isDeleting { return 0.3 }
        
        return 1.0
    }
}

// MARK: - Thumbnail Modifiers
private extension View {
    
    /// Enforces the grid square aspect ratio logic
    func forceSquareLayout() -> some View {
        self
            .aspectRatio(contentMode: .fill) // 1. Set the fill mode first
            .frame(minWidth: 0, maxWidth: .infinity) // 2. Allow it to fill the grid cell
            .aspectRatio(1, contentMode: .fit) // 3. Force it to be a square
    }
    
    /// Applies the dynamic color shifts for the "Liquid" effect
    func liquidPressVisuals(isPressed: Bool, opacity: Double) -> some View {
        self
            // 💧 LIQUID POLISH: Use dynamic saturation and contrast
            // When pressed, the colors "pool" and become more intense
            // 💧 Resting state is now 1.0 (Natural) to match the Flyer perfectly.
            // 💧 Only "blooms" to Liquid values when isPressed is true.
            .background(Color.black.opacity(opacity)) // Pure black provides better contrast for liquid refraction
            // 💎 THE "COMPRESSED DENSITY" LOOK:
            .saturation(isPressed ? 1.25 : 1.0)   // Higher saturation to fight the blur
            .contrast(isPressed ? 1.15 : 1.0)     // Higher contrast keeps it from looking "washed out"
            
            // 🌈 THE REFRACTION:
            // A tiny shift toward the "cool" side makes it feel like
            // light is bending through a lens.
            .hueRotation(.degrees(isPressed ? 2 : 0))
            
            // 💧 THE BLUR:
            // Keep it very low so it just softens the edges during the squish.
            .blur(radius: isPressed ? 0.5 : 0)
            
            // 🔑 Ensure the transition back to "Natural" is smooth
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
    
    /// Handles the technical requirements for the Hero transition (clipping, opacity, rendering layers)
    func heroRenderingLogic(opacity: Double, isPressed: Bool, heroTookOff: Bool) -> some View {
        self
            .clipped() // Ensure the "fill" doesn't bleed out of the square
            .opacity(opacity) // Hide the source if it's currently flying/selected
            .compositingGroup() // It flattens the view hierarchy into a single layer so the 0.01 opacity doesn't cause multi-layer "graying"
            
            // Note: .drawingGroup() was removed to prevent 'Watchdog' (0x8BADF00D) crashes during launch.
            // While it improves scroll performance by flattening the view into a single Metal-backed
            // layer, the overhead of creating Metal contexts for dozens of grid items simultaneously
            // creates a massive CPU spike that hangs the Main Thread during app initialization.
            //.drawingGroup() // Forces the renderer to treat it as a single pixel-buffer
            
            .animation(.easeInOut(duration: 0.2), value: isPressed)
            .transaction {
                // 🔑 THE FIX: Prevent the "fade" glitch by making the opacity change instant (only on hero fly out)
                // Only kill the animation if we are hiding the item for a standard Hero takeoff.
                // If we are deleting, allow the ghost to fade in smoothly.
                if opacity == 0.01 {
                    $0.animation = nil
                }
            }
            .allowsHitTesting(!heroTookOff)
    }
}
