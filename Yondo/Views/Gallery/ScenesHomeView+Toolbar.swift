//
//  ScenesHomeView+Toolbar.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.01.2026.
//

import SwiftUI

extension ScenesHomeView {
    
    @ToolbarContentBuilder
    var homeToolbarItems: some ToolbarContent {
        smallTitleItem
        bottomBarItems
        dismissItem
    }
    
    @ToolbarContentBuilder
    private var smallTitleItem: some ToolbarContent {
        // Having the smallTitleItem on the top toolbar creates a blur effect that affects the top row,
        // even then smallTitleItem opacity is 0, that's why we add it only when user starts scrolling up,
        // when the navigation bar blur effect is needed for the thumbnails underneath.
        if !isVisualHeroMode && scrollOffset < 0 {
            ToolbarItem(placement: .principal) {
                Text("My Yondos")
                    .id("smallTitle")
                    .font(.system(.headline, design: .rounded).bold())
                    .tracking(-0.2)
                    // 🛑 NEVER COLOR-MORPH: This title is only visible when
                    // the header is 'Scrolled' (dark backdrop). Keep it white
                    // regardless of ColorScheme to ensure legibility.
                    .foregroundColor(.white)
                    // 💡 THE OVERLAY: Subtler offset for smaller text
                    .overlay(alignment: .leading) {
                        if colorScheme == .light && !toolbarIsDark {
                            Text("My Yondos")
                                .font(.system(.headline, design: .rounded).bold())
                                .tracking(-0.2)
                                // 🛑 Same as the white color on the base text. See the comment above.
                                .foregroundColor(.white)
                                .offset(x: 0.25) // Subtle "thickening" shift
                        }
                    }
                    .opacity(smallTitleOpacity)
                    .blur(radius: smallTitleBlur)
                    // 1. The Dynamic Scale
                    .scaleEffect(0.92 + (0.08 * smallTitleOpacity))
                    // 2. The Docking Animation
                    // This spring has a high 'stiffness' for that premium Apple feel
                    // 1. Physical Growth Spring
                    .animation(
                        .interpolatingSpring(stiffness: 120, damping: 14),
                        value: smallTitleOpacity > 0.5
                    )
                    // 2. Smooth Fade Transition
                    .animation(.easeInOut(duration: 0.2), value: smallTitleOpacity)
                    // 3. The Climb: Starts as soon as opacity > 0
                    // We use 5pt for a slightly more noticeable "rise"
                    .offset(y: smallTitleOpacity > 0 ? 0 : 5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: smallTitleOpacity > 0)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var bottomBarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if isVisualHeroMode {
                heroModeBottomItems
            } else if !snapshottedImages.isEmpty {
                createYondoButton
            }
        }
    }

    @ViewBuilder
    private var heroModeBottomItems: some View {
        if !isDragging {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .yondoToolbarStyle(.standardSmall)
            }
            .tint(colorScheme == .light ? .yondoOrangeDeep : .yondoOrange)
            .allowsHitTesting(isInteractionEnabled)
            
            Spacer()
            
            Button {
                guard let selectedEntry, shareProvider.canShare else { return }
                HapticManager.shared.lightImpact()
                shareProvider.share(.entry(selectedEntry))
            } label: {
                ZStack {
                    Image(systemName: "square.and.arrow.up")
                        .offset(y: -1.5)
                        .opacity(shareProvider.canShare ? 1 : 0)
                    
                    if !shareProvider.canShare {
                        YondoSpinner(size: .small, style: .brand)
                    }
                }
                .yondoToolbarStyle(.standard)
            }
            .tint(colorScheme == .light ? .yondoInteractive : .yondoBrand)
            .allowsHitTesting(isInteractionEnabled)
            .disabled(!shareProvider.canShare)
            .animation(.easeInOut, value: shareProvider.canShare)
        }
    }
    
    @ViewBuilder
    private var createYondoButton: some View {
        Spacer()
        
        Button(action: {
            HapticManager.shared.mediumImpact()
            showCreateFlow = true
        }) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .yondoToolbarStyle(.label, weight: .black)
                
                Text("Create New Yondo")
                    .yondoToolbarStyle(.label)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .tint(.primary)
        .allowsHitTesting(isInteractionEnabled)
        
        Spacer()
    }

    @ToolbarContentBuilder
    private var dismissItem: some ToolbarContent {
        if isVisualHeroMode && !isDragging {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) {
                    triggerDismiss.toggle()
                } label: {
                    Image(systemName: "xmark")
                        .yondoToolbarStyle(.dismiss)
                }
                .tint(.primary) // allows vibrancy when pressed
                .allowsHitTesting(isInteractionEnabled)
            }
        }
    }
}

extension ScenesHomeView {
    var preferredToolbarScheme: ColorScheme {
        if isVisualHeroMode {
            return (colorScheme == .dark || forceDarkMode) ? .dark : .light
        }
        return (colorScheme == .dark || toolbarIsDark) ? .dark : .light
    }
}

private extension ScenesHomeView {
    var isInteractionEnabled: Bool {
        if selectedEntry != nil {
            return isFullSizeSettled && !triggerDismiss
        }
        return true
    }
    
    var isDragging: Bool {
        currentDragScale != 1.0
    }
    
    var smallTitleBlur: CGFloat {
        let upwardScroll = max(0, -normalizedScrollOffset)
        
        // NEW: Clears up over 20pt.
        // Math: Starts at 8 radius, reaches 0 at 20pt scroll
        return max(8 - (upwardScroll / 20 * 8), 0)
    }
    
    var smallTitleOpacity: CGFloat {
        let upwardScroll = max(0, -normalizedScrollOffset)
        
        // NEW: Matches the blur speed. Fully opaque at 20pt.
        // Math: Reaches 1.0 at 20pt scroll
        return min(upwardScroll / 20, 1.0)
    }
}
