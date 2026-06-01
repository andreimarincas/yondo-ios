//
//  PurchaseModalView+Title.swift
//  Yondo
//
//  Created by Andrei Marincas on 07.04.2026.
//

import SwiftUI

extension PurchaseModalView {
    var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buy Credits")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
            
            // Current credits with "Slot Machine" animation
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(displayedCredits)")
                    .font(.title.bold().monospacedDigit()) // Keeps '1' and '8' the same width
                    .foregroundColor(.yondoBrand)
                    .fontDesign(.rounded)
                    // CRITICAL: Tells SwiftUI this is a "new" view when the number changes
                    .id("credit_count_\(displayedCredits)") // Bind ID to the stable UI state
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                
                Text(iapManager.creditStore.credits == 1 ? "credit remaining" : "credits remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)
                    // Optional: Animate the label shift if the number width changes
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: iapManager.creditStore.credits)
            }
            // Clips the transition so the old number doesn't "float" outside the header area
            .clipped()
            // This tells the HStack to animate any internal changes (like the ID swap)
            // whenever the credits value changes.
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: iapManager.creditStore.credits)
            
            Text(boldYondo("1 credit = 1 Yondo"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fontDesign(.rounded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
    }
}
