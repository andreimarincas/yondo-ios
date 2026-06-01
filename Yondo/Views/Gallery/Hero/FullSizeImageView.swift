//
//  FullSizeImageView.swift
//  Yondo
//
//  Created by Andrei Marincas on 26.01.2026.
//

import SwiftUI

/// 🔑 ARCHITECTURAL NOTE:
/// We use 'initialID' to provide a stable Identity for this view.
/// Because 'initialID' stays constant throughout the life of this view,
/// SwiftUI's diffing engine locks the view's identity.
///
/// This allows 'currentIndex' and 'selectedEntry' to "dance around" (change)
/// during swipes without SwiftUI replacing/re-initializing the entire
/// UIKit/Container tree. Only the 'sourceFrame' property updates,
/// keeping the transition fluid.
struct FullSizeImageView: View {
    let initialID: UUID
    let entries: [GeneratedImage]
    @ObservedObject var imageStore: ImageStore
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    let onIndexChanged: ((UUID) -> Void)?
    let columnsCount: Int
    @Binding var triggerDismiss: Bool
    @Binding var isVisualHeroMode: Bool
    let isDeleting: Bool
    @Binding var forceDarkMode: Bool
    @Binding var dragScale: CGFloat
    @Binding var isFlightCompleteBinding: Bool
    
    @State private var animateIn = false
    @State private var isFlightComplete = false
    @State private var currentIndex: Int
    
    private let starterImage: UIImage?
    
    init(initialID: UUID,
         entries: [GeneratedImage],
         imageStore: ImageStore,
         isPresented: Binding<Bool>,
         sourceFrame: CGRect,
         onIndexChanged: ((UUID) -> Void)?,
         columnsCount: Int,
         triggerDismiss: Binding<Bool>,
         isVisualHeroMode: Binding<Bool>,
         isDeleting: Bool,
         forceDarkMode: Binding<Bool>,
         starterImage: UIImage?, // Pass the image directly
         dragScale: Binding<CGFloat>,
         isFlightCompleteBinding: Binding<Bool>) {
        
        self.initialID = initialID
        self.entries = entries
        self.imageStore = imageStore
        self._isPresented = isPresented
        self.sourceFrame = sourceFrame
        self.onIndexChanged = onIndexChanged
        self.columnsCount = columnsCount
        self._triggerDismiss = triggerDismiss
        self._isVisualHeroMode = isVisualHeroMode
        self.isDeleting = isDeleting
        self._forceDarkMode = forceDarkMode
        self._dragScale = dragScale
        self._isFlightCompleteBinding = isFlightCompleteBinding
        
        if let entryIndex = entries.firstIndex(where: { $0.id == initialID }) {
            self._currentIndex = State(initialValue: entryIndex)
            self.starterImage = starterImage
        } else {
            self._currentIndex = State(initialValue: 0)
            self.starterImage = nil
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            
            // The .topLeading coordinate of the stack matches the (0,0) of the screen.
            // This allows us to use the sourceFrame.minX and minY directly as offsets.
            ZStack(alignment: .topLeading) {
                backdropLayer
                
                UIKitGalleryContainer(
                    entries: entries,
                    currentIndex: $currentIndex,
                    starterImage: starterImage,
                    imageStore: imageStore,
                    sourceFrame: sourceFrame,
                    columnCount: columnsCount,
                    isDeleting: isDeleting,
                    isVisualHeroMode: $isVisualHeroMode,
                    dragScale: $dragScale,
                    triggerDismiss: $triggerDismiss,
                    isFlightComplete: $isFlightComplete,
                    forceDarkMode: $forceDarkMode
                )
                .ignoresSafeArea() // It ensures the UIKit coordinate (0,0) is the absolute top-left of the glass.
                .frame(width: screenSize.width, height: screenSize.height)
            }
        }
        // Stretches to screen size if presented at the top level of the NavigationStack in parent view
        .ignoresSafeArea()
        
        // It ensures the user can't accidentally "grab" the image and start zooming or dragging it while
        // it's still flying out of the grid
        .allowsHitTesting(isFlightComplete)
        
        .onAppear(perform: handleAppear)
        .onChange(of: triggerDismiss) {
            // Prepare for reverse flight
            isFlightComplete = false
            dismiss()
        }
        .onChange(of: currentIndex) { _, newIndex in
            if entries.indices.contains(newIndex) {
                let entry = entries[newIndex]
                onIndexChanged?(entry.id)
            }
        }
    }
    
    var backdropLayer: some View {
        let opacity: CGFloat = 1.0 //0.55
        // Reduce opacity based on scale (1.0 scale = full opacity, 0.5 scale = 0 opacity)
        let interactiveOpacity = opacity * Double(max(0, (dragScale - 0.5) / 0.5))
        
        return Color(uiColor: .systemBackground)
            .opacity(animateIn ? interactiveOpacity : 0)
            .ignoresSafeArea()
    }
}

private extension FullSizeImageView {
    
    func handleAppear() {
        if forceDarkMode {
            forceDarkMode = false
        }
        
        // Brief delay to ensure geometry is ready
        DispatchQueue.main.async {
            guard sourceFrame != .zero else {
                animateIn = true
                return
            }
            
            // The reason we have nested async calls is usually to ensure that SwiftUI
            // has finished its initial layout (the "dirty" pass) so that sourceFrame
            // and the GeometryReader proxy are settled.
            
            DispatchQueue.main.async {
                // Match the spring timing to flip the switch
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    animateIn = true
                    isVisualHeroMode = true
                }
                
                // 🔑 Set flight complete after the spring settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    isFlightComplete = true
                    isFlightCompleteBinding = true
                }
            }
        }
    }
    
    func dismiss() {
        // 1. First, swap back to the static flyer so the spring can move it
        isFlightComplete = false
        isFlightCompleteBinding = false
        
        if forceDarkMode {
            forceDarkMode = false
        }
        
        // 2. Give SwiftUI a tiny moment (heartbeat) to render the static image
        // at its full size before we start the shrink animation.
        
        // We use TWO levels of async or a small delay.
        // Level 1: Ensure the state change propagated to UIKit.
        // Level 2: Ensure UIKit performed its internal layout/swap.
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                // Use a slightly stiffer spring for the "flight home"
                withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                    animateIn = false
                    isVisualHeroMode = false
                    // Also ensure background fades out
                    dragScale = 1.0
                }
            }
        }
        
        // 3. Final cleanup
        // We wait 0.45s (Spring Response 0.35s + 0.1s buffer) to nil out the selection.
        // Since the grid thumbnail's visibility is tied to 'selectedEntry', this
        // delay ensures the thumbnail stays hidden at 0.01 opacity until the Flyer
        // has physically landed and settled. Without this, the thumbnail would
        // "ghost" back into the grid while the Flyer is still moving home.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isPresented = false
        }
    }
}
