//
//  LetterboxOverlay.swift
//  Yondo
//
//  Created by Andrei Marincas on 16.02.2026.
//

import SwiftUI

struct LetterboxOverlay: View {
    var opacity: CGFloat = 0.35

    var body: some View {
        GeometryReader { geo in
            let previewAspect: CGFloat = 3 / 4 // front camera portrait feel
            let screenAspect = geo.size.width / geo.size.height

            let barHeight: CGFloat = {
                if screenAspect < previewAspect {
                    let previewHeight = geo.size.width / previewAspect
                    return max((geo.size.height - previewHeight) / 2, 0)
                } else {
                    return 0
                }
            }()

            VStack(spacing: 0) {
                Color(red: 0.05, green: 0.05, blue: 0.1, opacity: opacity)
                    .frame(height: barHeight)

                Spacer()

                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1, opacity: opacity),
                        Color(red: 0.05, green: 0.05, blue: 0.1, opacity: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: barHeight)
                    
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
