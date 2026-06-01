//
//  SceneView.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.12.2025.
//

import SwiftUI
import Photos
import UIKit

struct SceneView: View {
    @ObservedObject private var viewModel: SceneBuilderViewModel
    
    let config: SceneConfig
    let selfieImage: UIImage
    let onClose: () -> Void
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var isSaving = false
    @State private var showShareSheet = false
    
    // Temporal state (preventing double-taps during the 0.3s Task)
    @State private var isRegenerateButtonBusy = false
    
    @State private var showRegenerateConfirmation = false
    @State private var showPurchaseModal = false
    @State private var cloudAnimate = false
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var isAnimatingColor = false
    
    private let buttonMinWidth: CGFloat? = 80
    
    @StateObject var shareProvider = ImageShareProvider(imageStore: ImageStore.shared)
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    
    init(viewModel: SceneBuilderViewModel, config: SceneConfig, selfieImage: UIImage, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.config = config
        self.selfieImage = selfieImage
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack {
            Group {
                if viewModel.generatedImage != nil, !viewModel.isGenerating {
                    imageView
                        .transition(.opacity.combined(with: .scale(scale: 1.05))) // Slightly larger "zoom in" feel
                }
            }
            .zIndex(0)
            
            Group {
                if viewModel.isGenerating {
                    loadingViewWithCancel
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if let error = viewModel.generationError, viewModel.generatedImage == nil {
                    errorViewWithRetry
//                        .id(error.errorDescription)
                        .id("\(error.errorDescription ?? "")-\(isErrorResolved)")
                        // Delay the appearance by 0.2s for a smoother "handoff"
//                        .transition(.opacity.animation(.easeInOut(duration: 0.4).delay(0.2)))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center) // Keep the group centered
            .offset(y: -60)
            .zIndex(1)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: viewModel.isGenerating)
        .animation(.easeInOut(duration: 0.4), value: viewModel.generatedImage)
        .animation(.easeInOut(duration: 0.4), value: viewModel.generationError)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isErrorResolved)
        .animation(.easeInOut(duration: 0.3), value: isPaywallError)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbar }
        .shareSheet(provider: shareProvider)
        .sheet(isPresented: $showPurchaseModal) {
            PurchaseModalView()
        }
        .onAppear {
            viewModel.isSceneViewVisible = true
            let sameConfig = (config == viewModel.lastGenerationConfig) && (selfieImage === viewModel.lastGenerationSelfie)
            if !(sameConfig && viewModel.isActive) {
                viewModel.generateScene(selfie: selfieImage, config: config)
            }
        }
        .onDisappear {
            viewModel.isSceneViewVisible = false
            viewModel.cancelGeneration()
            viewModel.teardownWaitingState()
        }
        .alert("Recreate Yondo?", isPresented: $showRegenerateConfirmation) {
            Button("Cancel", role: .cancel) { }
            
            Button("Recreate") {
                handleRecreateAlertAction()
            }
        } message: {
            Text(boldYondo("This will create a new Yondo and consume one credit. Your current Yondo will remain in your gallery."))
        }
        .alert("Couldn’t save to gallery", isPresented: $viewModel.saveFailedButDeliveredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(boldYondo("This rarely happens. You can still save your Yondo to Photos or share it."))
                .font(.system(.callout, design: .rounded))
        }
        .onChange(of: viewModel.generatedImage) { _, newImage in
            guard isPresented else { return }
            if newImage != nil {
                HapticManager.shared.success()
            }
        }
        .onChange(of: viewModel.generationError) { oldError, newError in
            guard isPresented else { return }
            
            // 1. Always check for Paywall first.
            // If they are out of credits/locks, we show the modal and STOP.
            // (Returning here ensures we don't trigger a failure haptic when the modal slides up).
            if isPaywallError {
                IAPManager.shared.prepareForModalPresentation()
                showPurchaseModal = true
                return
            }
            
            // 2. The Healing Success
            let isInsufficient = newError?.isInsufficient ?? false
            let wasSyncing = oldError?.isSyncing ?? false
            
            if wasSyncing && isInsufficient && isErrorResolved {
                HapticManager.shared.success()
                return
            }
            
            // 3. True Failures (Network Error, AI Busy, etc.)
            if let newError, !newError.isSyncing {
                HapticManager.shared.failure()
            }
        }
        .background(
            SwipeBackControl(enabled: true)
        )
    }
    
    private var toolbar: some ToolbarContent {
        SceneViewToolbar(
            viewModel: viewModel,
            shareProvider: shareProvider,
            showRegenerateConfirmation: $showRegenerateConfirmation,
            showPurchaseModal: $showPurchaseModal,
            showShareSheet: $showShareSheet,
            onClose: onClose,
            handleRegenerateTap: handleRegenerateTap
        )
    }
    
    func handleRegenerateTap() {
        guard !isRegenerateButtonBusy else { return }
        isRegenerateButtonBusy = true
        
        Task {
            let iapManager = IAPManager.shared
            var canGenerate: Bool = iapManager.creditStore.credits > 0
            
            if let destination = viewModel.destination, destination.isPremium {
                canGenerate = canGenerate && iapManager.creditStore.premiumDestinationsUnlocked
            }
            
            if canGenerate {
                showRegenerateConfirmation = true
            } else {
                HapticManager.shared.lightImpact()
                iapManager.prepareForModalPresentation()
                showPurchaseModal = true
            }
            
            // Re-enable after short delay to prevent double-tap
            try? await Task.sleep(for: .seconds(0.3))
            
            isRegenerateButtonBusy = false
        }
    }
    
    private func handleRecreateAlertAction() {
        let iapManager = IAPManager.shared
        var canGenerate: Bool = iapManager.creditStore.credits > 0
        
        if let destination = viewModel.destination, destination.isPremium {
            canGenerate = canGenerate && iapManager.creditStore.premiumDestinationsUnlocked
        }
        
        HapticManager.shared.lightImpact()
        
        if canGenerate {
            viewModel.cancelGeneration(force: true, userInitiated: false)
            viewModel.prepareForNewGeneration()
            viewModel.generateScene(selfie: selfieImage, config: config)
        } else {
            iapManager.prepareForModalPresentation()
            showPurchaseModal = true
        }
    }
    
    @ViewBuilder
    private var imageView: some View {
        if let image = viewModel.generatedImage {
            ZoomableImageView(image: image, backgroundColor: .clear)
                .ignoresSafeArea()
                .edgesIgnoringSafeArea(.all) // Extra insurance for older SwiftUI versions
        }
    }
    
    private var loadingViewWithCancel: some View {
        VStack(spacing: 0) {
            generationProgressView
            cancelButton
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300, alignment: .top)
    }
    
    private var errorViewWithRetry: some View {
        VStack(spacing: 0) {
            errorView
            retryButton
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300, alignment: .top)
    }
    
    private var generationProgressView: some View {
        VStack(spacing: 16) {
            ZStack {
                YondoSpinner(size: .large, style: .brand)
            }
            .frame(height: 60)
            .padding(.bottom, 8)
            
            ShimmeringText(message: viewModel.currentMessage, colorScheme: colorScheme)
                .id(viewModel.currentMessage) // Each ID gets its own ShimmeringText instance
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.easeInOut(duration: 0.6)),
                        removal: .opacity.animation(.easeInOut(duration: 0.4))
                    )
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.currentMessage)
            
            Text(boldYondo("Your Yondo will appear in your gallery once ready."))
                .font(.system(.subheadline, design: .rounded)) // Rounded to match, but smaller/thinner
                .foregroundColor(.yondoSecondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .padding(.vertical, 24)
        .onAppear { startShimmer() }
        .onChange(of: viewModel.currentMessage) { _, _ in startShimmer() }
    }
    
    private func startShimmer() {
        // Only start if it's not already animating/at start
        guard shimmerOffset == -1.0 else { return }
        
        // Duration 2.5s is fast enough to feel active, but slow enough to show the color.
        // By using 0.0 to 1.0 with a 3x wide mask, the "pause" at normal color is minimal.
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.0
        }
    }
    
    @ViewBuilder
    private var cancelButton: some View {
        
        let buttonTitle: String = {
            if viewModel.cancelEnabled {
                return "Cancel \(viewModel.cancelCountdown)s"
            } else {
                return "Processing"
            }
        }()
        
        LiquidGlassSecondaryButton(
            title: buttonTitle,
            isEnabled: viewModel.cancelEnabled,
//            isProcessing: !viewModel.cancelEnabled,
            isMonospaced: true,
            minWidth: buttonMinWidth,
            action: {
                HapticManager.shared.lightImpact()
                viewModel.cancelGeneration()
                dismiss()
            }
        )
        .id(viewModel.cancelEnabled)
//        .transition(.opacity)
    }
    
    @ViewBuilder
    private var errorView: some View {
        VStack(spacing: 16) {
            ZStack {
                errorIcon
            }
            .frame(height: 60)
            .padding(.bottom, 8)
            
//            ZStack {
                Text(errorHeader)
                    .id(errorHeader) // Triggers transition when text changes
//                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .foregroundColor(colorScheme == .light ? .yondoMidnight : .yondoWhite)
//            }
//            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: errorHeader)
            
            let errorMessage = isErrorResolved
                ? "Everything is synced! You're ready to generate."
                : (viewModel.generationError?.errorDescription ?? "")
            
//            ZStack {
                Text(errorMessage)
                    .id(errorMessage) // Triggers transition
//                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.yondoSecondaryText(for: colorScheme))
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
//            }
//            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: errorMessage)
        }
        .padding(.vertical, 24)
    }
    
    @ViewBuilder
    private var errorIcon: some View {
        Group {
            if errorSymbol == "cloud.drizzle.fill" {
                Image(systemName: errorSymbol)
                    .font(.system(size: 44)) // Slightly larger because it's a "thinner" symbol
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        colorScheme == .light
                            ? Color.yondoMidnight.opacity(0.2) // Much lighter cloud
                            : Color.yondoWhite.opacity(0.4),   // Keep the ghostly dark mode cloud
                        Color.yondoAccent // The Drizzle (Electric Cyan)
                    )
                    .shadow(
                        color: .yondoAccent.opacity(colorScheme == .light ? (cloudAnimate ? 0.2 : 0.1) : (cloudAnimate ? 0.4 : 0.2)),
                        radius: cloudAnimate ? 12 : 8
                    )
                    // Breathing effect: subtly scales and fades
                    .scaleEffect(cloudAnimate ? 1.05 : 0.95)
                    .opacity(cloudAnimate ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                        value: cloudAnimate
                    )
            } else {
                Image(systemName: errorSymbol)
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        colorScheme == .light ? Color.yondoMidnight.opacity(0.2) : Color.yondoWhite.opacity(0.4),
                        Color.yondoAccent
                    )
                    // Explicitly change the ID so the view is recreated when the symbol changes
                    .id(errorSymbol)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: errorSymbol)
                    // Add rotation animation only for the sync icon
                    .rotationEffect(.degrees(errorSymbol == "arrow.triangle.2.circlepath" ? (cloudAnimate ? 360 : 0) : 0))
                    // Use nil for the non-syncing icons to ensure no animation is applied
                    .animation(
                        errorSymbol == "arrow.triangle.2.circlepath"
                            ? .linear(duration: 2).repeatForever(autoreverses: false)
                            : nil, // Use nil instead of .default to stop persistence
                        value: cloudAnimate
                    )
            }
        }
        .onAppear {
            // Use DispatchQueue to ensure the view is fully
            // in the hierarchy before starting the animation.
            DispatchQueue.main.async {
                cloudAnimate = true
            }
        }
        .onDisappear {
            // Reset state so it can restart next time
            cloudAnimate = false
        }
    }
    
    @ViewBuilder
    private var retryButton: some View {
        
        // Determine the button title based on state
        let buttonTitle: String = {
            if isPaywallError { return "View Options" }
            if viewModel.isSyncing { return "Syncing" }
            if isErrorResolved { return "Let's go!" }
            return "Try Again"
        }()
        
        LiquidGlassSecondaryButton(
            title: buttonTitle,
            isEnabled: !viewModel.isSyncing,
//            isProcessing: viewModel.isSyncing,
            isMonospaced: false,
            minWidth: buttonMinWidth,
            action: {
                HapticManager.shared.lightImpact()
                
                if isPaywallError {
                    IAPManager.shared.prepareForModalPresentation()
                    showPurchaseModal = true
                } else {
                    // If it's a sync error, this will simply re-trigger the generation
                    // which will check the backend again.
                    viewModel.cancelGeneration(force: true, userInitiated: false)
                    viewModel.prepareForNewGeneration()
                    viewModel.generateScene(selfie: selfieImage, config: config)
                }
            }
        )
        .id("retryButton") // Gives SwiftUI a stable anchor
//        .transition(.opacity)
    }
}

private extension SceneView {
    // MARK: - Error Handling Logic
    
    var isPaywallError: Bool {
        guard let error = viewModel.generationError else { return false }
        let store = IAPManager.shared.creditStore
        switch error {
        case .requiresPremiumUnlock:
            return store.premiumDestinationsUnlocked == false
        case .insufficientCredits:
            // Only treat as a paywall error if they STILL have 0 credits.
            // If they just bought some, we want to show the Retry button instead.
            return store.credits == 0
        default:
            return false
        }
    }
    
    var errorHeader: String {
        guard let error = viewModel.generationError else { return "A bit of a hiccup" }
        if isErrorResolved { return "Ready to Generate" }
        
//        if case .unknown(let underlying) = error, let aiError = underlying as? AIError {
//            switch aiError {
//            case .securityCheckFailed: return "Security Error"
//            case .tooManyRequests: return "System Busy"
//            case .timeout: return "Connection Timeout"
//            case .unknown: return "A bit of a hiccup"
//            }
//        }
        
        switch error {
        case .syncingPremiumUnlock, .syncingCredits:
            return "Syncing Store"
        case .requiresPremiumUnlock:
            return "Premium Destination"
        case .insufficientCredits:
            return "Top-up Required"
//        case .networkConnectionLost:
//            return "Connection Lost"
//        case .aiBusy:
//            return "AI Engine Busy"
        default:
            return "A bit of a hiccup"
        }
    }

    var errorSymbol: String {
        guard let error = viewModel.generationError else { return "cloud.drizzle.fill" }
        if isErrorResolved { return "sparkles" }
        
        switch error {
        case .syncingPremiumUnlock, .syncingCredits:
            return "arrow.triangle.2.circlepath" // Sync icon
        case .requiresPremiumUnlock:
            return "lock.fill"
        case .insufficientCredits:
            return "cart.fill"
//        case .networkConnectionLost:
//            return "wifi.exclamationmark"
        default:
            return "cloud.drizzle.fill"
        }
    }
    
    var isErrorResolved: Bool {
        guard let error = viewModel.generationError else { return false }
        let store = IAPManager.shared.creditStore
        
        switch error {
        case .insufficientCredits:
            // ✨ This is the "Decision Room".
            // If we have credits now, show the sparkles.
            return store.credits > 0
            
        case .requiresPremiumUnlock(_):
            // ✨ If the user unlocked it while the error was showing, show sparkles.
            return store.premiumDestinationsUnlocked
            
        case .syncingCredits, .syncingPremiumUnlock:
            // 🛑 The "Waiting Room".
            // Force the UI to stay on "Finalizing Purchase" / Sync icon.
            // We only leave this state when the ViewModel timeout or
            // a background sync changes the 'generationError' itself.
            return false
            
        default:
            return false // Keeps the "Syncing" UI visible until the store actually updates
        }
    }
}
