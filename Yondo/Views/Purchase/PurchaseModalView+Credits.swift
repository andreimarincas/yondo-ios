//
//  PurchaseModalView+Credits.swift
//  Yondo
//
//  Created by Andrei Marincas on 07.04.2026.
//

import SwiftUI

extension PurchaseModalView {
    var creditsProductsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(PurchaseType.allCases.filter { $0.isConsumable }.enumerated()), id: \.element) { index, type in
                if let product = iapManager.products[type] {
                    PurchaseButton(
                        product: product,
                        isPurchasing: iapManager.purchasingProductID == product.id,
                        isSuccess: shouldShowSuccessBadge(for: product.id),
                        isEnabled: !isInteractionDisabled,
                        statusBadge: getStatusBadge(for: product.id),
                        action: {
                            handlePurchase(for: type, productID: product.id)
                        }
                    )
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    // STAGGER LOGIC:
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .scaleEffect(
                        x: hasAppeared ? 1.0 : 1.0,
                        y: hasAppeared ? 1.0 : 0.95,
                        anchor: .center
                    )
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.04),
                        value: hasAppeared
                    )
                }
            }
        }
        .padding(.bottom, 8)
        .onAppear {
            displayedCredits = iapManager.creditStore.credits
            
            // Trigger the entrance
            // A 0.05s delay is invisible to the user but
            // makes the animation much more reliable.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Log.debug("🎭 PMV: Credits section entrance animation triggered.")
                hasAppeared = true
            }
        }
    }
}
