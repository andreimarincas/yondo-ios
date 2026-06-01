//
//  SceneViewToolbar.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.03.2026.
//

import SwiftUI

struct SceneViewToolbar: ToolbarContent {
    @ObservedObject var viewModel: SceneBuilderViewModel
    @ObservedObject var shareProvider: ImageShareProvider
    
    @Binding var showRegenerateConfirmation: Bool
    @Binding var showPurchaseModal: Bool
    @Binding var showShareSheet: Bool
    
    let onClose: () -> Void
    let handleRegenerateTap: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject var debugManager = DebugManager.shared
    @State var showDebugMenu = false
    
    var body: some ToolbarContent {
        // Top left
        backButton
        
        // Top right
#if DEBUG
        debugItem
#endif
//        dummySpinnerButton
//        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        closeButton
        
        // Bottom toolbar item
        if showsBottomItems {
            ToolbarItemGroup(placement: .bottomBar) {
                regenerateButton
                Spacer()
                shareButton
            }
        }
    }
    
    private var showsBottomItems: Bool {
        !viewModel.isGenerating && viewModel.generatedImage != nil
    }
    
    @ToolbarContentBuilder
    private var backButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                viewModel.cancelGeneration()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .yondoToolbarStyle(.dismiss)
            }
            .tint(.primary)
        }
    }
    
    @ToolbarContentBuilder
    private var dummySpinnerButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // No implementation needed
            } label: {
                ZStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .id("spinner_unique_id")
            .buttonStyle(.plain)
            .transition(.identity)
        }
        .sharedBackgroundVisibility(.hidden)
    }
    
    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.cancelGeneration()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .yondoToolbarStyle(.dismiss)
            }
            .tint(.primary)
        }
    }
    
    @ViewBuilder
    private var regenerateButton: some View {
        Button {
            handleRegenerateTap()
        } label: {
            ZStack {
                // 1. The background circle (The "container")
                Image(systemName: "circle.fill")
                    .font(.system(size: 30))
                
                // 2. The arrow on top (The "icon")
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: colorScheme == .light ? .semibold : .heavy, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }
            .padding(.horizontal, -10)
            .padding(.vertical, -5)
        }
        .tint(colorScheme == .light ? Color.yondoInteractive : .yondoBrand)
    }
    
    @ViewBuilder
    private var shareButton: some View {
        Button {
            guard let image = viewModel.generatedImage, shareProvider.canShare else { return }
            HapticManager.shared.lightImpact()
            shareProvider.share(.direct(full: image, thumb: image))
        } label: {
            ZStack {
                Image(systemName: "square.and.arrow.up")
                    .offset(y: -1.5)
                    .opacity(shareProvider.canShare ? 1 : 0)
                
                if !shareProvider.canShare {
                    YondoSpinner(size: .small, style: colorScheme == .dark ? .subtle : .system)
                }
            }
            .yondoToolbarStyle(.standard)
        }
        .tint(.primary)
//        .tint(colorScheme == .light ? .yondoInteractive : .yondoBrand)
        .disabled(!shareProvider.canShare)
        .animation(.easeInOut, value: shareProvider.canShare)
    }
}
