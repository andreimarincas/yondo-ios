//
//  SceneBuilderView+Camera.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    @ViewBuilder
    func cameraSection() -> some View {
        VStack(alignment: .leading, spacing: LayoutConstants.headerToContentSpacing) {
            SectionHeader(title: "Camera")
            
            Picker("", selection: Binding(
                get: { viewModel.camera },
                set: { newValue in
                    HapticManager.shared.select()
                    viewModel.camera = newValue
                    viewModel.saveCurrentConfig()
                }
            ), content: {
                ForEach(CameraStyle.allCases) { cam in
                    Text(cam.title).tag(cam)
                }
            })
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            .padding(.horizontal, LayoutConstants.horizontalPadding)
        }
    }
}
