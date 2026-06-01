//
//  CaptureService.swift
//  Yondo
//
//  Created by Andrei Marincas on 20.12.2025.
//

import Foundation
@preconcurrency import AVFoundation
import Combine
import CoreImage

actor CaptureService {
    
    let previewSource: PreviewSource
    
    private let session: AVCaptureSession
    private let photoOutput = AVCapturePhotoOutput()
    
    private var photoDelegates = [PhotoCaptureDelegate]()
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoDelegate: VideoOutputDelegate?
    private(set) var latestFrame: CIImage?
    
    // The stream of frames
    private(set) var frameStream: AsyncStream<CIImage>?
    private var frameTask: Task<Void, Never>?
    
    private let sessionQueue = DispatchQueue(label: "com.yondo.camera.sessionQueue")
    
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    func generateFrozenCGImage() -> CGImage? {
        guard let ciImage = latestFrame else { return nil }
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    private init(session: AVCaptureSession, previewSource: PreviewSource) {
        self.session = session
        self.previewSource = previewSource
        
        Task { @MainActor in
            Log.debug("CaptureService initialized with previewSource")
            Log.debug("🎥 CaptureService init - session: \(ObjectIdentifier(session))")
        }
        
        // Add to your Task block in init
        NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { _ in
            Log.warning("⚠️ AVCaptureSession was interrupted")
        }

        NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { _ in
            Log.debug("✅ AVCaptureSession interruption ended")
            // Potentially call start() again
        }
    }
    
    deinit {
        // Since it's an actor, you can't easily call async code here,
        // but you can ensure references are cleared if the actor is destroyed.
        latestFrame = nil
    }

    static func make() async -> CaptureService {
        let session = await MainActor.run {
            AVCaptureSession()
        }

        let previewSource = await MainActor.run {
            DefaultPreviewSource(session: session)
        }
        
        Log.debug("🏗️ CaptureService.make() created session and previewSource")

        return CaptureService(
            session: session,
            previewSource: previewSource
        )
    }
    
    // MARK: - Authorization
    var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            
            Task { @MainActor in
                Log.debug("🔐 AVCaptureDevice authorizationStatus: \(status.rawValue)")
            }
            
            if status == .notDetermined {
                return await AVCaptureDevice.requestAccess(for: .video)
            }
            return status == .authorized
        }
    }

    // MARK: - Session lifecycle
    func start() async throws {
        Task { @MainActor in
            Log.debug("🚀 CaptureService start() called")
        }
        
        guard await isAuthorized else {
            Log.warning("🚫 start() aborted - not authorized")
            return
        }
        
        guard !session.isRunning else {
            Log.debug("⚠️ start() ignored - session already running")
            return
        }

        try await configureSession()
        Log.debug("⚙️ Session configured")
        
        // 👈 FIX: Always ensure the frame stream is running even if the session was already configured
        if frameTask == nil || frameTask?.isCancelled == true {
            await setupFrameProcessing()
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak session] in
                guard let session = session else {
                    continuation.resume()
                    return
                }
                if !session.isRunning {
                    session.startRunning()
                    Log.debug("▶️ AVCaptureSession.startRunning() called")
                }
                continuation.resume()
            }
        }
        
        // Apply selfie zoom AFTER session is running
//        await applySelfieZoom()
    }
    
    func stop() {
        Log.debug("🛑 CaptureService stop() called")
        
        // 1. Cancel the consumer task immediately
        frameTask?.cancel() // Kill the frame listener
        Log.debug("🧵 frameTask cancelled")
        frameTask = nil
        
        // CRITICAL: Clear the buffer so the next session doesn't "inherit" it
        self.latestFrame = nil
        
        // 2. Hop to MainActor to finish the stream and clear the delegate
        let delegate = self.videoDelegate
        Task { @MainActor in
            Log.debug("🧹 Finishing frame stream")
            delegate?.continuation?.finish()
            delegate?.continuation = nil
        }
        
        // 🚨 FIX 3: Route stopRunning through the EXACT SAME serial queue.
        // If startRunning is currently executing, this will wait in line.
        sessionQueue.async { [weak session] in
            guard let session = session else { return }
            if session.isRunning {
                session.stopRunning()
                Log.debug("⏹️ AVCaptureSession stopped")
            }
        }
    }
    
    // MARK: - Configuration
    private func configureSession() async throws {
        Log.debug("⚙️ configureSession() called")
        guard session.inputs.isEmpty else {
            Log.debug("⚠️ configureSession skipped - inputs already exist")
            return
        }
        
        // 🚨 FIX: Do all ASYNC setup BEFORE calling beginConfiguration()
        // Create delegate on the main actor to satisfy MainActor isolation
        let delegate: VideoOutputDelegate = await MainActor.run { VideoOutputDelegate() }
        Log.debug("🎞️ VideoOutputDelegate created")
        
        self.videoDelegate = delegate
        await setupFrameProcessing() // Initialize the stream and the listener
        Log.debug("🧵 Frame processing pipeline set up")
        
        // Dedicated queue for the video frames (keep this off main)
        let frameQueue = DispatchQueue(label: "com.yondo.camera.frameQueue", qos: .userInteractive)
        
        await MainActor.run {
            // Always set delegate before adding to session
            videoOutput.setSampleBufferDelegate(delegate, queue: frameQueue)
            Log.debug("🎞️ SampleBufferDelegate set")
        }
        
        // --- NO `await` CALLS ALLOWED BELOW THIS LINE ---
        
        session.beginConfiguration()
        
        // This ensures that even if an error is thrown during setup,
        // the session doesn't stay in a "frozen" configuration state.
        defer { session.commitConfiguration() }
        
        session.sessionPreset = .photo
        Log.debug("📷 Session preset set to .photo")

        // 1. Device Setup: Front camera only
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .front)
        else {
            throw CameraError.setupFailed
        }
        Log.debug("📱 Front camera device acquired")
        
        // 2. Input Setup
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.addInputFailed
        }
        session.addInput(input)
        Log.debug("➕ Input added to session")
        
        // 3. Photo Output
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.addOutputFailed
        }
        session.addOutput(photoOutput)
        Log.debug("📸 PhotoOutput added to session")
        
        // 4. Video Output
        if session.canAddOutput(videoOutput) {
            
            // Video settings: ensure efficient pixel format
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            
            session.addOutput(videoOutput)
            Log.debug("➕ VideoOutput added to session")
            
            // 5. Ensure correct orientation for the video data connection
            if let connection = videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(0) {
                        connection.videoRotationAngle = 0 // Portrait
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                Log.debug("📐 Video orientation configured")
            }
        }
    }
    
    private func setupFrameProcessing() async {
        Log.debug("🧵 setupFrameProcessing() called")
        
        // Cancel any existing task
        frameTask?.cancel()
        Log.debug("🧵 Previous frameTask cancelled")

        // Create the stream
        let (stream, continuation) = AsyncStream<CIImage>.makeStream()
        Log.debug("🌊 AsyncStream for frames created")
        self.frameStream = stream
        
        // Inject the continuation into the delegate
        if let delegate = videoDelegate {
            await MainActor.run {
                delegate.continuation = continuation
                Log.debug("🔗 Continuation assigned to VideoOutputDelegate")
            }
        }

        // Create ONE task to consume the stream
        frameTask = Task { [weak self] in
            Log.debug("🧵 Frame consumer task started")
            for await image in stream {
                // Check for cancellation to stop processing immediately if needed
                if Task.isCancelled { break }
                #if DEBUG
                Log.debug("🖼️ Frame received in stream")
                #endif
                await self?.updateLatestFrame(image)
            }
        }
    }
    
    private func updateLatestFrame(_ image: CIImage) {
        self.latestFrame = image
    }
    
    private func applySelfieZoom() async {
        await MainActor.run {
            guard
                let deviceInput = session.inputs
                    .compactMap({ $0 as? AVCaptureDeviceInput })
                    .first,
                deviceInput.device.position == .front
            else { return }

            let device = deviceInput.device

            do {
                try device.lockForConfiguration()

                let desiredZoom: CGFloat = 1.3
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 2.0)

                device.videoZoomFactor = min(desiredZoom, maxZoom)

                device.unlockForConfiguration()
            } catch {
                Log.error("Failed to apply selfie zoom", error)
            }
        }
    }

    // MARK: - Photo capture
    /// Captures a photo asynchronously, returning a `Photo` object.
    ///
    /// This method uses a delegate to handle the capture process and retains the delegate until capture finishes to ensure the continuation is resumed properly.
    func capturePhoto(captureId: UUID) async throws -> Photo {
        Task { @MainActor in
            Log.debug("🆔 [\(captureId)] 📸 CaptureService.capturePhoto() called")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Log.debug("🆔 [\(captureId)] ⚙️ Creating AVCapturePhotoSettings")
            let settings = AVCapturePhotoSettings()
            
            Task { @MainActor in
                let delegate = PhotoCaptureDelegate(continuation: continuation, captureId: captureId)
                Log.debug("🆔 [\(captureId)] 📸 PhotoCaptureDelegate created and stored")
                
                // Retain delegate until capture finishes
                await self.storeDelegate(delegate)
                
                // Cleanup when done
                delegate.onFinish = { [weak self, weak delegate] in
                    Log.debug("🆔 [\(captureId)] 🧹 PhotoCaptureDelegate finished, removing")
                    guard let self, let delegate else { return }
                    Task { @MainActor in
                        await self.removeDelegate(delegate)
                    }
                }
                
                Log.debug("🆔 [\(captureId)] 📸 photoOutput.capturePhoto triggered")
                // Perform the capture on the main actor
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

extension CaptureService {
    /// Stores a photo capture delegate to retain it during capture.
    func storeDelegate(_ delegate: PhotoCaptureDelegate) {
        photoDelegates.append(delegate)
        Log.debug("📦 Delegate stored (count: \(photoDelegates.count))")
    }
    
    /// Removes a photo capture delegate after capture completes.
    func removeDelegate(_ delegate: PhotoCaptureDelegate) {
        if let index = photoDelegates.firstIndex(of: delegate) {
            photoDelegates.remove(at: index)
            Log.debug("📦 Delegate removed (count: \(photoDelegates.count))")
        }
    }
}

/// Delegate for handling video frame output from the camera.
/// Receives sample buffers and converts them to CGImage, then calls `onFrame` callback.
final class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // A continuation to yield frames into the AsyncStream
    var continuation: AsyncStream<CIImage>.Continuation?
    
    private var frameCounter = 0
    
    // Initialize once with high-performance options
//    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // 👈 FIX: Yield the cheap CIImage instantly, do not render the CGImage here!
        let ciImage = CIImage(cvImageBuffer: buffer)
        continuation?.yield(ciImage)
    }
    
    /*func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: buffer)
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            #if DEBUG
            frameCounter += 1
            if frameCounter % 10 == 0 {
                Log.debug("🎞️ Video frame received")
            }
            #endif
            
            // Yield the frame to the stream instead of a callback
            continuation?.yield(cgImage)
        }
    }*/
}

typealias PhotoContinuation = CheckedContinuation<Photo, Error>

/// Delegate for handling photo capture callbacks.
/// Ensures the continuation is resumed exactly once with the captured photo or an error.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<Photo, Error>
    private let captureId: UUID
    private var didResume = false
    
    /// Callback to remove delegate when done
    var onFinish: (() -> Void)?
    
    init(continuation: CheckedContinuation<Photo, Error>, captureId: UUID) {
        self.continuation = continuation
        self.captureId = captureId
    }
    
    /// Resumes the continuation once with the given result.
    /// Prevents multiple resumes.
    private func resumeOnce(with result: Result<Photo, Error>) {
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success(let photo):
            Log.debug("🆔 [\(captureId)] 📸 Resuming continuation with photo")
            continuation.resume(returning: photo)
        case .failure(let error):
            Log.debug("🆔 [\(captureId)] ❌ Resuming continuation with error")
            continuation.resume(throwing: error)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { onFinish?() }
        
        if let error {
            Log.error("🆔 [\(captureId)] ❌ Photo capture failed: \(error)")
            Log.debug("🆔 [\(captureId)] ❌ Resuming continuation with error")
            resumeOnce(with: .failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            resumeOnce(with: .failure(PhotoCaptureError.noPhotoData))
            return
        }
        Log.debug("🆔 [\(captureId)] 📸 Photo captured, size: \(data.count) bytes")
        Log.debug("🆔 [\(captureId)] 📸 Resuming continuation with photo")
        resumeOnce(with: .success(Photo(data: data)))
    }
    
    // Handle deferred photo capture (optional)
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        if let error {
            resumeOnce(with: .failure(error))
        }
        // No-op if already handled in didFinishProcessingPhoto
        onFinish?()
    }
}
