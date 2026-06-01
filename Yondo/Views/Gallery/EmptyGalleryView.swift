//
//  EmptyGalleryView.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.02.2026.
//

import SwiftUI

struct EmptyGalleryView: View {
    @Environment(\.colorScheme) var colorScheme
    var onCreateTapped: (() -> Void)?
    @State private var isAnimating = false
    
    var body: some View {
        VStack {
            Spacer().frame(height: 50)
            
            // 1. The Ghost Icon
            ghostIcon
                // 🔑 Subtle rise for the icon
                .offset(y: isAnimating ? 0 : 40)
                .scaleEffect(isAnimating ? 1.0 : 0.7)
                .opacity(isAnimating ? 1 : 0)
            
            // 2. The Text
            headerText
                .offset(y: isAnimating ? 0 : 20)
                .opacity(isAnimating ? 1 : 0)
            
            // 3. Your Hero Button
            createButton
                .scaleEffect(isAnimating ? 1.0 : 0.5) // Pops from small to full size
                .offset(y: isAnimating ? 0 : 30)      // Glides up
                .opacity(isAnimating ? 1 : 0)         // Fades in
                // 🔑 The Button should be the last to arrive
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: isAnimating)
            
            Spacer().frame(height: 80)
        }
        .onAppear {
            // Icon & Text appear first with a snappy bounce
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var ghostIcon: some View {
        Image(systemName: "photo.stack.fill")
            .font(.system(size: 80)) // Upped size slightly
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .yondoInteractive,
                        .yondoAccent.opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(colorScheme == .dark ? 0.7 : 0.5) // Higher opacity for punch
            .shadow(color: .yondoInteractive.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 20)
            .padding(.bottom, 10)
    }
    
    private var headerText: some View {
        VStack(spacing: 8) {
            Text("No Yondos Yet")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
            
            Text("Start your collection by creating your first interactive scene.")
                .font(.subheadline).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil) // Allows unlimited lines
                .fixedSize(horizontal: false, vertical: true) // Forces vertical expansion
                .padding(.horizontal, 50)
        }
        .padding(.bottom, 40)
    }
    
    private var createButton: some View {
        Button {
            let start = CFAbsoluteTimeGetCurrent()
            Log.debug("🆔 [EmptyGallery] 🟢 Create button tapped")

            HapticManager.shared.mediumImpact()
            Log.debug("🆔 [EmptyGallery] 🔔 Haptic triggered (+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start))s)")

            onCreateTapped?()
            Log.debug("🆔 [EmptyGallery] 🚀 onCreateTapped finished (+\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start))s)")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .imageScale(.large)
                Text("Create New Yondo")
                    .font(.title3)
                    .fontDesign(.rounded)
                    .tracking(0.5) // Adds a high-end feel
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(YondoGlassButtonStyle())
    }
}
