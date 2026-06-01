//
//  CreateSceneFlowView.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.12.2025.
//

import SwiftUI
import UIKit

struct CreateSceneFlowView: View {
    @ObservedObject var viewModel: SceneBuilderViewModel
    @Environment(\.dismiss) private var dismiss // slides whole flow down

    @State private var camera = CameraModel()
    @State private var path = NavigationPath()
    @State private var lastPathCount = 0
    
    init(viewModel: SceneBuilderViewModel) {
        self.viewModel = viewModel
        Log.debug("🏗️ [FLOW] CreateSceneFlowView Instance Created. VM ID: \(viewModel.instanceID)")
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            SelfieView(
                camera: camera,
                onContinue: { image in
                    path.append(CreateSceneStep.builder(image: image))
                },
                onClose: {
                    dismiss()
                }
            )
            .navigationDestination(for: CreateSceneStep.self, destination: destinationView)
        }
        .preferredColorScheme(nil)
        .onAppear {
            Log.debug("🎬 [FLOW] CreateSceneFlowView Appeared.")
        }
        .onDisappear {
            SceneBuilderManager.shared.endFlowIfIdle()
            Log.debug("🛑 [FLOW] CreateSceneFlowView DISAPPEARED. Checking if VM is still active: \(viewModel.isGenerating)")
        }
        .onNavigationPop(path: $path, lastCount: $lastPathCount) {
            Log.debug("User navigated back")
            NotificationCenter.default.post(name: .didPopNavigationStep, object: nil)
        }
    }
    
    // MARK: - Navigation Router
    @ViewBuilder
    private func destinationView(for step: CreateSceneStep) -> some View {
        switch step {
        case .builder(let image):
            builderView(image: image)
        case .scene(let config, let selfie):
            sceneView(config: config, selfie: selfie)
        }
    }

    // MARK: - View Factories
    private func builderView(image: UIImage) -> some View {
        SceneBuilderView(
            viewModel: viewModel,
            selfieImage: image,
            onGenerate: { config, selfie in
                path.append(CreateSceneStep.scene(config: config, selfie: selfie))
            },
            onShowActiveGeneration: { selfie in
                let config = viewModel.lastGenerationConfig ?? viewModel.lastConfig
                path.append(CreateSceneStep.scene(config: config, selfie: selfie))
            },
            onClose: { dismiss() },
            onPop: {
                if !path.isEmpty {
                    path.removeLast()
                    Log.debug("SceneBuilderView popped")
                }
            }
        )
    }

    private func sceneView(config: SceneConfig, selfie: UIImage) -> some View {
        SceneView(
            viewModel: viewModel,
            config: config,
            selfieImage: selfie,
            onClose: { dismiss() }
        )
    }
}

enum CreateSceneStep: Hashable {
    case builder(image: UIImage)
    case scene(config: SceneConfig, selfie: UIImage)
}

extension Notification.Name {
    static let didPopNavigationStep = Notification.Name("didPopNavigationStep")
}
