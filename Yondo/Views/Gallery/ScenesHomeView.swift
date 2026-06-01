//
//  ScenesHomeView.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.01.2026.
//

import SwiftUI

struct ScenesHomeView: View {
    @EnvironmentObject var authManager: AuthManager
    
    @State var showCreateFlow = false
    @State var selectedEntry: GeneratedImage?
    @ObservedObject var imageStore = ImageStore.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.safeAreaInsets) var safeAreaInsets
    
    // Tracking for the Glass Header
    @State var scrollOffset: CGFloat = 0
    
    @State var toolbarIsDark = false
    
    @State var gallerySyncID: UUID? = nil
    @State var allSourceFrames: [UUID: CGRect] = [:] // TODO: clear when isVisualHeroMode is false
    @State var triggerDismiss = false
    @State var isVisualHeroMode = false
    @State var transitionImage: UIImage? // The "Starter" image
    @State var currentDragScale: CGFloat = 1.0
    @State var isFullSizeSettled = false
    @State var isSelectionLocked = false
    @State var forceDarkMode = false
    
    @State var viewportHeight: CGFloat = 0
    @State var contentHeight: CGFloat = 0
    
    @State var snapshottedImages: [GeneratedImage] = []
    
    @State var showDeleteConfirmation = false
    @State var isPerformingDelete = false
    
    @StateObject var shareProvider = ImageShareProvider(imageStore: ImageStore.shared)
    
    @State var loadedImageIds: Set<UUID> = []
    @State var priorityLaunchIDs: Set<UUID> = []
    @State var isGridFullyRendered = false
    @State private var hasConfirmedNoData = false
    @State var isProcessingInitialBatch = false
    @State var revealTask: Task<Void, Never>? = nil
    
    init() {
        // This will fire every time the parent re-evaluates the view
        Log.debug("🏗️ [LIFECYCLE] ScenesHomeView Instance Created.")
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                applyNavigationConfiguration(to: mainStackContent)
            }
//            .overlay { debugOverlay }
        }
        .statusBar(hidden: isVisualHeroMode)
        // ⚓️ The cover is anchored to the stable root
        .fullScreenCover(isPresented: $showCreateFlow) {
            CreateSceneFlowView(viewModel: SceneBuilderManager.shared.startFlow())
        }
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76), value: isVisualHeroMode)
        .onAppear { handleOnAppear() }
        .onChange(of: selectedEntry) { _, newValue in
            if newValue == nil {
                // When the hero is gone, unlock the grid
                // Wait for the 'shrink back' spring to mostly finish
                // before giving the user control of the scroll again.
                // It prevents the user from accidentally "Double Tapping"
                // and launching two Hero transitions at once during the
                // spring-back animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isSelectionLocked = false
                }
            }
        }
        .onChange(of: imageStore.hasLoadedInitialData) { _, loaded in
            if loaded { updateSnapshottedImages(imageStore.entries) }
        }
        .onChange(of: isGridFullyRendered) { _, rendered in
            if rendered {
                // Wait for the final "reveal" animation to finish (0.4s)
                // then trigger the background maintenance.

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    triggerBackgroundMaintenance()
                }
            }
        }
        .alert("Delete Yondo?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                handleDeleteAction()
            }
            Button("Keep It", role: .cancel) {}
        }
        .shareSheet(provider: shareProvider)
    }
    
    private func handleOnAppear() {
        handleAppLaunching()
        Log.debug("🎬 [VIEW] ScenesHomeView Appeared. Snap Window starts now.")
        
        /* 🛑 THE WATCHDOG TRAP (0x8BADF00D):
         * DO NOT call 'updateSnapshottedImages' directly here.
         * During 'onAppear', the OS is already under high stress initializing
         * the NavigationStack. Injecting the image library here creates a
         * layout spike that hangs the Main Thread and triggers the Watchdog.
         *
         * THE FIX: We rely on 'onReceive(imageStore.$entries)' or the deferred
         * logic in 'updateSnapshottedImages' to drip-feed the UI only after
         * the initial scene transition has settled.
         */
        
        // Use the relative sum to ensure animations are definitely 'ON'
        // before the fallback triggers.
        let totalTimeout = AppLaunchContext.snapWindow + AppLaunchContext.safetyFallbackTimeout
        
        // Safety fallback: if images take > 2s, just show the grid anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTimeout) {
            if !isGridFullyRendered {
                Log.warning("Safety fallback triggered: Priority images failed to load in time.")
                
                // Safety: Ensure animations are enabled even if handleAppLaunching failed
                AppLaunchContext.isAppLaunching = false
                
                // Just change the state.
                // The .animation modifier on the ZStack handles the 'how'.
                isGridFullyRendered = true
                
                // See how many actually managed to load before the timeout
                printWatchdogHealth()
            }
        }
    }
    
    private var isReadyForUpdates: Bool {
        // We only care if the data is actually there to be read.
        imageStore.hasLoadedInitialData
    }
    
    var isShowingEmptyGalleryView: Bool {
        // Only show empty state if data is loaded, it's actually empty,
        // AND we aren't currently busy animating a deletion.
        authManager.hasRevealedApp &&
        imageStore.hasLoadedInitialData &&
        imageStore.entries.isEmpty &&
        !isPerformingDelete
    }
    
    var showsGrid: Bool {
        // If we are performing a delete, keep the grid visible
        // even if the count is 0, so the animation has a place to finish.
        let hasData = !snapshottedImages.isEmpty || isPerformingDelete
        return isGridFullyRendered && hasData
    }
    
    /*
     * MISSION: LAUNCH ORCHESTRATION & WATCHDOG (0x8BADF00D) PREVENTION
     * * This ZStack implements a "Physical Swap" strategy. It balances an "Instant-On"
     * user feel with the technical constraints of high-density grid rendering.
     *
     * 1. PERCEPTUAL LOADING (UX):
     * - "Turbo Launch" (<0.5s): If data arrives instantly, we use .none to 'snap' the
     * grid in. This makes the app feel native and pre-loaded.
     * - "Graceful Arrival" (>0.5s): If disk/cloud IO takes longer, we enable .easeInOut
     * to mask the skeleton-to-content swap, making the wait feel intentional.
     *
     * 2. STRUCTURAL STABILITY (Performance):
     * - CONDITIONAL DESTRUCTION: Using 'if !showsGrid' physically destroys the skeleton
     * nodes once ready. This kills background layout cycles and prevents "Layout Thrashing."
     * - SHADOW WARM-UP: The 'scrollableContent' stays at .opacity(0) during launch,
     * allowing the LazyVGrid to pre-calculate the 'VIP Batch' (first 12 items)
     * silently behind the skeleton 'shield'.
     * - Z-INDEX & ID STABILITY: Explicit .zIndex (0-4) and .id handles prevent SwiftUI
     * from re-ordering views during the swap, ensuring the GPU transition is a
     * single, clean draw call rather than a "muddy" layout recalculation.
     */
    private var mainStackContent: some View {
        ZStack(alignment: .top) {
            backgroundLayer
            
            // 1. MAIN CONTENT (Base Layer)
            // We keep the real content at the bottom of the stack.
            // It's "revealed" as the skeleton on top disappears.
            scrollableContent
                .ignoresSafeArea(.container, edges: .top) // Content goes UNDER the bar
                .opacity(showsGrid ? 1 : 0)
                .zIndex(0)
                .id("MAIN_GALLERY") // Stability handle
            
            // 2. SKELETON (Overlay Layer)
            // By keeping this at a higher Z-index permanently,
            // we ensure it's the thing that "fades away" off the screen.
            if !showsGrid {
                skeletonGridView
                    .zIndex(1)
                    .allowsHitTesting(false) // Safety: ghost doesn't block touches
                    .id("SKELETON_GALLERY") // Stability handle
                    .transition(.opacity)
            }
            
            // 3. EMPTY VIEW: On top of everything so the button is always tappable
            if isShowingEmptyGalleryView {
                emptyStateView
                    .zIndex(2)
                    .allowsHitTesting(isShowingEmptyGalleryView)
                    .id("EMPTY_GALLERY")
                    .transition(.opacity)
            }
            
            // 4. HERO
            heroOverlay.zIndex(3) // TODO: Move above glass header?
            
            // 5. GLASS HEADER
            glassHeaderOverlay.zIndex(4)
        }
        
        // Change to a standard ease-out. Springs can sometimes "overshoot"
        // opacity values, causing a flicker at the start.
        .animation(
            AppLaunchContext.isAppLaunching ? .none : .easeInOut(duration: 0.4),
            value: isGridFullyRendered // Watch the "Readiness" instead of the "Data"
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: snapshottedImages.isEmpty)
        .animation(.easeInOut(duration: 0.4), value: imageStore.hasLoadedInitialData) // Smooth fade for the store state
    }
    
    private func applyNavigationConfiguration<V: View>(to content: V) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsGrid {
                    homeToolbarItems
                }
            }
            .toolbarBackground(showsGrid ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(preferredToolbarScheme, for: .navigationBar)
            .animation(.easeInOut(duration: 0.4), value: showsGrid)
            // 🔑 Update the grid only when the data changes AND we aren't in Hero mode
            .onReceive(imageStore.$entries) { newEntries in
                updateSnapshottedImages(newEntries)
            }
            // 🔑 Catch up on missed updates when the Hero is dismissed
            .onChange(of: isVisualHeroMode) { _, isHero in
                handleOnChangeOfVisualHeroMode(isHero)
            }
    }
    
    private func updateSnapshottedImages(_ entries: [GeneratedImage]) {
        guard isReadyForUpdates && entries != snapshottedImages else { return }
        
        // Only auto-sync if we aren't currently in the middle of a Hero transition/deletion
        guard !isVisualHeroMode && selectedEntry == nil && !isSelectionLocked else { return }
        
        // 🛡️ THE DATA GUARD: If we are already mid-launch-sequence, don't restart the timers.
        // This prevents the "Thundering Herd" effect on the Data Layer.
        guard !isProcessingInitialBatch else { return }
        
        let currentPriority = Set(entries.prefix(priorityCount).map { $0.id })
        self.priorityLaunchIDs = currentPriority
        
        if !AppLaunchContext.isAppLaunching {
            Log.debug("🔄 [SYNC] Normal update: \(entries.count) items")
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                self.snapshottedImages = entries
            }
        } else {
            // 🚨 LOCK THE GATE
            isProcessingInitialBatch = true
            
            // 1. Immediate VIP Batch
            // Just the visible 'Hero' area (e.g., first 6-9 items)
            // This completes in ~16ms, allowing the UI to 'flush' and stay alive.
            let vipBatch = entries.filter { currentPriority.contains($0.id) }
            logLaunchPerformance(count: vipBatch.count, stage: "VIP_BATCH")
            self.snapshottedImages = vipBatch
            
            // 2. Deferred Full Library
            // We use a slight delay to ensure the OS 'Scene Creation' timer resets.
            // We wait for the first layout pass to settle before hitting the CPU again.
            // Load the rest after the UI is interactive
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                logLaunchPerformance(count: entries.count, stage: "DEFERRED_FULL")
                
                // App is starting up? Use the "Safe" curve to avoid Watchdog.
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.snapshottedImages = entries
                }
                
                // 🔓 UNLOCK THE GATE: After the transition is fully committed to the GPU
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.isProcessingInitialBatch = false
                    
                    // Final safety: ensures transition state is reset
                    if AppLaunchContext.isAppLaunching {
                         AppLaunchContext.isAppLaunching = false
                    }
                }
            }
        }
    }
    
    var backgroundLayer: some View {
        Group {
            // 🛡️ The "Glitch Shield": A tiny invisible pixel to stabilize the NavStack
            // Keeps the NavigationStack from collapsing when the ZStack is performing its swap.
            Color.clear.frame(height: 1)
            
            // A background that matches the theme to hide scaling gaps
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        }
    }
    
    var scrollableContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("SCROLL_TOP_ID")
                    
                    scrollTracker()
                    
                    // Top padding so content starts below the header
                    Spacer().frame(height: dynamicHeaderHeight)
                    
                    galleryGrid()
                }
            }
            .coordinateSpace(name: "gallery_space") // 🔑 2. The Anchor
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .top) // Content goes UNDER the bar
            .contentMargins(.top, dynamicHeaderHeight, for: .scrollIndicators)
            .contentMargins(.trailing, 2, for: .scrollIndicators)
            .scrollDisabled(snapshottedImages.count == 0 || selectedEntry != nil || isSelectionLocked || isVisualHeroMode)
            .scrollIndicators(.never, axes: .horizontal)
            .scrollIndicators(isVisualHeroMode ? .hidden : .automatic, axes: .vertical)
            .allowsHitTesting(selectedEntry == nil && !isSelectionLocked)
            .onReceive(imageStore.didAddNewImage) { entry in
                handleDidAddNewImage(entry: entry, scrollProxy: scrollProxy)
            }
            .onPreferenceChange(UUIDFramePreferenceKey.self) { preferences in
                self.allSourceFrames.merge(preferences) { (_, new) in new }
            }
            .onChange(of: gallerySyncID) { _, newID in
                guard let newID = newID else { return }
                scrollEntryToVisible(newID, scrollProxy: scrollProxy)
            }
        }
    }
}
