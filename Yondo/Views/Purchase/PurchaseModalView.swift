//
//  PurchaseModalView.swift
//  Yondo
//
//  Created by Andrei Marincas on 31.12.2025.
//

import SwiftUI
import StoreKit

struct StoreAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct PurchaseModalView: View {
    @ObservedObject var iapManager = IAPManager.shared
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State var isRestoring = false
    @State var showSuccess = false
    @State var activeAlert: StoreAlert?
    @State private var pendingConnectionRecovery = false
    @State var isDismissing = false
    @State var successfulProductID: String?
    @State var isProcessing = false
    @State var hasAppeared = false
    @State var animateIcon = false
    @State var displayedCredits: Int = 0
    
    @State private var refreshTask: Task<Void, Never>?
    
    @Namespace var glassTransitionSpace
    
    var isInteractionDisabled: Bool {
        isProcessing ||
        isRestoring ||
        pendingConnectionRecovery ||
        iapManager.purchasingProductID != nil ||
        successfulProductID != nil ||
        iapManager.creditStore.isBusy ||
        iapManager.loadingState == .loading ||
        iapManager.loadingState == .idle
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            NavigationStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        titleSection
                            .opacity(hasAppeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.5), value: hasAppeared)
                        
                        contentView
                    }
                    .padding(.bottom, 16)
                    .allowsHitTesting(!isInteractionDisabled)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .bottomBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .yondoToolbarStyle(.standardSmall)
                    }
                    titleItem
                    
                    ToolbarItemGroup(placement: .bottomBar) {
                        // We use Color.clear as a placeholder to trigger the system's
                        // bottom bar glass material without adding any visible UI elements.
                        Color.clear
                    }
                    // .toolbarBackground(.hidden) would kill the glass blur entirely.
                    // .sharedBackgroundVisibility(.hidden) is the "secret sauce": it hides
                    // the individual 'capsule/pill' background that iOS wraps around toolbar
                    // items, letting the beautiful full-width glass effect shine through.
                    .sharedBackgroundVisibility(.hidden)
                }
                .animation(.default, value: iapManager.loadingState) // Animates the swap
                .scrollDisabled(iapManager.loadingState != .loaded)
            }
            
            #if DEBUG
            VStack {
                HStack {
                    Spacer()
                    DebugIAPOverlay(iapManager: iapManager)
                }
                Spacer()
            }
            #endif
            
            VStack(spacing: 0) {
                Spacer()
//                YondoDivider()
                restorePurchasesSection
            }
            .ignoresSafeArea(edges: .bottom)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true // Kill the "swap" animation
            
            withTransaction(transaction) {
                // If we are about to fetch anyway, force the UI to loading state immediately
                // to prevent flashing an old error message.
                if iapManager.products.isEmpty || iapManager.shouldRefresh() {
                    iapManager.loadingState = .idle
                }
            }
        }
        .onDisappear {
            Log.debug("🎭 PMV: onDisappear triggered. Cleaning up temporary state.")
            hasAppeared = false
            iapManager.isAnimatingCelebration = false
            
            Task {
                await iapManager.syncService.flushBuffers()
            }
        }
        .task {
            Log.debug("🎭 PMV: Primary View Task started.")
            
            // If we have NO products, we need to show the spinner and fetch.
            if iapManager.products.isEmpty {
                Log.debug("🎭 PMV: No products found. Triggering synchronous retryFetch().")
                await iapManager.retryFetch() // Shows loading UI
            }
            // If we HAVE products but they are old, refresh silently in the background.
            else if iapManager.shouldRefresh() {
                Log.debug("🎭 PMV: Products exist but are stale. Triggering background fetchProducts().")
                await iapManager.fetchProducts() // Updates prices/list without clearing UI
            }
        }
        .onChange(of: iapManager.networkMonitor.isConnected) { _, isConnected in
            Log.debug("🎭 PMV: Network connectivity state shifted -> \(isConnected ? "Online" : "Offline").")
            guard isConnected else { return }
            
            // 1. Immediately lock the UI when internet returns
            Log.debug("🎭 PMV: Internet recovered. Locking UI briefly to allow IAPManager state to shift.")
            pendingConnectionRecovery = true
            
            Task {
                // 2. Wait a tiny bit to give IAPManager time to switch to .loading
                try? await Task.sleep(for: .seconds(0.5))
                
                // 3. Release the lock (IAPManager should be in .loading state by now)
                Log.debug("🎭 PMV: Releasing network recovery UI lock.")
                pendingConnectionRecovery = false
            }
        }
        .alert(item: $activeAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .cancel())
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Log.debug("🎭 PMV: App foregrounded. Evaluating if store data is stale.")
            
            // 1. Only act if the data is actually stale
            guard iapManager.shouldRefresh() else {
                Log.debug("🎭 PMV: Store data is fresh. Foreground fetch ignored.")
                return
            }
            
            refreshTask?.cancel()
            refreshTask = Task {
                // 2. If we are currently showing an error, wait for the OS to stabilize WiFi
                if case .error = iapManager.loadingState {
                    Log.debug("🎭 PMV: View is in Error state. Pausing 1.0s for OS network stabilizing before retrying fetch.")
                    try? await Task.sleep(for: .seconds(1.0))
                    await iapManager.retryFetch() // Shows spinner because we are in error state
                } else if case .loaded = iapManager.loadingState {
                    // 3. SILENT REFRESH: If already loaded, don't show a spinner!
                    // Just update products in the background so prices stay current.
                    Log.debug("🎭 PMV: View is Loaded. Performing background silent refresh.")
                    await iapManager.fetchProducts()
                }
            }
        }
        .onChange(of: iapManager.creditStore.credits) { oldValue, newValue in
            guard newValue != displayedCredits else {
                return
            }
            
            Log.debug("🎭 PMV: Credit balance change detected. UI Value: \(displayedCredits) -> Store Value: \(newValue)")
            
            // Wrap the state change in a spring animation to trigger the Text transition
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                displayedCredits = newValue
            }
            
            // Only trigger dismissal/success logic if credits actually increased
            // This prevents the modal from closing if the balance drops
            // or if RevenueCat has a temporary cache dip.
            guard newValue > oldValue, !isDismissing else { return }
            
            // If we are currently buying, let handlePurchase lead the way.
            // This prevents the .onChange from dismissing the view TOO FAST
            // before the button can turn green.
            guard iapManager.purchasingProductID == nil else {
                Log.debug("🎭 PMV: Skipping auto-dismissal. Either balance dropped or we are already dismissing.")
                return
            }
            
            // This path is now strictly for Restores/Background updates
            isDismissing = true // Mark that we are already handling success
            
            Log.debug("🎭 PMV: Spontaneous credit increase (Restore or Background drop). Triggering success haptic & dismissal.")
            HapticManager.shared.success()
            
            Task {
                // If they were on the Error screen, we definitely want to animate a recovery
                let wasInErrorState = if case .error = iapManager.loadingState { true } else { false }
                
                if newValue > 0 {
                    // Give them a moment to see the number change on the UI
                    Log.debug("🎭 PMV: Sleeping 1.5s to display credit increase transition before auto-dismissal.")
                    try? await Task.sleep(for: .seconds(1.5))
                    dismiss()
                } else if wasInErrorState {
                    // They recovered from an error but still have 0 credits
                    // (rare, but possible if a transaction was corrected but used)
                    Log.debug("🎭 PMV: Zero-balance recovery from error state. Refreshing products.")
                    await iapManager.fetchProducts()
                }
            }
        }
        .onChange(of: iapManager.creditStore.premiumDestinationsUnlocked) { oldUnlocked, newUnlocked in
            // Guard check: Only proceed if we are actually in a Restore flow.
            // If this is a regular purchase, handlePurchase() takes care of the dismissal/success UI.
            // 🔥 IDEMPOTENCY GUARD: Only celebrate if it's a NEW unlock (false -> true)
            guard isRestoring, !isDismissing, !oldUnlocked, newUnlocked else { return }
            
            Log.debug("🎭 PMV: Spontaneous Premium unlock detected during restore. Triggering success visual sequence.")
            isDismissing = true
            
            // If they just restored the premium unlock, close the store regardless of state
            Task {
                // Trigger success state
                HapticManager.shared.success()
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    // Update both in the same animation block so that the morphing
                    // animation for spinner -> restore glass buttons works
                    showSuccess = true
                    isRestoring = false
                }
                
                try? await Task.sleep(for: .seconds(2.0))
                
                withAnimation(.easeInOut) {
                    showSuccess = false
                }
                dismiss()
            }
        }
    }
    
    private var contentView: some View {
        VStack {
            switch iapManager.loadingState {
            case .idle, .loading:
                Spacer(minLength: 0)
                loadingView
                Spacer()
            case .error(let error):
                // Reduce this further to pull the content up
                // This compensates for the "Buy Credits" header height
                Spacer(minLength: 0)
                errorView(error)
                Spacer()
            case .loaded:
                productsView
            }
        }
        .id(iapManager.loadingState.idValue) // Forces a clean swap of the content area
        .transition(.opacity.combined(with: .scale(scale: 0.95))) // Makes it look polished
        .animation(.easeInOut, value: iapManager.loadingState)
    }
    
    @ToolbarContentBuilder
    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Store")
                .font(.system(.headline, design: .rounded).bold())
                .foregroundColor(.primary)
        }
    }
    
    private var productsView: some View {
        VStack(alignment: .leading) {
            creditsProductsSection
            
            if let _ = iapManager.products[.premiumDestinations] {
                if iapManager.hasSpendableCreditsProducts {
                    Rectangle()
                        .fill(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.3))
                        .frame(height: 0.33)
                        .padding(.horizontal, 16)
                }
                
                premiumDestinationsSection
            }
        }
    }
}
