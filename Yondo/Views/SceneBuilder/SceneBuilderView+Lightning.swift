//
//  SceneBuilderView+Lightning.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    @ViewBuilder
    func lightingSection() -> some View {
        VStack(alignment: .leading, spacing: LayoutConstants.headerToContentSpacing) {
            SectionHeader(title: "Lighting")
            
            Picker("", selection: Binding(
                get: { viewModel.lighting },
                set: { newValue in
                    HapticManager.shared.select()
                    viewModel.lighting = newValue
                    viewModel.saveCurrentConfig()
                }
            ), content: {
                ForEach(SceneLighting.allCases) { lighting in
                    Text(lighting.title).tag(lighting)
                }
            })
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            .padding(.horizontal, LayoutConstants.horizontalPadding)
        }
    }
}
