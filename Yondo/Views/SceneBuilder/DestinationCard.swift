//
//  DestinationCard.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import SwiftUI

private let cardRadius: CGFloat = 22

struct DestinationCard: View {
//    @State private var hasSeated = false // Tracks if the card has finished its initial load
    
    let destination: SceneDestination
    let isPremiumUnlocked: Bool
    let isSelected: Bool
    let anySelected: Bool
    let isPinned: Bool
    let scrollDirection: CGFloat
    let animateReflection: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    // This state will drive the actual animation independent of the selection state
    @State private var sweepProgress: CGFloat = 0
    
    var body: some View {
        Button {
            // This ONLY runs if the user didn't scroll
//            HapticManager.shared.softImpact(intensity: 0.65)
            action()
        } label: {
            ZStack(alignment: .topTrailing) { // Top trailing for the badge
                cardContent
                badgeOverlay // 👈 Now actually visible
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .rotationEffect(.degrees(isSelected ? 5 : 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.1), value: isSelected)
            }
        }
        .buttonStyle(DestinationButtonStyle(isSelected: isSelected))
        // This allows the button to be triggered even if the background is clear
//        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var cardContent: some View {
        ZStack(alignment: .bottomLeading) {
            Image(destination.thumbnailName)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(minHeight: 0, maxHeight: .infinity)
                .clipped()
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            
            // The Sweep Reflection
//            reflectionOverlay
//                .mask(RoundedRectangle(cornerRadius: 16))
//                .allowsHitTesting(false) // Ensure it doesn't block taps
            
            /*if animateReflection { //}&& hasSeated {
                reflectionOverlay
                    .mask(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                    .blendMode(.plusLighter) // Makes the light "bleed" into the image naturally
                    .allowsHitTesting(false)
                    // This transition ensures it disappears instantly on deselect
                    .transition(
                        .asymmetric(
                            // The "Pro Tip": A slightly longer fade-in so it "blooms" onto the card
                            insertion: .opacity.animation(.easeIn(duration: 0.3)), // Fade in quick
                            removal: .identity // Vanish instantly on removal
                        )
                    )
                    // This animation drives the sweep
//                    .animation(.easeOut(duration: 0.9).delay(0.1), value: isSelected)
                    .onAppear {
                        sweepProgress = 0 // Reset to start
                        // 💧 THE LENS FLARE PHYSICS:
                        // Using a steeper timing curve (0.4, 0, 0.2, 1) makes the light
                        // "zip" across the center but linger on the edges.
                        withAnimation(.timingCurve(0.3, 0, 0.3, 1, duration: 1.2).delay(0.0)) {
                            sweepProgress = 1
                        }
                        // A tiny delay to ensure the card is rendered before it's allowed to sweep
                        // This effectively "uses up" the first true state of 'animateReflection'
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
//                            hasSeated = true
//                        }
                    }
                    .onDisappear {
                        sweepProgress = 0 // Reset for next time
                    }
            }*/
            
            VStack(alignment: .leading, spacing: 1) { // Tighter line spacing for a "unit" feel
                Text(destination.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1) // Extra safety
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(destination.subtitle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.white.opacity(0.9)) // 0.85 0.9
                    .shadow(color: .black.opacity(colorScheme == .light ? 0.4 : 0.2), radius: 1, x: 0, y: 1) // 👈 Contrast boost
                    .lineLimit(1)
            }
//            .padding(.horizontal, 16)
            .padding(.leading, 18) // Extra nudge for the "Liquid" curve
            .padding(.trailing, 12)
//            .padding(.vertical, 12)
//            .padding(.vertical, 8) // Keep top tighter to stay away from the middle
            .padding(.bottom, 14) // Gives the subtitle room to breathe above the curve
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // THE LAYERED GRADIENT STRATEGY
                ZStack {
                    // 1. The "Color Burn" Layer
                    // This makes the shadow deep and colorful based on the photo
                    LinearGradient(
                        colors: [
                            .clear,
                            colorScheme == .dark ? .black.opacity(0.8) : .yondoDeep.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.multiply)
                    
                    if colorScheme == .dark {
                        // 2. The "Readability" Layer
                        // A very subtle standard gradient to ensure white text pops
                        // even if the photo has a very bright white spot at the bottom.
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        // 2. The Light Mode "Softener"
                        // In light mode, we add a tiny bit of white-tinted blur OR
                        // just reduce the black opacity so it doesn't look like "ink"
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.1)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
                }
            }
        }
        
        // 3. SHAPING THE CARD
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous)) // Shapes the ZStack (Image + Text)
        // 6. HIT AREA & PERFORMANCE
        // This flattens the image + gradients into one layer for the GPU
        // making the scale animation much smoother on older devices.
        .drawingGroup()
    }
    
    @ViewBuilder
    private var badgeOverlay: some View {
        if destination.isPremium {
            Text(isPremiumUnlocked ? "⭐" : "🔒")
                .font(.system(size: 13, weight: .bold)) // Slightly smaller font for a "jewelry" feel
                .frame(width: 28, height: 28)           // Fixed size makes it a perfect circle
                .background {
                    // Add a secondary layer to ensure visibility on dark images
                    ZStack {
                        // The "Frosted" base
                        Circle()
                            .fill(colorScheme == .dark
                                  ? Color.white.opacity(0.15)
                                  : Color.white.opacity(0.85)) // Stronger white in light mode
                        
                        // The "Liquid Rim" - This is what makes it look like a physical object
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        
//                        Circle()
//                            .fill(.white.opacity(colorScheme == .dark ? 0.1 : 0.2))
//                        
//                        Circle()
//                            .stroke(.white.opacity(0.2), lineWidth: 0.5) // A "Liquid" rim
//                        
//                        Rectangle()
//                            .fill(.ultraThinMaterial) // The actual blur
                    }
                }
//                .background(.ultraThinMaterial)
                .clipShape(Circle())
                // A crisp shadow to separate it from the image
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1.5)
                // Subtle shadow so it doesn't get lost in the thumbnail textures
//                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                // The "Yondo" Nudge:
                .padding(.top, 12)    // Increased from 8
                .padding(.trailing, 12) // Increased from 8
        }
    }

@ViewBuilder
  private var reflectionOverlay: some View {
      GeometryReader { geo in
          let width = geo.size.width
          let height = geo.size.height
          let travelDistance = width * 2
          
          // Start is always opposite of where we want to go
          let startX = -travelDistance// * scrollDirection
          let endX = travelDistance// * scrollDirection
          
          Rectangle()
              .fill(
                  LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white.opacity(0.05), location: 0.3), // Even softer ramp-in
                        .init(color: .white.opacity(0.12), location: 0.5), // The "Whisper" peak
                        .init(color: .white.opacity(0.05), location: 0.7), // Even softer ramp-out
                        .init(color: .clear, location: 1.0)
                    ],
                      startPoint: .leading,
                      endPoint: .trailing
                  )
              )
              .frame(width: width * 0.8, height: height * 3)
              .rotationEffect(.degrees(35))
//                .rotationEffect(.degrees(15 * scrollDirection))
//                .rotationEffect(.degrees(-20 * scrollDirection))
              // 1. Position it based on selection
//                .offset(x: isSelected ? endX : -startX)
//                .offset(x: animateReflection ? travelDistance : -travelDistance)
              // The logic: If selected, be at the destination. If not, be at the start.
//                .offset(x: isSelected ? endX : startX)
              .offset(x: startX + (endX - startX) * sweepProgress)
              .position(x: width / 2, y: geo.size.height / 2)
              // 2. Hide it instantly when not selected
              .opacity(isSelected ? 1.0 : 0.0)
              .position(x: width / 2, y: geo.size.height / 2)
              // 3. The critical part: Different animation for ON vs OFF
              .animation(
                  isSelected
                      ? .easeOut(duration: 0.8)//.delay(0.04)
                      : .linear(duration: 0), // Snap back instantly when deselected
                  value: isSelected
              )
      }
  }
  
  private var shadowColor: Color {
      guard isSelected else { return .clear }
      return colorScheme == .dark ? Color.yondoBrand.opacity(0.35) : Color.black.opacity(0.55)
  }
}

struct DestinationButtonStyle: ButtonStyle {
    let isSelected: Bool
    @State private var isAnimatingPress = false
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        // Combined state: Active if finger is down OR if we are in the "release" animation bridge
        let isPressed = configuration.isPressed || isAnimatingPress
        
        configuration.label
            // 1. DYNAMIC BORDER (The "Inner Stroke")
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? .white.opacity(isAnimatingPress ? 0.08 : 0.15)
                            : .clear,
                        lineWidth: 1.5
                    )
            )
            .scaleEffect(isPressed ? 0.96 : (isSelected ? 1.03 : 1.0))
            .brightness(isPressed ? -0.04 : 0)
            .shadow(
                color: colorScheme == .light
                    ? (isPressed ? Color.black.opacity(0.05) : (isSelected ? .black.opacity(0.18) : .black.opacity(0.1)))
                    : .clear,
                radius: isPressed ? 2 : (isSelected ? 10 : 6),
                x: 0,
                y: isPressed ? 1 : (isSelected ? 5 : 3)
            )
            // 💧 ASYMMETRIC SPRING:
            // Selection is "Heavy Liquid" (Damping 0.7)
            // Press is "High Tension" (Damping 0.85)
            .animation(.spring(response: 0.35, dampingFraction: isPressed ? 0.85 : 0.7), value: isPressed)
            .animation(.spring(response: 0.5, dampingFraction: 0.65), value: isSelected)
            
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
//                    HapticManager.shared.softImpactGenerator.prepare()
//                    HapticManager.shared.softImpact(intensity: 0.6)
                    isAnimatingPress = true
                } else {
                    // Slight delay to let the eye appreciate the "down" state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isAnimatingPress = false
                    }
                }
            }
    }
}
