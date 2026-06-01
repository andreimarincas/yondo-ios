//
//  SceneBuilderToolbar.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

struct SceneBuilderToolbar: ToolbarContent {
    @ObservedObject var viewModel: SceneBuilderViewModel
    
    let selfieImage: UIImage
    let activeGenerationToken: GenerationToken?
    @Environment(\.colorScheme) var colorScheme
    
    let onPop: () -> Void
    let onClose: () -> Void
    let onShowActiveGeneration: (UIImage) -> Void
    
    @State private var showSelfiePopover: Bool = false
    @State private var isAnimatingPulse = false
    
    @StateObject var debugManager = DebugManager.shared
    @State var showDebugMenu = false
    
    var body: some ToolbarContent {
        // Leading Items
        backButton
        ToolbarSpacer(.fixed, placement: .topBarLeading)
        selfieProfileButton
        
        titleItem
        
        // Trailing Items
#if DEBUG
        debugItem
#endif
        activeGenerationProgress
        closeButton
    }
}

private extension SceneBuilderToolbar {
    @ToolbarContentBuilder
    var backButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onPop) {
                Image(systemName: "chevron.left")
                    .yondoToolbarStyle(.dismiss)
            }
            .tint(.primary)
        }
    }
    
    @ToolbarContentBuilder
    var selfieProfileButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSelfiePopover.toggle()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    // Keep the label clean - just the image
                    Image(uiImage: selfieImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    //                    .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                    // Use a dynamic color for the stroke to stay visible in both modes
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                        .padding(.horizontal, -11)
                        .padding(.vertical, -6)
                    
//                    statusDot
////                        .padding(.horizontal, -11)
////                        .padding(.vertical, -6)
//                        //.offset(x: -2, y: -2)
//                        .offset(x: 11, y: 6)
                }
            }
            .buttonStyle(.glass)
            .frame(width: 36, height: 36)
//            .frame(maxWidth: 38, maxHeight: 38)
//            .padding(-10)
            .clipShape(Circle()) // This clips the glass background
            // --- ADD THE OVERLAY AFTER THE CLIP ---
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    // Outer Pulse (The "Alive" part)
//                    Circle()
//                        .fill(Color.yondoSuccess)
//                        .frame(width: 6, height: 6)
//                        .scaleEffect(isAnimatingPulse ? 1.5 : 1.0)
//                        .opacity(isAnimatingPulse ? 0 : 0.5)
                    
//                    Circle()
//                        .frame(width: 8, height: 8)
//                        .glassEffect()
                    
                    // Solid Center
                    Circle()
                        .fill(Color.yondoSuccess)
                        .frame(width: 8, height: 8)
                        // CRITICAL: Ensure the stroke color is explicitly opaque
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .light ? Color(white: 0.85) : Color(white: 0.4), lineWidth: 1.0)
                        )
                }
                .drawingGroup()
                .clipShape(Circle())
                .offset(x: -2.5, y: -2.5) // Nudge it to sit perfectly on the rim
            }
            .transition(.scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    isAnimatingPulse = true
                }
            }
            .popover(isPresented: $showSelfiePopover, arrowEdge: .top) {
                SelfiePopoverView(image: selfieImage)
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
    
    @ToolbarContentBuilder
    var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(viewModel.activeGenerationToken != nil ? "Processing…" : "New Yondo")
                .font(.system(.headline, design: .rounded).bold())
                .foregroundColor(.primary)
        }
    }
    
    @ToolbarContentBuilder
    var activeGenerationProgress: some ToolbarContent {
        if viewModel.activeGenerationToken != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onShowActiveGeneration(viewModel.lastGenerationSelfie ?? selfieImage)
                } label: {
                    ZStack {
                        YondoSpinner(size: .small, style: colorScheme == .dark ? .subtle : .system)
                            .frame(width: 44, height: 44)
                    }
                    .frame(width: 44, height: 44)
                    .compositingGroup()
                    .contentShape(Rectangle())
                }
                .id("spinner_unique_id")
                .buttonStyle(.plain)
                .opacity(activeGenerationToken != nil ? 1 : 0)
                .transition(.scale.combined(with: .opacity))
            }
            .sharedBackgroundVisibility(.hidden)
            
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
    }
    
    @ToolbarContentBuilder
    var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .close, action: onClose) {
                Image(systemName: "xmark")
                    .yondoToolbarStyle(.dismiss)
            }
            .tint(.primary)
        }
    }
}
