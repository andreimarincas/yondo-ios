//
//  MoreDestinationsView.swift
//  Yondo
//
//  Created by Andrei Marincas on 25.12.2025.
//

import SwiftUI

struct MoreDestinationsView: View {
    @ObservedObject var viewModel: SceneBuilderViewModel
    let onClose: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var cardFrames: [SceneDestination: CGRect] = [:]
    
    @State private var isSelectionTransitioning = false // Track if we are closing
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Grid Configuration
    private let spacing: CGFloat = 16
    private let columnsCount: Int = 2
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // THE LIQUID DIMMER:
            // This layer sits behind the content but in front of the background.
            // It darkens the "room" when a card is picked.
            Color.black
                .opacity(isSelectionTransitioning ? 0.15 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: isSelectionTransitioning)
            
            NavigationStack {
                GeometryReader { geometry in
                    // Calculate card width once here or in a computed property
                    let totalSpacing = spacing * CGFloat(columnsCount - 1)
                    let cardWidth = (geometry.size.width - totalSpacing - 2 * spacing) / CGFloat(columnsCount)
                    
                    ScrollViewReader { scrollProxy in
                        mainScrollView(cardWidth: cardWidth)
                            .onPreferenceChange(CardFramePreferenceKey.self) { value in
                                cardFrames = value
                            }
                            .onChange(of: viewModel.destination) { _, newDest in
                                scrollToDestination(newDest, using: scrollProxy, geometry: geometry)
                            }
                            .allowsHitTesting(!isSelectionTransitioning)
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) {
                            onClose()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .yondoToolbarStyle(.dismiss)
                        }
                        .tint(.primary)
                        .blur(radius: isSelectionTransitioning ? 2 : 0)
                        .opacity(isSelectionTransitioning ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isSelectionTransitioning)
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private func mainScrollView(cardWidth: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                destinationsGrid(cardWidth: cardWidth)
                // Extra breathing room at the bottom
                Color.clear.frame(height: 40)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More Destinations")
                .font(.system(.title, design: .rounded).weight(.bold))
            
            Text("Explore iconic places and premium locations from around the world.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
        .padding(.horizontal)
        // LIQUID TOUCH: Fade and slightly shrink the header on selection
        .blur(radius: isSelectionTransitioning ? 4 : 0)
        .opacity(isSelectionTransitioning ? 0.3 : 1.0)
        .scaleEffect(isSelectionTransitioning ? 0.98 : 1.0)
        .animation(.spring(duration: 0.5), value: isSelectionTransitioning)
    }
    
    private func destinationsGrid(cardWidth: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columnsCount),
            spacing: spacing
        ) {
            ForEach(SceneDestination.allOrdered) { destination in
                destinationItem(for: destination, width: cardWidth)
            }
        }
        .padding(.horizontal, spacing)
    }
    
    private func destinationItem(for destination: SceneDestination, width: CGFloat) -> some View {
        // This is checked against the updated viewModel.destination
        let isThisCardSelected = destination == viewModel.destination
        let isActiveWinner = isSelectionTransitioning && isThisCardSelected
        
        // Choose the shadow color based on the mode
//        let selectionGlowColor: Color = {
//            if colorScheme == .dark {
//                return Color.white.opacity(0.2) // Soft glow for dark mode
//            } else {
//                return Color.black.opacity(0.1) // Deep lift for light mode
//            }
//        }()
        
        return MoreDestinationCard(
            destination: destination,
            isPremiumUnlocked: IAPManager.shared.creditStore.premiumDestinationsUnlocked,
            isSelected: isThisCardSelected,
            isActiveWinner: isActiveWinner,
            action: { selected in
                handleSelection(for: destination, isSelected: selected)
            }
            //isPremium: destination.isPremium
        )
        .id(destination)
        // Add a "soft light" behind the winner
//        .shadow(
//            color: (isSelectionTransitioning && isThisCardSelected)
//                ? selectionGlowColor
//                : Color.clear,
//            radius: isThisCardSelected ? 20 : 0
//        )
        // THE LIQUID FOCUS EFFECT: Winner grows, Losers shrink
        // If we are transitioning, blur everyone EXCEPT the new selection
        .blur(radius: (isSelectionTransitioning && !isThisCardSelected) ? 3.5 : 0)
        .saturation(isSelectionTransitioning && isThisCardSelected ? 1.2 : 1.0)
        .contrast((isSelectionTransitioning && !isThisCardSelected) ? 0.9 : 1.0) // Softens the "noise" of the blur
//        .scaleEffect((isSelectionTransitioning && !isThisCardSelected) ? 0.94 : 1.0)
        .opacity((isSelectionTransitioning && !isThisCardSelected) ? 0.5 : 1.0)
        // Use a crisp white glint instead of a "dirty" shadow
        .scaleEffect(isSelectionTransitioning ? (isThisCardSelected ? 1.06 : 0.94) : 1.0)
//        .shadow(
//            color: (isSelectionTransitioning && isThisCardSelected) ? selectionGlowColor : .clear,
//            radius: isThisCardSelected ? 20 : 0,
//            y: isThisCardSelected ? 10 : 0 // Shift shadow down in Light Mode for "height"
//        )
        .zIndex(isThisCardSelected ? 1 : 0) // Ensure the winner stays on top of blurred neighbors
//        .animation(.spring(duration: 0.4), value: isSelectionTransitioning)
//        .frame(width: width)
//        .aspectRatio(3/2, contentMode: .fill)
    }
    
    // MARK: - Logic Helpers
    
    private func handleSelection(for destination: SceneDestination, isSelected: Bool) {
        // 1. Trigger Haptic immediately
        HapticManager.shared.softSuccess()
        
        // 2. Start the "Focus" state
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            isSelectionTransitioning = true
            
            // 3. Update the source of truth INSIDE the same animation block
            // This ensures the grid re-evaluates 'isThisCardSelected'
            // at the exact same time the blur starts.
            viewModel.destination = destination
        }
        
        // 4. Update underlying logic
        if !destination.isPopular {
            viewModel.setSelectedExtraDestination(destination)
        } else {
            viewModel.setSelectedExtraDestination(nil)
        }
        viewModel.saveCurrentConfig()
        
        // 5. Dismissal delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { // A tiny bit more time for the zoom
            onClose()
            dismiss()
        }
        
        /*if !isSelected {
            // Selecting a new item
            if !destination.isPopular {
                viewModel.setSelectedExtraDestination(destination)
            } else {
                viewModel.setSelectedExtraDestination(nil)
            }
            viewModel.destination = destination
            viewModel.saveCurrentConfig()
            
            // 3. THE "LIQUID" DISMISSAL
            // A tiny delay ensures the user sees the button 'press'
            // before the modal starts its exit animation.
            // Slightly longer delay to let the user appreciate the blur/focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onClose()
                dismiss()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // If they tap the already selected one, we can also dismiss
                // since they are essentially confirming their current choice.
                onClose()
                dismiss()
            }
            
            // Deselecting existing item
//            if viewModel.isRunningOnFreeCredits {
//                // Prevent deselection during initial free credits
//                return
//            } else {
//                viewModel.clearDestination()
//                viewModel.setSelectedExtraDestination(nil)
//            }
        }*/
    }
    
    private func scrollToDestination(_ destination: SceneDestination?, using proxy: ScrollViewProxy, geometry: GeometryProxy) {
        guard let destination = destination,
              let frame = cardFrames[destination] else { return }
        
        let scrollViewHeight = geometry.size.height
        let cardMinY = frame.minY
        let cardMaxY = frame.maxY
        
        // Scroll only if out of view
        if cardMinY < 0 || cardMaxY > scrollViewHeight {
            withAnimation {
                proxy.scrollTo(destination, anchor: .center)
            }
        }
    }
}

struct CardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [SceneDestination: CGRect] = [:]
    static func reduce(value: inout [SceneDestination: CGRect], nextValue: () -> [SceneDestination: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/*struct MoreDestinationsView: View {
    @ObservedObject var viewModel: SceneBuilderViewModel
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cardFrames: [SceneDestination: CGRect] = [:]
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            NavigationStack {
                GeometryReader { geometry in
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("More Destinations")
                                        .font(.title.weight(.semibold))
                                    
                                    Text("Explore iconic places and premium locations from around the world.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 8)
                                .padding(.horizontal)
                                
                                let spacing: CGFloat = 16
                                let columns: Int = 2
                                let totalSpacing = spacing * CGFloat(columns - 1)
                                let cardWidth = (geometry.size.width - totalSpacing - 2 * spacing) / CGFloat(columns)
                                
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: columns),
                                    spacing: spacing
                                ) {
                                    ForEach(SceneDestination.allOrdered) { destination in
                                        MoreDestinationCard(
                                            destination: destination,
                                            isPremiumUnlocked: IAPManager.shared.creditStore.premiumDestinationsUnlocked,
                                            isSelected: destination == viewModel.destination,
                                            action: { selected in
                                                HapticManager.shared.select()
                                                if !selected {
                                                    if !destination.isPopular {
                                                        viewModel.selectedExtraDestination = destination
                                                    } else {
                                                        viewModel.selectedExtraDestination = nil
                                                    }
                                                    viewModel.selectDestination(destination)
                                                } else {
                                                    if viewModel.isRunningOnFreeCredits {
                                                        // Prevent deselection during initial free credits, keep haptic only
                                                    } else {
                                                        viewModel.clearDestination()
                                                        viewModel.selectedExtraDestination = nil
                                                    }
                                                }
                                            },
                                            isPremium: destination.isPremium
                                        )
                                        .id(destination)
                                        .frame(width: cardWidth)
                                        .aspectRatio(3/2, contentMode: .fill)
                                    }
                                }
                                .padding(.horizontal, spacing)
                            }
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(CardFramePreferenceKey.self) { value in
                            cardFrames = value
                        }
                        .onChange(of: viewModel.destination) { _, newDestination in
                            guard let destination = newDestination else { return }
                            
                            if let frame = cardFrames[destination] {
                                let scrollViewHeight = geometry.size.height
                                let cardMinY = frame.minY
                                let cardMaxY = frame.maxY

                                if cardMinY < 0 || cardMaxY > scrollViewHeight {
                                    withAnimation {
                                        scrollProxy.scrollTo(destination, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(viewModel.destination?.title ?? "Select Destination")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                onClose()
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}*/

//struct CardFramePreferenceKey: PreferenceKey {
//    static var defaultValue: [SceneDestination: CGRect] = [:]
//    static func reduce(value: inout [SceneDestination: CGRect], nextValue: () -> [SceneDestination: CGRect]) {
//        value.merge(nextValue(), uniquingKeysWith: { $1 })
//    }
//}
