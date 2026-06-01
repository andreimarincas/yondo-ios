//
//  SceneBuilderViewModel.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.12.2025.
//

import UIKit
import Combine
import SwiftUI
import SwiftData

@MainActor
/// ViewModel responsible for managing scene composition and AI image generation.
/// Handles user selections for destination, environment, mood, lighting, and camera.
/// Coordinates with AIImageGenerator and IAPManager for generating images and consuming credits.
final class SceneBuilderViewModel: ObservableObject {
    let instanceID = UUID().uuidString
    
    /// Currently selected scene properties
    @Published var destination: SceneDestination? = SceneConfig.default.destination
    @Published var environment: SceneEnvironment = SceneConfig.default.environment
    @Published var mood: SceneMood = SceneConfig.default.mood
    @Published var lighting: SceneLighting = SceneConfig.default.lighting
    @Published var camera: CameraStyle = SceneConfig.default.camera
    
    @Published var isGenerating = false
    
    /// Holds the generated AI image after successful generation
    @Published var generatedImage: UIImage?
    
    /// Holds the error if image generation fails
    @Published var generationError: SceneGenerationError?
    
    @Published private(set) var activeGenerationToken: GenerationToken? {
        didSet {
            let tokenDesc: String
            if let token = activeGenerationToken {
                tokenDesc = token.id.uuidString
            } else {
                tokenDesc = "nil"
            }
            Log.debug("SceneBuilderViewModel activeGenerationToken = \(tokenDesc)")
        }
    }
    
    let popularDestinations = SceneDestination.popular
    @Published private(set) var selectedExtraDestination: SceneDestination?
    
//    @FileBacked(filename: "lastSceneConfig.json", defaultValue: SceneConfig.default)
    private(set) var lastConfig: SceneConfig = .default
    
    private var generationTask: Task<Void, Never>?
    private(set) var messageRotationTask: Task<Void, Never>?
    
    @Published var cancelEnabled = true
    
    // Dependencies
    private let useCase: SceneGenerationUseCase
    let iapProvider: CreditProvider
    private let imageStore: ImageStoring
    let shieldManager: SyncShielding
    let syncHealingController: SyncHealingController
    let syncService: SyncService
    
    @Published var cancelCountdown: Int = 5
    
    let generationManager = GenerationHistoryManager.shared
    
    private let generatingMessages = [
        "Analyzing local light physics…",      // Step 1: Understand the destination
        "Mapping your digital presence…",      // Step 2: Understand the user
        "Weaving molecular realism…",          // Step 3: The "Magic" happens
        "Anchoring atmospheric shadows…",      // Step 4: Physical grounding
        "Refining cinematic depth… ✨",        // Step 5: The "Polish"
        "Synchronizing your arrival…",         // Step 6: Finalizing
        "Almost there…"                        // Step 7: The "Hang tight"
    ]
    
    private let initialGeneratingMessage = "Initializing synthesis engine…"
    
    @Published var currentMessage: String
    
    private(set) var lastGenerationSelfie: UIImage?
    private(set) var lastGenerationConfig: SceneConfig?
    
    @Published var saveFailedButDeliveredAlert: Bool = false
    @Published var isSceneViewVisible: Bool = false
    
    var lastHeroID: SceneDestination.ID?
    
    var destinationsToShow: [SceneDestination]
    
    private var cancellables = Set<AnyCancellable>()
    
    init(
        useCase: SceneGenerationUseCase,
        modelContainer: ModelContainer,
        iapProvider: CreditProvider? = nil,
        imageStore: ImageStoring? = nil,
        shieldManager: SyncShielding? = nil,
        syncService: SyncService? = nil
    ) {
        Log.debug("SceneBuilderViewModel INIT: \(instanceID)")
        Log.debug("SceneBuilderViewModel: Restoring lastConfig and selectedExtraDestination")
        
        self.destinationsToShow = self.popularDestinations
        
        self.useCase = useCase
        
        Log.debug("⚡ Initializing iapProvider")
        self.iapProvider = iapProvider ?? IAPManager.shared
        Log.debug("✅ iapProvider assigned")
//        Log.debug("✅ iapProvider initialized: \(self.iapProvider)")
        
        self.syncService = syncService ?? FirebaseSyncService.shared
        self.shieldManager = shieldManager ?? SyncShieldManager.shared
        self.syncHealingController = SyncHealingController(iapProvider: self.iapProvider, syncService: self.syncService)
        
        Log.debug("⚡ Initializing imageStore")
        self.imageStore = imageStore ?? ImageStore.shared
        Log.debug("✅ imageStore assigned")
//        Log.debug("✅ imageStore initialized: \(self.imageStore)")
        
        self.currentMessage = initialGeneratingMessage
        
        // Restore persisted config on init
//        Log.debug("⚡ Accessing lastConfig for restoration")
//        let config = lastConfig
//        Log.debug("✅ lastConfig assigned")
////        Log.debug("✅ lastConfig accessed: \(config)")
//        if let destination = config.destination, !destination.isPopular {
//            selectedExtraDestination = destination
//        }
//        self.destination = config.destination
//        Log.debug("SceneBuilderViewModel: destination restored")
////        Log.debug("SceneBuilderViewModel: destination restored: \(String(describing: self.destination))")
//        self.environment = config.environment
//        Log.debug("SceneBuilderViewModel: environment restored")
//        self.mood = config.mood
//        Log.debug("SceneBuilderViewModel: mood restored")
//        self.lighting = config.lighting
//        Log.debug("SceneBuilderViewModel: lighting restored")
//        self.camera = config.camera
//        Log.debug("SceneBuilderViewModel: camera restored")
        
//        Log.debug("SceneBuilderViewModel: environment=\(environment), mood=\(mood), lighting=\(lighting), camera=\(camera)")
        
        Log.debug("SceneBuilderViewModel: setupSyncObservers() start")
        self.setupSyncObservers()
        Log.debug("SceneBuilderViewModel: setupSyncObservers() completed")
        
        Log.debug("SceneBuilderViewModel INIT DONE: \(instanceID)")
        Log.debug("SceneBuilderViewModel: fully initialized and ready")
    }
    
    deinit {
        Log.debug("SceneBuilderViewModel DEINIT: \(instanceID)")
        messageRotationTask?.cancel()
    }
    
    var isActive: Bool {
        guard let task = generationTask, !task.isCancelled else {
            return false
        }
        return true
    }
    
    var isSyncing: Bool {
        return generationError?.isSyncing ?? false
    }
    
    func setSelectedExtraDestination(_ destination: SceneDestination?) {
        selectedExtraDestination = destination
        destinationsToShow = popularDestinations + (destination.map { [$0] } ?? [])
    }
    
    /// Applies the visual presets associated with a destination.
    /// Triggered only on explicit user tap.
    func applyPresets(for destination: SceneDestination) -> Bool {
        let oldConfig = buildConfig()
        defer { saveCurrentConfig() }
        
        // 1. Force environment if current one isn't allowed
        if !destination.allowedEnvironments.contains(environment) {
            withAnimation(.snappy) {
                environment = destination.allowedEnvironments.first ?? environment
            }
        }
        
        withAnimation(.snappy) {
            mood = destination.recommendedMood
        }
        
        // 2. Apply the "Vibe" (Mood, Lighting, Camera)
        // We use a spring animation so the sliders move smoothly in the UI
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            lighting = destination.recommendedLighting
            camera = destination.recommendedCamera
        }
        
        let newConfig = buildConfig()
        let hasChanged = newConfig != oldConfig
        return hasChanged
    }
    
    /// Clears the current destination selection
    func clearDestination() {
        destination = nil
        restorePresetsIfNeeded(keepSnapshot: true)
        saveCurrentConfig()
    }
    
    /// Builds a SceneConfig object from the current selections
    /// - Returns: SceneConfig representing current selections
    func buildConfig() -> SceneConfig {
        SceneConfig(
            environment: environment,
            mood: mood,
            lighting: lighting,
            camera: camera,
            destination: destination
        )
    }
    
    /// Persists the current configuration to lastConfig
    func saveCurrentConfig() {
        lastConfig = buildConfig()
    }
    
    func generateScene(selfie: UIImage, config: SceneConfig) {
        Log.debug("🚀 Starting new generation with config: \(config)")
        
        self.lastGenerationSelfie = selfie
        self.lastGenerationConfig = config
        
        generationTask = Task { @MainActor
            [weak self, iapProvider, useCase, generationManager, shieldManager, syncService] in
            
            // --- STEP 1: THE GRACE PERIOD ---
            let gracePeriodSucceeded = await self?.runGracePeriodTimer() ?? false
            Log.debug("⏳ Grace period finished. Success: \(gracePeriodSucceeded)")
            
            // If user cancelled during those 5 seconds, exit here.
            guard gracePeriodSucceeded, !Task.isCancelled else { return }
            
            // --- STEP 2: THE COMMITMENT POINT ---
            // 🛡️ Lock the sync listener before taking the credit
            let transactionID = shieldManager.startTransaction()
            
            // Generate a UI-specific identity for this generation attempt
            let token = GenerationToken()
            
            // Lock the UI and take the credit BEFORE the network call
            Log.debug("🧱 [\(token.id.uuidString.prefix(8))] Point of No Return: Locking UI and consuming credit.")
            
            self?.cancelEnabled = false
            Log.debug("🔒 Cancel disabled. Committing to generation.")
            
            self?.activeGenerationToken = token
            
            defer {
                generationManager.cleanupIfFinalized(token)
            }
            
            do {
                Log.debug("🧬 [\(token.id.uuidString.prefix(8))] Generation Loop Started. Active Token: \(self?.activeGenerationToken?.id.uuidString.prefix(8) ?? "None")")
                
                try await useCase.generateScene(
                    selfie: selfie,
                    config: config
                ) { [token, selfie, config] stage in
                    guard !Task.isCancelled else { return }
                    self?.handleSceneGenerationStage(stage, token: token, selfie: selfie, config: config)
                }
                
                guard !Task.isCancelled else { return }
                
                // ✅ SUCCESS PATH
                
                // 1. ALWAYS drop the shield for this specific transaction.
                // It succeeded, so we trash the stale buffer to prevent inflation.
                shieldManager.stopTransaction(id: transactionID)
                await syncService.flushBuffers()
                
                // 2. Only update the UI state if the user is still waiting for THIS specific image.
                self?.finalizeGeneration(for: token)
                
            } catch is CancellationError {
                Log.debug("🚫 Task caught cancellation: UI already reset by cancelGeneration()")
                
                // 🛡️ PARALLEL-SAFE REFUND:
                // We check the Manager to see if a credit record was committed for THIS specific token.
                // If a record exists, the credit was taken, so we must trigger a silent refund
                // regardless of whether this is the currently 'active' UI generation.
                let recordExists = generationManager.hasCommittedRecord(for: token)
                
                if recordExists {
                    Log.debug("⚠️ Committed Task [\(token)] cancelled. Triggering silent refund.")
                    
                    // We committed but then got cancelled (e.g. system interrupt).
                    // We refund, so the buffer is now "Correct" again.
                    // Use a detached Task to ensure the refund happens even if this scope dies.
                    Task.detached { [generationManager, iapProvider, shieldManager, token, transactionID] in
                        Log.debug("🚑 [\(token.id.uuidString.prefix(8))] Detached Refund Task started.")
                        do {
                            // The manager handles the state check internally to ensure we don't refund twice.
                            try await generationManager.refundIfUndelivered(token, creditProvider: iapProvider)
                            Log.debug("✅ [\(token.id.uuidString.prefix(8))] Detached Refund Success.")
                            
                            // Stop shield and immediately flush buffers to grab the latest economy data
                            await shieldManager.stopTransaction(id: transactionID)
                            await shieldManager.clearBypass()
                            await syncService.flushBuffers()
                        } catch {
                            Log.error("🚨 [\(token.id.uuidString.prefix(8))] Detached Refund Failed: \(error)")
                        }
                    }
                } else {
                    // Cancelled before consumption (Grace period)
                    Log.debug("ℹ️ Task [\(token.id.uuidString.prefix(8))] cancelled before commitment. No record found.")
                    shieldManager.stopTransaction(id: transactionID)
                }
                
                Log.debug("Task caught cancellation: UI cleanup skipped to preserve transition.")
            } catch {
                // ERROR RECOVERY PATH
                Log.error("❌ Generation failed: \(error.localizedDescription)")
                
                // 🛑 handleGenerationError handles the UI alert and triggers a refund if necessary.
                // Once refunded, the buffer (old balance) is correct again.
                await self?.handleGenerationError(error, token: token, transactionID: transactionID)
            }
        }
    }
    
    /// Maps domain-level generation events to UI state updates and history tracking.
    func handleSceneGenerationStage(
        _ stage: SceneGenerationStage,
        token: GenerationToken,
        selfie: UIImage,
        config: SceneConfig
    ) {
        switch stage {
        case .creditConsumed:
            // Safe to start loading text rotation now that payment is confirmed.
            generationManager.addRecord(token: token, config: config, selfie: selfie)
            startMessageRotation()
            
        case .imageReceived(let image):
            // Only render the image if the user hasn't navigated away or started a new request
            if token == activeGenerationToken && isSceneViewVisible {
                withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
                    generatedImage = image
                    isGenerating = false
                }
                generationManager.markImageGenerated(token, image: image)
            }
            
        case .localSaveSuccess:
            // Confirm persistence. This updates the history record regardless of UI visibility.
            generationManager.markSaved(token)
            
        case .localSaveFailed(let error):
            if let saveError = error as? ImageStoreError {
                // Check if image was delivered to the UI
                if token == activeGenerationToken && isSceneViewVisible && generatedImage != nil {
                    // Image reached SceneView, but save failed → trigger alert
                    saveFailedButDeliveredAlert = true
                }
                generationManager.markSaveError(token, error: saveError)
            }
        }
    }
    
    func prepareForNewGeneration() {
        Log.debug("SceneBuilderViewModel: prepareForNewGeneration() called")
        generatedImage = nil
        generationError = nil
        isGenerating = true
        cancelEnabled = true
        cancelCountdown = 5
        currentMessage = initialGeneratingMessage
        saveFailedButDeliveredAlert = false
    }
    
    private func runGracePeriodTimer() async -> Bool {
        for i in (1...5).reversed() {
            if Task.isCancelled { return false }
            self.cancelCountdown = i
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        self.cancelCountdown = 0
        return true
    }
    
    private func startMessageRotation() {
        currentMessage = generatingMessages[0]
        messageRotationTask = Task { [weak self] in
            guard let self else { return }
            for i in 1..<generatingMessages.count {
                try? await Task.sleep(nanoseconds: 7_500_000_000)
                guard !Task.isCancelled, self.isGenerating else { break }
                self.currentMessage = self.generatingMessages[i]
            }
        }
    }

    func finalizeGeneration(for token: GenerationToken, withError error: SceneGenerationError? = nil) {
        // 1. IDENTITY CHECK: The Ultimate Gatekeeper
        guard self.activeGenerationToken == token else {
            Log.debug("👻 Ghost Task Prevented: finalizeGeneration ignored for stale token [\(token.id.uuidString.prefix(8))]")
            return
        }
        
        Log.debug("🏁 Finalizing generation [\(token.id.uuidString.prefix(8))]. Cleaning up state.")
        
        // 2. ATOMIC STATE UPDATE
        self.generationError = error
        self.isGenerating = false
        self.cancelEnabled = false
        self.cancelCountdown = 0
        self.generationTask = nil
        self.messageRotationTask?.cancel()
        self.activeGenerationToken = nil
        
        // 3. SAFE SHIELD RESET
        // Because of the guard above, we know we are only dropping
        // the shield if the CURRENT session is ending.
        shieldManager.clearBypass()
    }
    
    @discardableResult
    /// Cancels the current image generation task if possible.
    /// - Parameter force: Force cancel even if cancelEnabled is false
    func cancelGeneration(force: Bool = false, userInitiated: Bool = true) -> Bool {
        Log.debug("🛑 cancelGeneration(force=\(force), userInitiated=\(userInitiated)) on VM: \(instanceID), isGenerating: \(isGenerating), cancelEnabled: \(cancelEnabled)")
        
        // Guard check
        guard force || (isGenerating && cancelEnabled) else { return false }
        
        // Kill the main generation task
        if userInitiated {
            generationTask?.cancel()
        }
        generationTask = nil
        
        messageRotationTask?.cancel()
        messageRotationTask = nil
        
        // KILL THE SYNC HEALING TASK
        // This triggers the 'catch' block in the Task, which resets the bypass shield
        // and ensures no zombie UI updates happen.
        syncHealingController.cancel()
        
        // Reset UI States explicitly
        isGenerating = false
        cancelEnabled = false // Ensure the button hides/disables immediately
        currentMessage = generatingMessages[0]
        activeGenerationToken = nil
        
        // Ensure shield is reset (Double-safety)
        // In case the task wasn't running or the catch block is delayed.
        shieldManager.clearBypass()
        
        return true
    }
    
    func teardownWaitingState() {
        Log.debug("Cleanup: User navigated away. Cancelling sync timers.")
        
        // Explicitly kill the timer so it doesn't wake up and mess with the NEW generation
        // This triggers the 'catch' block in the Task, which triggers the shield reset.
        syncHealingController.cancel()
        
        // Wipe the slate clean
        // This sets isGenerating = false, kills the token, resets the bypass shield,
        // and makes the floating button on the home screen disappear.
//        self.finalizeGeneration()
        
        // Clear the error so the next time they enter, it's fresh
        // Only do this if you want the user to see the setup screen again
        // without any leftover "Insufficient Credits" alerts.
        self.generationError = nil
    }
    
    // MARK: 🔹 Snapshot used only during destination selection
    private var presetSnapshot: PresetSnapshot?

    struct PresetSnapshot {
        let environment: SceneEnvironment
        let mood: SceneMood
        let lighting: SceneLighting
        let camera: CameraStyle
    }

    /// Manages temporary snapshot of environment/mood/lighting/camera during destination selection
    func snapshotPresetsIfNeeded() {
        Log.debug("SceneBuilderViewModel: snapshotPresetsIfNeeded() called")
        guard presetSnapshot == nil else {
            Log.debug("SceneBuilderViewModel: snapshot already exists, skipping")
            return
        }

        presetSnapshot = PresetSnapshot(
            environment: environment,
            mood: mood,
            lighting: lighting,
            camera: camera
        )
    }

    /// Manages temporary snapshot of environment/mood/lighting/camera during destination selection
    func restorePresetsIfNeeded(keepSnapshot: Bool = false) {
        Log.debug("SceneBuilderViewModel: restorePresetsIfNeeded(keepSnapshot=\(keepSnapshot)) called")
        guard let snapshot = presetSnapshot else {
            Log.debug("SceneBuilderViewModel: no snapshot to restore, skipping")
            return
        }

        environment = snapshot.environment
        mood = snapshot.mood
        lighting = snapshot.lighting
        camera = snapshot.camera
        
        if !keepSnapshot {
            presetSnapshot = nil
        }
        
        saveCurrentConfig()
    }

    /// Manages temporary snapshot of environment/mood/lighting/camera during destination selection
    func clearPresetSnapshot() {
        Log.debug("SceneBuilderViewModel: clearPresetSnapshot() called")
        presetSnapshot = nil
    }
}

extension SceneBuilderViewModel {
    
    private func setupSyncObservers() {
        /*
        iapProvider.creditStore.creditsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] newCount in
                guard let self = self else { return }
                
                // If we are actively healing, let the Task handle the UI.
                // Stand down and do not cancel the task!
                guard self.generationError != .syncingCredits && self.syncHealingTask == nil else {
                    Log.debug("🤫 Publisher ignoring credit update because Sync Healing is in progress.")
                    return
                }
                
                Log.debug("✨ UI Heal: Received updated credit count (\(newCount)).")
                
                // Transition to Decision Room (InsufficientCredits state shows the UI)
                self.generationError = .insufficientCredits
                
                // Kill the 8s safety timer since reality has arrived
//                self.syncHealingTask?.cancel()
//                self.syncHealingTask = nil
            }
            .store(in: &cancellables)
        
        // Watch for Premium Sync Completion
        iapProvider.creditStore.premiumPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isUnlocked in
                guard let self = self else { return }
                guard self.generationError == .syncingPremiumUnlock else { return }
                Log.debug("🎯 UI Heal: Premium unlocked.")
                
                // Transition to Decision Room (InsufficientCredits state shows the UI)
                self.generationError = .requiresPremiumUnlock(destinationName: nil)
                
                // Kill the 8s safety timer since reality has arrived
                self.syncHealingTask?.cancel()
                self.syncHealingTask = nil
            }
            .store(in: &cancellables)
        */
    }
}
