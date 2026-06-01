//
//  PurchaseModalView+Premium.swift
//  Yondo
//
//  Created by Andrei Marincas on 07.04.2026.
//

import SwiftUI

extension PurchaseModalView {
    var premiumDestinationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explore More")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            
            Text("Premium destinations include Tokyo, Dubai, and Cappadocia.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fontDesign(.rounded)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Premium Destinations Unlock Product
            if let product = iapManager.products[.premiumDestinations] {
                let consumablesCount = iapManager.numberOfConsumableProducts
                PurchaseButton(
                    product: product,
                    isPurchasing: iapManager.purchasingProductID == product.id,
                    isSuccess: shouldShowSuccessBadge(for: product.id),
                    isEnabled: !iapManager.creditStore.premiumDestinationsUnlocked && !isInteractionDisabled,
                    statusBadge: getStatusBadge(for: product.id),
                    action: {
                        guard !iapManager.creditStore.premiumDestinationsUnlocked else { return }
                        Log.debug("🎭 PMV: 🛒 Tapped non-consumable purchase: \(product.id)")
                        handlePurchase(for: .premiumDestinations, productID: product.id)
                    }
                )
                .disabled(iapManager.creditStore.premiumDestinationsUnlocked)
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .scaleEffect(
                    x: hasAppeared ? 1.0 : 1.0,
                    y: hasAppeared ? 1.0 : 0.95,
                    anchor: .center
                )
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.75)
                    .delay(Double(consumablesCount) * 0.04),
                    value: hasAppeared
                )
                
                Text(boldYondo("You still need credits to generate Yondos."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)
                    .padding(.leading, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(iapManager.creditStore.premiumDestinationsUnlocked ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: iapManager.creditStore.premiumDestinationsUnlocked)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
