//
//  SceneBuilderManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 05.01.2026.
//

import SwiftData

@MainActor
final class SceneBuilderManager {

    static let shared = SceneBuilderManager()

    private(set) var viewModel: SceneBuilderViewModel?
    
    private var modelContainer: ModelContainer?
    
    // 1. Make this a lazy property or a var that is initialized on demand
    private var _generator: AIImageGenerator?
    
    private var generator: AIImageGenerator {
        if let existing = _generator { return existing }
        // By the time this is called (startFlow), Firebase will be ready
        let firebaseAIGenerator = FirebaseAIResultGenerator()
        _generator = firebaseAIGenerator
        return firebaseAIGenerator
    }
    /*
    // Designated initializer that accepts a generator explicitly.
    private init(generator: AIImageGenerator) {
        self._generator = generator
    }

    // Convenience initializer that constructs the default generator on the main actor.
    private convenience init() {
//        let defaultGenerator = OpenAIDALLEResultGenerator(apiKey: Secrets.openAIKey)
//        let defaultGenerator = OpenAIDALLEResultGenerator(
//            apiKey: Secrets.openAIKey,
//            apiClient: APIClient(enableCaching: true),
//            imagePreprocessor: ImagePreprocessor()
//        )
        
        let mockGenerator = MockAIImageGenerator()
//        mockGenerator.duration = .seconds(8)
//        mockGenerator.shouldSucceed = false
        self.init(generator: mockGenerator)
        
//        let firebaseAIGenerator = FirebaseAIResultGenerator()
//        self.init(generator: firebaseAIGenerator)
    }
    */
    func setup(with container: ModelContainer) {
        self.modelContainer = container
    }

    func startFlow() -> SceneBuilderViewModel {
        Log.debug("🛠️ SceneBuilderManager: startFlow() called")
        if let existing = viewModel {
            Log.debug("🛠️ SceneBuilderManager: Returning existing viewModel")
            return existing
        }
        
        guard let container = modelContainer else {
            fatalError("SceneBuilderManager must be set up with a ModelContainer before starting flow.")
        }
        
        let persistence = SceneGenerationPersistenceService(modelContainer: container)
        let useCase = SceneGenerationService(
            generator: generator,
            iapProvider: IAPManager.shared,
            persistence: persistence,
            imageStore: ImageStore.shared
        )
        let vm = SceneBuilderViewModel(
            useCase: useCase,
            modelContainer: container,
            imageStore: ImageStore.shared
        )
        viewModel = vm
        Log.debug("🛠️ SceneBuilderManager: New SceneBuilderViewModel created and assigned")
        return vm
    }

    func endFlowIfIdle() {
        Log.debug("🛠️ SceneBuilderManager: endFlowIfIdle() called")
        guard let vm = viewModel else { return }

        // Only release if no generation is running
        if vm.isActive == false {
            Log.debug("🛠️ SceneBuilderManager: viewModel released (idle)")
            viewModel = nil
        }
    }

    func forceEndFlow() {
        Log.debug("🛠️ SceneBuilderManager: forceEndFlow() called")
        viewModel?.cancelGeneration(force: true, userInitiated: false)
        viewModel = nil
        Log.debug("🛠️ SceneBuilderManager: viewModel forcefully released")
    }
}
