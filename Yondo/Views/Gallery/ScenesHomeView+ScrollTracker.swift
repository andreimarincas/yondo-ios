//
//  ScenesHomeView+ScrollTracker.swift
//  Yondo
//
//  Created by Andrei Marincas on 09.02.2026.
//

import SwiftUI

extension ScenesHomeView {
    
    @ViewBuilder
    func scrollTracker() -> some View {
        GeometryReader { geo in
            let globalY = geo.frame(in: .global).minY
            
            Color.clear
                .onChange(of: globalY) { _, newValue in
                    guard showsGrid else {
                        if self.scrollOffset != 0 {
                            self.scrollOffset = 0
                            updateToolbarScheme()
                        }
                        return
                    }
                    
                    // We clamp to 0 to ignore rubber-banding (pulling down)
                    let clampedOffset = min(0, newValue)
                    
                    // Noise Filter: Ignore sub-pixel floating point jitter
                    let finalOffset = abs(clampedOffset) < 0.5 ? 0 : clampedOffset
                    
                    if self.scrollOffset != finalOffset {
                        self.scrollOffset = finalOffset
                        updateToolbarScheme()
                    }
                }
        }
        .frame(height: 0)
    }
    
    /// Decisions based on the current scroll position
    private func updateToolbarScheme() {
        // 🌓 SYNC POINT: We check < 0 because 'normalized' only drops below 0
        // after crossing the 8pt physical threshold.
        let currentlyScrolled = self.normalizedScrollOffset < 0
        
        // Only trigger an animation block if the state is actually flipping
        if self.toolbarIsDark != currentlyScrolled {
            if currentlyScrolled {
                HapticManager.shared.softImpact(intensity: 0.5)
            }
            
            // Wrap state updates to avoid stutter
            withAnimation(.easeInOut(duration: 0.12)) {
                self.toolbarIsDark = currentlyScrolled
            }
        }
    }
}
