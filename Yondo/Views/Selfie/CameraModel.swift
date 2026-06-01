//
//  CameraModel.swift
//  Yondo
//
//  Created by Andrei Marincas on 20.12.2025.
//

import SwiftUI
import AVFoundation

@MainActor
@Observable
final class CameraModel {

    enum Status {
        case idle, unauthorized, running, failed
    }

    private(set) var status: Status = .idle
    private(set) var capturedImage: UIImage?
    private(set) var frozenFrame: UIImage?
    private(set) var previewSource: PreviewSource?
    
    private var captureService: CaptureService?
    private var currentCaptureId: UUID?
    
    private(set) var isCapturing = false
    
    func start() async {
        Log.debug("🚀 CameraModel start() called")
        
        // NEW: Clear any leftover frames from previous sessions immediately
        self.frozenFrame = nil
        
        // 1. Ensure the service and preview source exist
        if captureService == nil {
            Log.debug("🧱 Creating new CaptureService")
            let service = await CaptureService.make()
            self.captureService = service
            self.previewSource = service.previewSource
        } else {
            Log.debug("♻️ Reusing existing CaptureService")
        }
        
        // 2. Check authorization
        let authorized = await captureService?.isAuthorized ?? false
        Log.debug("🔐 Camera authorization status: \(authorized)")
        guard authorized else {
            status = .unauthorized
            Log.warning("🚫 Camera unauthorized")
            return
        }

        // 3. ALWAYS call service.start() if we are not already running
        // This wakes up the hardware even if the preview UI layer already exists
        do {
            try await captureService?.start()
            Log.debug("▶️ CaptureService started")
            status = .running
            Log.debug("✅ CameraModel status = running")
        } catch {
            status = .failed
            Log.error("❌ CameraModel failed to start: \(error)")
        }
    }

    func capturePhoto() async {
        Log.debug("🆔 [pending] 📸 capturePhoto() called")
        
        guard !isCapturing else {
            Log.debug("⚠️ capturePhoto ignored - already capturing")
            return
        }
        
        guard let service = captureService else {
            Log.error("❌ capturePhoto failed - captureService is nil")
            return
        }
        
        let captureId = UUID()
        currentCaptureId = captureId
        Log.debug("🆔 New captureId: \(captureId)")
        
        // Clear any existing frozen frame BEFORE setting isCapturing
        // This ensures we don't accidentally show an old frame via the UI
        self.frozenFrame = nil
        
        isCapturing = true
        
        Log.debug("🆔 [\(captureId)] 📸 Capture started (isCapturing = true)")
        defer {
            isCapturing = false
            Log.debug("🆔 [\(captureId)] 📸 Capture finished (isCapturing = false)")
        }
        
        // Add a tiny "safety" sleep if the session just started.
        // This gives the VideoDataOutput a chance to refresh its buffer.
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        if let rawFrame = await service.generateFrozenCGImage() {
            withAnimation(.snappy(duration: 0.15)) {
                self.frozenFrame = UIImage.fromCapturedCGImage(rawFrame, mirrorSelfie: true)
            }
        }
        Log.debug("🆔 [\(captureId)] 🧊 Frozen frame captured: \(frozenFrame != nil)")
        
        do {
            Log.debug("🆔 [\(captureId)] 📸 Awaiting photo capture from service")
            let photo = try await service.capturePhoto(captureId: captureId)
            Log.debug("🆔 [\(captureId)] 📸 Photo data received (size: \(photo.data.count) bytes)")
            
            if let uiImage = UIImage(data: photo.data), let cgImage = uiImage.cgImage {
                // SUCCESS: Assign the image.
                // We keep frozenFrame alive here for the smooth UI transition!
                let mirrored = UIImage.fromCapturedCGImage(cgImage, mirrorSelfie: true)
                capturedImage = mirrored
                Log.debug("🆔 [\(captureId)] 🖼️ CGImage successfully created and assigned")
            } else {
                // FAILURE: The data was corrupt and couldn't make an image.
                Log.error("🆔 [\(captureId)] ❌ Failed to create CGImage from photo data")
                frozenFrame = nil // 👈 FIX: Clear the freeze frame
            }
        } catch {
            // FAILURE: The camera hardware threw an error.
            Log.error("🆔 [\(captureId)] ❌ Photo capture failed: \(error)")
            frozenFrame = nil // 👈 FIX: Clear the freeze frame
        }
        
        // Important: Do NOT clear the frozenFrame here; the success path uses it for the UI transition!
        // If cleared here, the UI would "flash" back to the live camera for a split second before the
        // high-res image is rendered.
//        frozenFrame = nil
        
        Log.debug("🆔 [\(captureId)] ✅ Capture sequence complete")
    }
    
    /// Manually inject an image as if it was captured by the camera.
    /// Used for restoring a previously saved selfie.
    func setCapturedImage(_ image: UIImage) {
        Log.debug("🖼️ setCapturedImage called")
        capturedImage = image
        frozenFrame = nil
    }
    
    func resetCapturedPhoto() {
        Log.debug("🔁 resetCapturedPhoto called")
        capturedImage = nil
    }
    
    func resetFrozenFrame() {
        Log.debug("🔁 resetFrozenFrame called")
        frozenFrame = nil
    }

    func stop() async {
        Log.debug("🛑 CameraModel stop() called")
        await captureService?.stop()
        
        // Clear heavy assets from memory
        frozenFrame = nil
        
        // We keep the capturedImage so it's there if the user navigates back!
//        capturedImage = nil
        
        // DO NOT set previewSource = nil here.
        // Keeping it allows the UI to stay ready for when we restart.
//        previewSource = nil
    }
}
