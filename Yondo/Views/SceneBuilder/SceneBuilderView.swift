//
//  SceneBuilderView.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.12.2025.
//

import SwiftUI
import UIKit

enum ScrollTarget: Hashable {
    case destination(SceneDestination.ID)
    case showMore
}

struct SceneBuilderView: View {
    let selfieImage: UIImage
    let onGenerate: (SceneConfig, UIImage) -> Void
    let onShowActiveGeneration: (UIImage) -> Void
    let onClose: () -> Void
    let onPop: () -> Void
    
    @ObservedObject var viewModel: SceneBuilderViewModel
    @ObservedObject var iapManager = IAPManager.shared
    
    @State var isDestinationsExpanded: Bool = true
    @State var showMoreDestinations = false
    @State private var showPurchaseModal = false
    @State private var isVisible = false
    @State var isAnimatingIn = false
    @State var activePhase: ScrollPhase = .idle
    @State var scrollDirection: CGFloat = 1.0 // 1 for Forward, -1 for Backward
//    @State private var suppressInitialAnimation = true // The Gatekeeper
    @State var selectionCount = 0
    
    enum LayoutConstants {
        static let horizontalPadding: CGFloat = 20
        static let headerToContentSpacing: CGFloat = 10
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isGenerateButtonPressed = false
    
    // Temporal state (preventing double-taps during the 0.3s Task)
    @State private var isGenerateButtonBusy = false
    
    init(viewModel: SceneBuilderViewModel,
         selfieImage: UIImage,
         onGenerate: @escaping (SceneConfig, UIImage) -> Void,
         onShowActiveGeneration: @escaping (UIImage) -> Void,
         onClose: @escaping () -> Void,
         onPop: @escaping () -> Void) {
        
        self.viewModel = viewModel
        self.selfieImage = selfieImage
        self.onGenerate = onGenerate
        self.onShowActiveGeneration = onShowActiveGeneration
        self.onClose = onClose
        self.onPop = onPop
        
//        self.position = ScrollPosition(id: viewModel.destination?.id)
    }
    
    private var isGenerateButtonEnabled: Bool {
        // Button is ONLY logically enabled if a destination is selected.
        // Assuming viewModel.destination is nil when "Show More" is the hero.
        viewModel.destination != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            mainScrollView
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay {
            VStack(spacing: 0) {
                Spacer()
                
                ZStack(alignment: .bottom) {
                    // The Blur Background with the "Hole" cut out
                    LiquidGlassBlurFade(isPressed: isGenerateButtonPressed || isGenerateButtonBusy)
                    
                    // The Physical Tray sitting in that hole
                    LiquidGlassTray(
                        isEnabled: isGenerateButtonEnabled,
                        isPressed: isGenerateButtonPressed || isGenerateButtonBusy,
                        cornerRadius: LiquidGlassTrayLayoutConstants.trayCornerRadius
                    ) {
                        generateButton()
                    }
                    .padding(.horizontal, LiquidGlassTrayLayoutConstants.trayPadding)
                    .padding(.bottom, LiquidGlassTrayLayoutConstants.trayPadding)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .opacity(isAnimatingIn ? 1 : 0)
            .offset(y: isAnimatingIn ? 0 : 150)
        }
        .toolbar {
            SceneBuilderToolbar(
                viewModel: viewModel,
                selfieImage: selfieImage,
                activeGenerationToken: viewModel.activeGenerationToken,
                onPop: onPop,
                onClose: onClose,
                onShowActiveGeneration: onShowActiveGeneration
            )
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isVisible = true
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25)) {
                isAnimatingIn = true
            }
        }
        .onDisappear {
            isVisible = false
            isAnimatingIn = false
        }
        .onChange(of: viewModel.activeGenerationToken) { oldToken, newToken in
            if oldToken != nil && newToken == nil
                && viewModel.isActive && !viewModel.isSyncing
                && isVisible && !showPurchaseModal {
                HapticManager.shared.success()
            }
        }
        .background(
            SwipeBackControl(enabled: true)
        )
    }
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView() {
            VStack(spacing: 0) {
                destinationsSection()
                
                VStack(spacing: 24) {
                    environmentSection()
                    moodSection()
                    lightingSection()
                    cameraSection()
                }
            }
            .padding(.top, 24)
            .padding(.bottom, LiquidGlassTrayLayoutConstants.trayHeight + 80)
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - View Builders
    
    private func generateImage() {
        let config = viewModel.buildConfig()
        let sameConfig = (config == viewModel.lastGenerationConfig) && (selfieImage === viewModel.lastGenerationSelfie)
        
        if !(sameConfig && viewModel.isActive) {
            HapticManager.shared.lightImpact()
            viewModel.cancelGeneration(force: true, userInitiated: false)
            viewModel.prepareForNewGeneration()
        }
        
        onGenerate(config, selfieImage)
    }
    
    private var captionMessage: String {
        // Premium destination locked
        if let destination = viewModel.destination,
           destination.isPremium && !iapManager.creditStore.premiumDestinationsUnlocked {
            return "Tap to unlock 🔒"
        }
        
        // Free credits
        if iapManager.creditStore.isRunningOnFreeCredits {
            if iapManager.creditStore.credits == 1 {
                return "1 free remaining 🎁"
            } else {
                return "\(iapManager.creditStore.credits) free remaining 🎁"
            }
        }
        
        // Paid credits
        if iapManager.creditStore.credits > 0 {
            if iapManager.creditStore.credits == 1 {
                return "1 remaining"
            } else {
                return "\(iapManager.creditStore.credits) remaining"
            }
        }
        
        // No credits
        return "Tap to purchase 🛍️"
    }
    
    private func handleGenerateTap() {
        guard !isGenerateButtonBusy else { return }
        isGenerateButtonBusy = true
        
        Task {
//            await iapManager.creditStore.resetAll()
            
            var canGenerate: Bool = iapManager.creditStore.credits > 0
            
            if let destination = viewModel.destination, destination.isPremium {
                canGenerate = canGenerate && iapManager.creditStore.premiumDestinationsUnlocked
            }
            
            if canGenerate {
                generateImage()
            } else {
                HapticManager.shared.lightImpact()
                iapManager.prepareForModalPresentation()
                showPurchaseModal = true
            }
            
            // Re-enable after short delay to prevent double-tap
            try? await Task.sleep(for: .seconds(0.3))
            
            isGenerateButtonBusy = false
        }
    }
    
    private func generateButton() -> some View {
        Button {
            handleGenerateTap()
        } label: {
            EmptyView() // The label is handled inside the Style now
        }
        .buttonStyle(LiquidGlassButtonStyle(
            captionMessage: captionMessage,
            isBusy: isGenerateButtonBusy,
            colorScheme: colorScheme,
            isDown: $isGenerateButtonPressed
        ))
        .disabled(!isGenerateButtonEnabled)
        .sheet(isPresented: $showPurchaseModal) {
            PurchaseModalView()
        }
    }
}
