//
//  SelfieView.swift
//  Yondo
//
//  Created by Andrei Marincas on 19.12.2025.
//

import SwiftUI

struct SelfieView: View {
    @State var camera: CameraModel
    @State private var showCapturedPhoto = false
    @State private var showFaceGuide = false
    
    // Last selfie support
    @State private var lastSelfieThumbnail: UIImage?
    @State private var usingStoredSelfie = false
    
    @State private var isButtonUIVisible = true
    @State private var isProcessingAction = false
    
    let onContinue: (UIImage) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            // We keep the CameraPreview alive in the ZStack at all times.
            // 1. Destroying/re-creating the preview (e.g. via if/else) causes a ~200ms
            //    main-thread block while AVFoundation re-binds the session to the layer.
            // 2. By keeping it always present, 'Retake' becomes an instantaneous
            //    UI toggle rather than a hardware re-initialization.
            if let source = camera.previewSource {
                CameraPreview(source: source)
                    .ignoresSafeArea()
                
                // THE LIVE OVERLAYS (Face Guide / Frozen Frame)
                if let frozen = camera.frozenFrame {
                    GeometryReader { geo in
                        Image(uiImage: frozen)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: geo.size.width, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }
                
                if showFaceGuide {
                    FaceGuideOverlay()
                        .transition(.scale(scale: 1.1).combined(with: .opacity)) // For the initial appearance in .task
                        .opacity(camera.frozenFrame == nil ? 1.0 : 0.0)  // For hiding during capture
                        .animation(.yondoSnappy, value: camera.frozenFrame)
                }
            }
            
            // THE FINAL CAPTURED IMAGE LAYER
            // When showCapturedPhoto becomes false, this will fade out because of .transition(.opacity)
            if let image = camera.capturedImage {
                // The captured image simply covers the camera preview up when available.
                GeometryReader { geo in
                    Image(uiImage: image)
                      .resizable()
                      .scaledToFill()
                      .frame(maxWidth: geo.size.width, maxHeight: .infinity)
                      .ignoresSafeArea()
                      .blur(radius: showCapturedPhoto ? 0 : 10) // Fades from blurry to sharp
                      .scaleEffect(showCapturedPhoto ? 1.0 : 1.05) // Subtle "zoom in" effect
                }
                // Bind opacity directly to the state.
                // It will automatically animate because the state change is wrapped in `withAnimation`.
                .opacity(showCapturedPhoto ? 1.0 : 0.0)
            }
            
            LetterboxOverlay(opacity: 0.4)
            
            VStack {
                Spacer()
                
                ZStack {
                    // --- BRANCH A: REVIEW MODE ---
                    if showCapturedPhoto {
                        HStack(spacing: 16) {
                            retakeButton
                            Spacer()
                            continueButton
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 80)
                        .padding(.bottom, 35)
                        // Apply transition to the actual moving container
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                        .id("ReviewModeUI")
                        .allowsHitTesting(showCapturedPhoto && !isProcessingAction)
                    }
                    
                    // --- BRANCH B: CAPTURE MODE ---
                    else {
                        ZStack {
                            captureButtonContainer
                            lastSelfieButtonContainer
                        }
                        .transition(.opacity)
                        .id("CaptureModeUI")
                        .allowsHitTesting(!showCapturedPhoto && !isProcessingAction)
                    }
                }
                // CRITICAL: This animation ensures the ZStack handles the swap smoothly
                .animation(.spring(duration: 0.3, bounce: 0), value: showCapturedPhoto)
            }
        }
        .task(priority: .userInitiated) {
            // Always unlock the UI when the view becomes active/visible
            isProcessingAction = false
            
            Log.debug("🤳 SelfieView appeared")
            
            // 0. Load from disk on appearance
            if let thumbnail = await LastSelfieStore.shared.loadThumbnail() {
                // We are already on the MainActor because SelfieView is a View,
                // so we can just assign it.
                self.lastSelfieThumbnail = thumbnail
                Log.debug("🖼️ Thumbnail loaded and assigned")
            }
            
            // 1. Start camera immediately
            await camera.start()
            
            // 2. If we are returning from the next screen (showing a photo),
            // we wait a tiny bit for the camera to actually warm up,
            // then fade back to live mode.
            if showCapturedPhoto {
                // Optional: Small delay to ensure camera.start() has finished
                // and the preview layer is ready behind the image.
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCapturedPhoto = false
                } completion: {
                    camera.resetCapturedPhoto()
                }
            }
            
            // 3. Only perform the "Intro Fade" if we aren't already in a good state
            // If showFaceGuide is already true, we've probably been here before.
            if !showFaceGuide {
                try? await Task.sleep(nanoseconds: 150_000_000) // Slightly shorter sleep
                withAnimation(.easeIn(duration: 0.2)) {
                    showFaceGuide = true
                    isButtonUIVisible = true
                }
            }
        }
        .onDisappear {
            Task {
                Log.debug("🛑 SelfieView disappearing - stopping camera")
                await camera.stop()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .yondoToolbarStyle()
                }
                .tint(.primary)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
        .allowsHitTesting(!isProcessingAction)
        .onChange(of: camera.isCapturing) { _, isCapturing in
            if isCapturing {
                isButtonUIVisible = false
            } else {
                // If capture just finished, wait 0.1s to bridge the "flash gap"
                // before checking if we should show the button again.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !camera.isCapturing && !showCapturedPhoto {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isButtonUIVisible = true
                        }
                    }
                }
            }
        }
        .onChange(of: showCapturedPhoto) { _, isReviewing in
            if isReviewing {
                withAnimation(.easeOut(duration: 0.2)) {
                    isButtonUIVisible = false
                }
            } else {
                // Tapping 'Retake' is a UI action, not a hardware one.
                // We can show the button IMMEDIATELY so it fades in with the transition.
                if !camera.isCapturing {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isButtonUIVisible = true
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var captureButtonContainer: some View {
        VStack {
            Spacer()
            
            ZStack {
                Button {} label: {
                    Color.clear
                        .frame(width: 80, height: 80)
                        .padding(.horizontal, -12)
                        .padding(.vertical, -7)
                }
                .buttonStyle(.glass)
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .frame(width: 80, height: 80)
                
                if camera.isCapturing {
                    WormSpinner(size: .extraLarge, style: .ghost)
                        .frame(width: 80, height: 80)
                        .transition(.opacity)
                }
                
                captureButton
            }
            .padding(.bottom, 35)
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .opacity.combined(with: .scale(scale: 0.9))
            ))
        }
    }
    
    @ViewBuilder
    private var lastSelfieButtonContainer: some View {
        // We only check if the thumbnail exists.
        // The main if/else block already handles hiding this during review mode.
        if lastSelfieThumbnail != nil {
            VStack {
                Spacer()
                
                ZStack {
                    HStack(alignment: .center) {
                        lastSelfieButton
                        Spacer()
                    }
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                }
                .padding(.bottom, 35)
            }
            .opacity(isButtonUIVisible ? 1.0 : 0.0)
            .allowsHitTesting(isButtonUIVisible)
        }
    }
    
    @ViewBuilder
    private var retakeButton: some View {
        Button {
            guard !isProcessingAction else { return }
            isProcessingAction = true
            
            Log.debug("🔄 Retake tapped - resetting photo")
            HapticManager.shared.lightImpact()
            
            // 1. Animate the UI toggle first
            withAnimation(.easeInOut(duration: 0.25)) {
                showCapturedPhoto = false
                usingStoredSelfie = false
            } completion: {
                // 2. Only clear the underlying data AFTER the fade-out completes
                camera.resetCapturedPhoto()
                camera.resetFrozenFrame()
                isProcessingAction = false
                Log.debug("🔁 Data cleared, returning to live camera preview")
            }
        } label: {
            Text("RETAKE")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
        }
    }
    
    @ViewBuilder
    private var continueButton: some View {
        if let image = camera.capturedImage {
            Button {
                guard !isProcessingAction else { return }
                isProcessingAction = true
                
                Log.debug("➡️ Continue tapped (usingStoredSelfie: \(usingStoredSelfie))")
                HapticManager.shared.mediumImpact()
                
                Task {
                    if usingStoredSelfie {
                        Log.debug("📂 Loading stored selfie for continue")
                        if let image = await LastSelfieStore.shared.loadSelfie() {
                            onContinue(image)
                        } else {
                            Log.warning("⚠️ Stored selfie expected but not found")
                            isProcessingAction = false
                        }
                    } else {
                        // Save only if freshly captured
                        Log.debug("💾 Saving freshly captured selfie")
                        try await LastSelfieStore.shared.clear()
                        
                        Task(priority: .utility) {
                            Log.debug("💾 Background save of selfie started")
                            // Since LastSelfieStore saveSelfie is a disk-based operation, it's fine to
                            // let it finish in the background. Pass the uiImage directly to the next view.
                            try? await LastSelfieStore.shared.saveSelfie(image)
                        }
                        
                        // Move the user to the next screen immediately
                        onContinue(image)
                    }
                }
            } label: {
                Text("CONTINUE")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    @ViewBuilder
    private var captureButton: some View {
        Button {
            guard !isProcessingAction else { return }
            isProcessingAction = true
            
            Log.debug("📸 Capture button tapped")
            
            HapticManager.shared.impact(style: .rigid)
            usingStoredSelfie = false
            
            Task {
                Log.debug("📸 Triggering camera capture")
                // Set this immediately so the UI knows we are in "Review Mode"
                // even while the high-res image is still processing.
                await camera.capturePhoto()
                Log.debug("📸 Capture finished, image available: \(camera.capturedImage != nil)")
                
                // Only switch the UI state if the capture was successful
                // NOTE: showCapturedPhoto must only be set AFTER the await finishes.
                // Since camera.capturePhoto is @MainActor, the moment it finishes and
                // returns here, the 'capturedImage' is already set and 'frozenFrame'
                // is cleared. SwiftUI batches these changes into a single frame update,
                // preventing a "flash" of the live camera feed.
                if camera.capturedImage != nil {
                    Log.debug("📸 Capture successful, switching to review mode")
                    withAnimation(.spring(duration: 0.25, bounce: 0)) {
                        showCapturedPhoto = true
                    } completion: {
                        camera.resetFrozenFrame()
                        isProcessingAction = false
                    }
                } else {
                    Log.error("❌ Capture failed, remaining in live preview")
                    camera.resetFrozenFrame()
                    // Optional: Trigger a failure haptic here so the user knows it failed
                    HapticManager.shared.failure()
                    isProcessingAction = false
                }
            }
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: 68, height: 68)
                // This subtle grey stroke makes the white circle feel "physical"
                // and premium, similar to the high-end Apple shutter button.
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .scaleEffect(camera.isCapturing ? 0.93 : 1.0)
                .animation(.easeOut(duration: 0.1), value: camera.isCapturing)
        }
        .buttonStyle(CameraShutterButtonStyle())
        .disabled(camera.isCapturing)
        .contentTransition(.symbolEffect)
    }
    
    @ViewBuilder
    private var lastSelfieButton: some View {
        if let thumbnail = lastSelfieThumbnail {
            Button {
                guard !isProcessingAction else { return }
                isProcessingAction = true
                
                Log.debug("🖼️ Last selfie tapped")
                usingStoredSelfie = true
                
                Task {
                    if let image = await LastSelfieStore.shared.loadSelfie() {
                        Log.debug("🖼️ Applying stored selfie to camera state")
                        // Wrap this in animation so the image fades in and the
                        // buttons swap smoothly
                        withAnimation(.easeInOut(duration: 0.25)) {
                            camera.setCapturedImage(image)
                            showCapturedPhoto = true
                        } completion: {
                            isProcessingAction = false
                        }
                        
                        Log.debug("🖼️ Switching to captured photo preview (stored)")
                    } else {
                        Log.warning("⚠️ Stored CGImage selfie not found")
                        isProcessingAction = false
                        usingStoredSelfie = false
                    }
                }
            } label: {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    // 1. Make the image slightly smaller than the 52x52 button
                    // This creates a 2pt "glass rim" around the photo
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    // Inner subtle shadow to give the photo depth inside the rim
                    .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                    // The "Glass Rim" highlight
                    .padding(.horizontal, -11)
                    .padding(.vertical, -6)
            }
            .buttonStyle(.glass) // Your custom glass style behind the image
            .environment(\.colorScheme, .dark)
            .frame(width: 52, height: 52)
            .clipShape(Circle()) // Clip the glass background itself
            .allowsHitTesting(!isProcessingAction && !showCapturedPhoto)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                removal: .opacity
            ))
        }
    }
}

struct FaceGuideOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.65
            let height = width * 1.3

            Ellipse()
                .strokeBorder(
                    Color.white.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: width, height: height)
                .position(x: geo.size.width / 2,
                          y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct CameraShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The magic happens here:
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            // Use a snappy spring for a "mechanical" feel
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticManager.shared.select()
                    // Pre-warm the haptics as soon as the finger goes down
                    HapticManager.shared.rigidGenerator.prepare()
                }
            }
    }
}
