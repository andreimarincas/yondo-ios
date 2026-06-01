//
//  SceneBuilderView+Destinations.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    @ViewBuilder
    func destinationsSection() -> some View {
        VStack(alignment: .leading, spacing: -3) {
            // 1. Extracted Header
            destinationsHeader
            
            // 2. Extracted Expanded Content
            if isDestinationsExpanded {
                destinationsCarousel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, isDestinationsExpanded ? 0 : 24)
        .onChange(of: isDestinationsExpanded) { _, expanded in
            triggerScrollToSelection(expanded: expanded)
        }
        .sheet(isPresented: $showMoreDestinations) {
            MoreDestinationsView(
                viewModel: viewModel,
                onClose: handleMoreDestinationsClose
            )
        }
    }
    
    private var destinationsHeader: some View {
        Button {
            HapticManager.shared.select()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                isDestinationsExpanded.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("EXPLORE")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .tracking(1.0)
                    .foregroundColor(.primary)
                
                if let destination = viewModel.destination, !isDestinationsExpanded {
                    Text(destination.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.yondoInteractive)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .rotationEffect(.degrees(isDestinationsExpanded ? 0 : -90))
                    .foregroundColor(
                        !isDestinationsExpanded && viewModel.destination != nil
                            ? Color.yondoInteractive
                            : .yondoSecondaryText(for: colorScheme)
                    )
                    .padding(.leading, 5)
                    .offset(y: -1.5)
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, LayoutConstants.horizontalPadding)
    }
    
    @ViewBuilder
    private var destinationsCarousel: some View {
        // Layout Constants
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth = screenWidth * 0.70
        let cardHeight = cardWidth * (9/16)
        let topMargin: CGFloat = 20
        let bottomMargin: CGFloat = 30
        let totalHeight = cardHeight + topMargin + bottomMargin
        let horizontalInset = (screenWidth - cardWidth) / 2

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // A. Destination Cards
                    ForEach(viewModel.destinationsToShow) { destination in
                        makeDestinationCard(
                            destination: destination,
                            width: cardWidth,
                            height: cardHeight,
                            proxy: proxy
                        )
                    }

                    // B. "Show More" Card
                    makeShowMoreCard(width: cardWidth, height: cardHeight)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
//            .scrollPosition($position)
            .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
            .contentMargins(.top, topMargin, for: .scrollContent)
            .contentMargins(.bottom, bottomMargin, for: .scrollContent)
            .onAppear {
                if let selected = viewModel.destination {
                    DispatchQueue.main.async { proxy.scrollTo(selected.id, anchor: .center) }
                }
                // Wait for the push animation to finish before allowing reflections
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
//                    suppressInitialAnimation = false
//                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToSelectedDestination)) { notification in
                if let id = notification.object as? SceneDestination.ID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                activePhase = newPhase
            }
            .onScrollTargetVisibilityChange(idType: ScrollTarget.self) { visibleIDs in
                handleScrollTargetVisibilityChanged(visibleIDs: visibleIDs)
            }
        }
        .frame(height: totalHeight)
    }
    
    func updateScrollDirection(for newHero: SceneDestination, oldHero: SceneDestination?) {
        guard let oldHero, let oldIndex = viewModel.destinationsToShow.firstIndex(where: { $0.id == oldHero.id }) else {
            scrollDirection = -1.0 // navigating back from "More Destinations" card
            return
        }
        guard let newIndex = viewModel.destinationsToShow.firstIndex(where: { $0.id == newHero.id }) else {
            scrollDirection = 1.0
            return
        }
        scrollDirection = newIndex > oldIndex ? 1.0 : -1.0
    }
    
    @ViewBuilder
    private func makeDestinationCard(
        destination: SceneDestination,
        width: CGFloat,
        height: CGFloat,
        proxy: ScrollViewProxy
    ) -> some View {
        DestinationCard(
            destination: destination,
            isPremiumUnlocked: iapManager.creditStore.premiumDestinationsUnlocked,
            isSelected: destination == viewModel.destination,
            anySelected: viewModel.destination != nil,
            isPinned: destination == viewModel.selectedExtraDestination,
            scrollDirection: scrollDirection,
            animateReflection: selectionCount > 0 && (destination == viewModel.destination),
            action: {
                // 1. Update the Selection immediately for UI responsiveness
                viewModel.destination = destination
                
                // 2. Center the card in the UI
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    proxy.scrollTo(ScrollTarget.destination(destination.id), anchor: .center)
                }
                
                // 3. Apply the presets (Sliders move, etc.)
                let presetsChanged = viewModel.applyPresets(for: destination)
                
                // 4. Success haptic
                if presetsChanged {
                    HapticManager.shared.lightImpact()
                } else {
                    HapticManager.shared.softImpact(intensity: 0.7)
                }
            }
        )
        .frame(width: width, height: height)
        .id(ScrollTarget.destination(destination.id))
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(1.0 - (abs(phase.value) * 0.06))
                .saturation(1.0 - (abs(phase.value) * 0.25))
                .opacity(1.0 - (abs(phase.value) * 0.2))
                .rotation3DEffect(
                    .degrees(phase.value * -5),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
        }
    }
    
    @ViewBuilder
    private func makeShowMoreCard(width: CGFloat, height: CGFloat) -> some View {
        ShowMoreDestinationsCard {
            viewModel.snapshotPresetsIfNeeded()
            showMoreDestinations = true
        }
        .id(ScrollTarget.showMore)
        .frame(width: width, height: height)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(1.0 - (abs(phase.value) * 0.12))
                .opacity(1.0 - (abs(phase.value) * 0.3))
        }
    }
}

private extension SceneBuilderView {
    func triggerScrollToSelection(expanded: Bool) {
        guard expanded, let destination = viewModel.destination else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .scrollToSelectedDestination,
                object: destination.id
            )
        }
    }
    
    func handleMoreDestinationsClose() {
        if viewModel.destination == nil {
            viewModel.restorePresetsIfNeeded()
        } else {
            viewModel.clearPresetSnapshot()
        }
        showMoreDestinations = false
    }
    
    func handleScrollTargetVisibilityChanged(visibleIDs: [ScrollTarget]) {
        guard activePhase != .idle else { return }
        guard let heroTarget = visibleIDs.first else { return }
        
        selectionCount += 1
        
        switch heroTarget {
        case .destination(let id):
            // Update your ViewModel as usual
            if let hero = viewModel.destinationsToShow.first(where: { $0.id == id }) {
                if viewModel.destination?.id != id {
                    updateScrollDirection(for: hero, oldHero: viewModel.destination)
                    viewModel.destination = hero
                    viewModel.saveCurrentConfig()
                    HapticManager.shared.select()
                }
            }
            
        case .showMore:
            // ✨ This is where you detect the "Show More" card settling
            Log.debug("Scrolled to the end - Show More is now the Hero!")
            
            // You could trigger a haptic or prepare the sheet data here
            HapticManager.shared.lightImpact()
            
            scrollDirection = 1.0
            
            // Note: You probably want to set viewModel.destination = nil
            // so the 'Create' button disappears/disables when on this card.
            viewModel.destination = nil
            viewModel.saveCurrentConfig()
        }
    }
}

// MARK: - 5. Logic Helpers (Moving logic out of the View Body)

//    private func handleDestinationSelection(_ destination: SceneDestination, proxy: ScrollViewProxy) {
//        HapticManager.shared.select()
//
//        let isFreeCreditsOnly = viewModel.isRunningOnFreeCredits
//        let wasSelected = viewModel.destination == destination
//
//        // Prevent deselection when running on initial free credits
//        if isFreeCreditsOnly && wasSelected { return }

//        viewModel.selectDestination(destination)

//        if !wasSelected {
//            withAnimation {
//                proxy.scrollTo(destination.id, anchor: .center)
//            }
//        }
//    }
