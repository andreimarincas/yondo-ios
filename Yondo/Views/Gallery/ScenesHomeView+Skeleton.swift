//
//  ScenesHomeView+Extensions.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.01.2026.
//

import SwiftUI

extension ScenesHomeView {
    
    var emptyStateView: some View {
        ScrollView {
            ZStack {
                Spacer().containerRelativeFrame([.horizontal, .vertical])
                VStack(spacing: 0) {
                    Spacer().frame(height: dynamicHeaderHeight)
                    Spacer()
                    
                    emptyGalleryView
                    
                    Spacer().frame(height: 110)
                    Spacer()
                }
            }
        }
        .scrollDisabled(true)
        .ignoresSafeArea(.container, edges: .top)
        // This ensures the Spacers are always calculating based on the full screen
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: snapshottedImages.isEmpty)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isGridFullyRendered)
    }
    
    @ViewBuilder
    private var emptyGalleryView: some View {
        if isShowingEmptyGalleryView {
            EmptyGalleryView(onCreateTapped: { showCreateFlow = true })
                .frame(maxWidth: .infinity)
                .background(backgroundView)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 4)
                // This transition will now stay relative to the Spacers
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.92))    // Start smaller
                            .combined(with: .offset(y: 20)),        // Start lower for a "rising" feel
                        removal: .opacity
                            .combined(with: .scale(scale: 1.05))    // Grow slightly as it fades out
                    )
                )
        }
    }
    
    private var backgroundView: some View {
        ZStack {
            Rectangle()
                .fill(Color(UIColor.systemBackground))
            
            Rectangle()
                .fill(Theme.placeholderColor(colorScheme).opacity(Theme.gridSkeletonOpacity))
        }
        .mask(fadeGradient)
    }
    
    private var fadeGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0),    // fully transparent at top
                .init(color: .black, location: 0.1),    // fully visible after fade
                .init(color: .black, location: 0.9),    // fully visible till near bottom
                .init(color: .clear, location: 1.0)     // fade to transparent at bottom
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var skeletonFadeGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                // 1. The "Hidden" Zone: Keep the very top clear so it doesn't
                // interfere with the Status Bar/Back buttons.
                .init(color: .clear, location: 0.0),
                
                // 2. The "Peek" Zone: Let about 20% of the content's alpha
                // through right where the title sits.
                .init(color: .black.opacity(0.2), location: 0.08),
                
                // 3. The "Solid" Zone: Full visibility starts just as we
                // clear the Large Title area.
                .init(color: .black, location: 0.18),
                
                // 4. The Bottom Fade: Standard clean exit.
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var skeletonGridView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: dynamicHeaderHeight)
                gridContent
                    .padding(.horizontal, 4)
                    .opacity(Theme.gridSkeletonOpacity)
                    .allowsHitTesting(false)
                    .clipped()
            }
        }
        .scrollDisabled(true)
        .ignoresSafeArea(.container, edges: .top)
        .mask(skeletonFadeGradient)
    }
    
    @ViewBuilder
    private var gridContent: some View {
        VStack(spacing: 4) {
            // Generates enough rows to fill a standard screen
            ForEach(0..<8, id: \.self) { _ in
                gridRow
            }
        }
    }
    
    @ViewBuilder
    private var gridRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonGridPlaceholder()
            }
        }
    }
}

private struct Theme {
    static let gridPlaceholderOpacity: Double = 0.08
    static let gridSkeletonOpacity: Double = 0.7
    
    static func placeholderColor(_ colorScheme: ColorScheme) -> Color {
        let color: Color
        let opacity: Double
        
        if colorScheme == .dark {
            color = Color.white
            opacity = Theme.gridPlaceholderOpacity
        } else {
            color = Color.black
            opacity = Theme.gridPlaceholderOpacity
        }
        
        return color.opacity(opacity)
    }
}

private struct SkeletonGridPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Theme.placeholderColor(colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .cornerRadius(4)
    }
}

struct GridPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Theme.placeholderColor(colorScheme)
            
            // The "Liquid" Background
            RoundedRectangle(cornerRadius: 4)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
        }
        .aspectRatio(1, contentMode: .fill)
    }
}
