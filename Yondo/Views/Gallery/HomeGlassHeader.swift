//
//  HomeGlassHeader.swift
//  Yondo
//
//  Created by Andrei Marincas on 26.01.2026.
//

import SwiftUI

struct HomeGlassHeader: View {
    let scrollOffset: CGFloat
    let headerHeight: CGFloat
    let isHeroMode: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    
    // MARK: - Computed States
    private var upwardScroll: CGFloat { max(0, -scrollOffset) }
    
    private var isScrolled: Bool { scrollOffset < 0 }
    
    // Centralized animation math
    private var config: HeaderMetrics {
        HeaderMetrics(upwardScroll: upwardScroll, colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                liquidBackdrop(bgProgress: config.bgProgress)
                titleLabel
            }
            .frame(height: headerHeight)
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrolled)
    }
    
    // MARK: - Subviews
    @ViewBuilder
    private var titleLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Use safeAreaInsets.top to push content below the dynamic island/notch
            Spacer().frame(height: safeAreaInsets.top)
            
            HStack {
                Text("My Yondos")
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .tracking(-1.0)
                    .scaleEffect(config.textScale, anchor: .leading)
                    .offset(y: -config.liquidOffset)
                    .foregroundStyle(titleGradient)
                    // 💡 THE OVERLAY: Only applied in Light Mode
                    .overlay(alignment: .leading) {
                        if colorScheme == .light {
                            Text("My Yondos")
                                .font(.system(.largeTitle, design: .rounded).bold())
                                .tracking(-1.0)
                                .scaleEffect(config.textScale, anchor: .leading)
                                .offset(y: -config.liquidOffset)
                                // Use a tiny horizontal shift to thicken the vertical stems
                                // 💡 Dynamic thickness: gets slightly wider as it fades out
                                // to maintain legibility during the scroll.
                                .offset(x: 0.4 + (upwardScroll / 500))
                                .foregroundStyle(titleGradient)
                                .opacity(0.6)
                        }
                    }
                    .shadow(color: config.shadowColor, radius: 4, x: 0, y: 2)
                    .compositingGroup()
                    .opacity(config.textOpacity)
                    .blur(radius: (isScrolled && !isHeroMode) ? config.textBlur : 0)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: scrollOffset)
                    // Force the blur to "catch up" to the Hero dismissal
                    .animation(.spring(response: 0.25, dampingFraction: 1.0), value: isHeroMode)
                
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            
            Spacer().frame(height: 16)
        }
        // Hero Mode transitions grouped for clarity
        .opacity(isHeroMode ? 0 : 1)
        .scaleEffect(isHeroMode ? 0.9 : 1, anchor: .leading)
        .offset(y: isHeroMode ? -10 : 0)
        .blur(radius: isHeroMode ? 6 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isHeroMode)
    }
    
    private var titleGradient: LinearGradient {
        LinearGradient(
            // 🛑 CRITICAL: Small title is always white, so Large Title
            // MUST turn white here to maintain visual continuity
            // during the hand-off (blur/fade).
            colors: isScrolled ? [.white, .white.opacity(0.8)] : [.primary, .primary.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func liquidBackdrop(bgProgress: CGFloat) -> some View {
        LinearGradient(
            colors: [
                .black.opacity(0.8 * bgProgress),
                .black.opacity(0.4 * bgProgress),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Logic Refactoring (The "Math" Layer)
private struct HeaderMetrics {
    let bgProgress: CGFloat
    let textOpacity: CGFloat
    let textBlur: CGFloat
    let textScale: CGFloat
    let liquidOffset: CGFloat
    let shadowColor: Color
    
    init(upwardScroll: CGFloat, colorScheme: ColorScheme) {
        // 🛡️ ZERO-BASE: upwardScroll is derived from 'normalizedScrollOffset'.
        // It starts at 0 at the threshold and goes up.
        // Do NOT add a dead-zone here (e.g., - 8) or you will delay the
        // background fade relative to the status bar flip.
        let upwardScroll = max(0, upwardScroll)
        
        // Background reaches full 0.8 opacity over 40pt of 'effective' scroll.
        self.bgProgress = min(upwardScroll / 40, 1.0)
        
        // Text logic
        let fadeRange: CGFloat = (colorScheme == .light) ? 70 : 40
        self.textOpacity = max(1.0 - (upwardScroll / fadeRange), 0.0)
        
        // Starts blurring almost immediately (2pt) and hits max blur twice as fast (/ 5)
        // Math: (22pt - 2pt) / 5 = 4.0 (your max blur)
        self.textBlur = min(max(0, upwardScroll - 2) / 5, 4.0)
        
        self.textScale = max(1.0 - (upwardScroll / 800), 0.9)
        self.liquidOffset = upwardScroll * 0.45
        
        // Visuals
        let shadowAlpha = 0.15 * textOpacity
        self.shadowColor = (colorScheme == .light && upwardScroll > 16)
            ? .black.opacity(shadowAlpha)
            : .clear
    }
}

extension Font {
    static func precisionSystem(size: CGFloat, weight: CGFloat, design: Font.Design = .rounded) -> Font {
        let uiFont = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(weight))
        
        // Apply the rounded design trait if needed
        if let descriptor = uiFont.fontDescriptor.withDesign(design == .rounded ? .rounded : .default) {
            return Font(UIFont(descriptor: descriptor, size: size))
        }
        
        return Font(uiFont)
    }
}

extension ScenesHomeView {
    
    // MARK: - Glass Header
    
    var glassHeaderOverlay: some View {
        HomeGlassHeader(
            scrollOffset: normalizedScrollOffset,
            headerHeight: dynamicHeaderHeight,
            isHeroMode: isVisualHeroMode
        )
        .allowsHitTesting(false) // 👈 CRITICAL: This lets taps "pass through" to the toolbar buttons
    }
}
