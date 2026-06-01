//
//  SectionHeader.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    struct SectionHeader: View {
        let title: String
        
        var body: some View {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold)) // Bold + Rounded
                .padding(.leading, SceneBuilderView.LayoutConstants.horizontalPadding) // Matches the ScrollView padding
                .foregroundColor(.primary)
                .padding(.top, 8) // Give the "Liquid" elements room to breathe
        }
    }
}
