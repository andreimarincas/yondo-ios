//
//  PurchaseModalView+Error.swift
//  Yondo
//
//  Created by Andrei Marincas on 07.04.2026.
//

import SwiftUI

extension PurchaseModalView {
    var loadingView: some View {
        VStack(spacing: 0) {
            YondoSpinner(size: .large, style: colorScheme == .dark ? .subtle : .system)
                .frame(height: 60) // Matches error icon frame
                .padding(.bottom, 8)
                .offset(y: -16)
            
            // 2. Main Title (Matches Error Title Style/Alignment)
            VStack(spacing: 8) {
                Text("Connecting to App Store...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fontDesign(.rounded)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300, alignment: .top) // Consistent height/alignment
        .padding(.top, 32) // Nudge to account for the Title Section above it
    }
    
    func errorView(_ error: Error) -> some View {
        VStack(spacing: 0) { // Set spacing to 0 and use internal padding for precision
            let isOffline: Bool = {
                // Check if it's your custom StoreError wrapper
                if let storeError = error as? StoreError,
                   case .networkIssue(let underlyingError) = storeError {
                    return isRootErrorOffline(underlyingError)
                }
                // Check if it's a direct network error
                return isRootErrorOffline(error)
            }()
            let isRegional = (error as? StoreError) == .emptyRegion
            
            // 1. Icon Section
            VStack(spacing: 16) {
                // Dynamic Icon
                Image(systemName: isOffline ? "wifi.slash" : (isRegional ? "mappin.and.ellipse" : "wifi.exclamationmark"))
                    .font(.system(size: 44))
                    .fontDesign(.rounded)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        Color.yondoAccent, // 1. Exclamation Mark becomes the "Hot" color
                        // Use the same ghostly opacity as SceneView
                        colorScheme == .light ? Color.primary.opacity(0.2) : Color.primary.opacity(0.4) // 2. Waves become "Ghostly"
                    )
                    .frame(height: 60)
                    .offset(y: -8)
                    .symbolEffect(.pulse, options: .repeating, value: animateIcon)
                    .symbolEffect(.bounce, value: iapManager.loadingState) // Bounces once whenever the state changes to Error
                    .onAppear { animateIcon.toggle() }
                
                // 2. Text Section
                VStack(spacing: 16) {
                    // Dynamic Title
                    Text(isOffline ? "No Internet Connection" : (isRegional ? "Region Not Supported" : "Store Unavailable"))
                        .font(.headline)
                        .foregroundColor(.primary)
                        .fontDesign(.rounded)
                    Text("Please check your connection and try again to view available products.")
                        .font(.subheadline) // Match SceneView subheadline
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                        .lineLimit(3)
                        // Add this to ensure the layout engine reserves enough space
                        // for multi-line text, matching the SceneView's density.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 24) // Match the SceneView internal padding
            
            SecondaryActionButton(
                title: isRegional ? "Check Again" : "Try Again",
                isEnabled: !isInteractionDisabled,
                minWidth: 130,
                action: {
                    guard iapManager.loadingState != .loading else { return }
                    Log.debug("🎭 PMV: User manually tapped 'Try Again' button.")
                    HapticManager.shared.lightImpact()
                    Task { await iapManager.retryFetch() }
                }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300, alignment: .top)
    }
}
