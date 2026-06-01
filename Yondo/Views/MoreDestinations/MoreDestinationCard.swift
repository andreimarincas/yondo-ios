//
//  MoreDestinationCard.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import SwiftUI

struct MoreDestinationCard: View {
    let destination: SceneDestination
    let isPremiumUnlocked: Bool
    let isSelected: Bool
    let isActiveWinner: Bool
    let action: (Bool) -> Void
    
    @State private var isPressed = false // Track local press for text dimming
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            action(isSelected)
        }) {
            ZStack(alignment: .bottomLeading) {
                // 1. The Image Base
                GeometryReader { geo in
                    Image(destination.thumbnailName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .aspectRatio(3/2, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                
                // 2. The Premium Badge (Jewelry Style)
                if destination.isPremium {
                    badgeOverlay
                }
                
                // 3. The Content & Gradient
                VStack(alignment: .leading, spacing: 1) {
                    Text(destination.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(destination.subtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // Use the same layered gradient strategy from DestinationCard
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(isPressed ? 0.7 : 1.0) // Dim text on press
            }
            .aspectRatio(3/2, contentMode: .fit)
            // MATCH: Same card shaping as SceneBuilder
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .drawingGroup()
        }
        // Use a customized version of our "Liquid" style
        .buttonStyle(MoreDestinationButtonStyle(isSelected: isSelected, isActiveWinner: isActiveWinner, externalIsPressed: $isPressed))
    }
    
    // MATCH: Your premium badge logic from DestinationCard
    @ViewBuilder
    private var badgeOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Text(isPremiumUnlocked ? "⭐" : "🔒")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    .padding(8)
            }
            Spacer()
        }
    }
}

struct MoreDestinationButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isActiveWinner: Bool
    @Binding var externalIsPressed: Bool
    @State private var isAnimatingPress = false
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || isAnimatingPress
        
        // 1. Logic for the Border Color
//        let selectionStrokeColor: Color = {
//            if isSelected {
//                return colorScheme == .dark ? Color.yondoInteractive : Color.black.opacity(0.75)
//            }
//            return .white.opacity(isPressed ? 0.08 : 0.15)
//        }()
        
        configuration.label
            // Dynamic Border: Glows when selected, dims when pressed
//            .overlay(
//                RoundedRectangle(cornerRadius: 22, style: .continuous)
//                    .stroke(
//                        selectionStrokeColor,
//                        lineWidth: isSelected ? (colorScheme == .dark ? 2.5 : 4) : 1 // Slightly thinner for "Ink" look
//                    )
//            )
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(isActiveWinner ? 0.2 : 0.2), lineWidth: 1.0)
                }
            }
//            .scaleEffect(isPressed ? 0.96 : (isSelected ? 1.04 : 1.0))
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .brightness(isPressed ? -0.08 : 0)
            .saturation(isPressed ? 1.1 : 1.0)  // Subtle "pop" on tap
            .shadow(
                color: colorScheme == .light ? Color.black.opacity(0.2) : Color.black.opacity(0.4),
                radius: isPressed ? 2 : 6,
                x: 0,
                y: isPressed ? 1 : 3
            )
//            .shadow(
//                color: Color.black.opacity(0.1),
//                radius: isPressed ? 2 : (isSelected ? 12 : 6),
//                x: 0,
//                y: isPressed ? 1 : (isSelected ? 6 : 3)
//            )
//            .shadow(
//                color: isSelected
//                    ? (colorScheme == .dark ? Color.sceneAccent.opacity(0.4) : Color.black.opacity(0.2))
//                    : Color.black.opacity(0.1),
//                radius: isPressed ? 2 : (isSelected ? 12 : 6),
//                x: 0,
//                y: isPressed ? 1 : (isSelected ? 6 : 3)
//            )
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isPressed)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isSelected)
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    externalIsPressed = true
                    isAnimatingPress = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                            isAnimatingPress = false
                            externalIsPressed = false
                        }
                    }
                }
            }
    }
}

/*struct MoreDestinationCard: View {
    let destination: SceneDestination
    let isPremiumUnlocked: Bool
    let isSelected: Bool
    let action: (Bool) -> Void
    let isPremium: Bool // optional for showing premium badge
    
    @Environment(\.colorScheme) private var colorScheme
    
    var badgeSymbol: String? {
        guard destination.isPremium else { return nil }
        return isPremiumUnlocked ? "⭐" : "🔒"
    }
    
    var body: some View {
        Button(action: {
            action(isSelected)
        }, label: {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Image(destination.thumbnailName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width * 2 / 3)
                        .selectionEmphasis(isSelected: isSelected)
                        .clipped()
                        .background(
                            Color.clear
                                .preference(key: CardFramePreferenceKey.self,
                                            value: [destination: geo.frame(in: .named("scroll"))])
                        )
                }

                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.7)
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(destination.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                if let badge = badgeSymbol {
                    Text(badge)
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial.opacity(0.85))
                        .clipShape(Circle())
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.sceneAccent : Color.clear, lineWidth: 4)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            )
        })
        .buttonStyle(.plain)
        .shadow(color: shadowColor, radius: 8, y: 4)
    }
    
    private var shadowColor: Color {
        return (colorScheme == .dark
                ? Color.white.opacity(isSelected ? 0.25 : 0.15)
                : Color.black.opacity(isSelected ? 0.45 : 0.35))
    }
}*/
