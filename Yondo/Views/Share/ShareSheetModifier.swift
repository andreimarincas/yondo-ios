//
//  ShareSheetModifier.swift
//  Yondo
//
//  Created by Andrei Marincas on 05.02.2026.
//

import SwiftUI

private let smallHeight: CGFloat = 150

struct ShareSheetModifier: ViewModifier {
    @ObservedObject var provider: ImageShareProvider
    
    @State private var activeDetent: PresentationDetent = .height(smallHeight)
    @State private var isReady: Bool = false
    
    @State private var displayedRequestID: UUID?
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $provider.showsSheet, onDismiss: {
                provider.cancel(specificID: displayedRequestID)
            }) {
                ZStack {
                    ShareSheetHost(provider: provider) {
                        handleIsReady()
                    }
                }
                .onAppear {
                    displayedRequestID = provider.currentRequestID
                }
                .presentationDetents(availableDetents, selection: $activeDetent)
                .presentationDragIndicator(showsDragIndicator ? .visible : .hidden)
                .interactiveDismissDisabled(!isReady)
                .animation(.easeInOut(duration: 0.2), value: isReady)
            }
            .onReceive(provider.resetStream) { _ in
                resetInternalState()
            }
    }
    
    private func resetInternalState() {
        isReady = false
        activeDetent = .height(smallHeight)
    }
    
    private var availableDetents: Set<PresentationDetent> {
        // If isReady is true, the small 150pt detent is removed from the UI entirely
        isReady ? [.medium, .large] : [.height(smallHeight), .medium, .large]
    }
    
    private var showsDragIndicator: Bool {
        activeDetent == .medium || activeDetent == .large
    }
    
    private func handleIsReady() {
        // Only expand if we are actually still showing the sheet
        guard provider.showsSheet else { return }
        
        // 1. Start the physical slide to .medium.
        // At this moment, isReady is still FALSE, so the 'smallHeight'
        // still exists in the set. The animation is safe.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeDetent = .medium
        }
        
        // 2. Wait for the slide to "land" before removing the small detent.
        // 0.35s-0.4s is the sweet spot for native sheet feel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Now that we've arrived at .medium, it is safe to remove
            // the 150pt detent and update available detents.
            withAnimation(.easeInOut(duration: 0.2)) {
                isReady = true
            }
        }
    }
}

extension View {
    func shareSheet(provider: ImageShareProvider) -> some View {
        self.modifier(ShareSheetModifier(provider: provider))
    }
}
