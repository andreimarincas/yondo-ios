//
//  ImageStore.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import UIKit
import Combine

enum ImageStoreError: Error {
    case encodingFailed
    case saveFailed(Error)
}

// REMOVE @MainActor from here to allow nonisolated properties to exist naturally
final class ImageStore: ObservableObject, ImageStoring {
    
    static let shared = ImageStore()
    static let priorityLoadingCount = 18 // TODO: Calculate dynamically based on screen size?
    
    // MARK: - 1. UI-bound properties specifically as @MainActor
    
    // Single source of truth. Always kept sorted by createdAt DESC.
    @MainActor @Published private(set) var entries: [GeneratedImage] = []
    
    @MainActor @Published var hasLoadedInitialData = false
    
    let didAddNewImage = PassthroughSubject<GeneratedImage, Never>()
    
    // MARK: - 2. Dependencies - These are now naturally nonisolated
    
    private let fileService = ImageFileService()
    
    // ConcurrentImageCache is thread-safe; allow cross-actor access
    nonisolated private let cache = ConcurrentImageCache()
    
    private let thumbnailSize = CGSize(width: 512, height: 512)
    
    @MainActor private var migrationTask: Task<Void, Never>?
    
    private(set) var initTask: Task<Void, Never>?
    
    private(set) var activeUserId: String
    
    /// Indicates if the store is currently renaming the physical folder on disk (e.g., "local" to "permanentUID").
    ///
    /// While `hasLoadedInitialData` is perfect for showing generic loading skeletons in the UI, `isMigrating`
    /// can be used to explicitly freeze the app with a global blocker/spinner if:
    ///   1. You want to prevent the user from deleting or saving new images *while* the OS is moving the folder.
    ///   2. Your UI is currently rendering the image grid and you want to prevent a momentary APFS filesystem read error.
    @MainActor @Published private(set) var isMigrating = false
    
    private init() {
        self.activeUserId = FirebaseAuthService.shared.currentUID ?? "local"
        configureCache()
    }
    
    func initialize() {
        guard self.initTask == nil else {
            Log.debug("📁 ImageStore: ⚠️ Initialization already in progress. Ignoring duplicate call.")
            return
        }

        Log.debug("📁 ImageStore: initialize() called")
        Log.debug("📁 ImageStore: 🏁 Spawning main initialization Task.")

        self.initTask = Task {
            Log.debug("📁 ImageStore: loadInitialIndex() begin")
            await loadInitialIndex()
            Log.debug("📁 ImageStore: loadInitialIndex() finished")

            let currentEntries = await MainActor.run { entries }
            if !currentEntries.isEmpty {
                Log.debug("📁 ImageStore: 🚀 Index verified with \(currentEntries.count) items. Dispatching prewarmCache routine.")
                prewarmCache(priorityCount: Self.priorityLoadingCount, limit: 24)
            } else {
                Log.debug("📁 ImageStore: ℹ️ No stored images found. Skipping prewarmCache.")
            }
        }
    }
    
    func waitForReady() async {
        if initTask == nil {
            Log.error("📁 ImageStore: ❌ waitForReady() called but initialize() was never spawned!")
//            initialize()
        }
        await initTask?.value
    }
    
    func updateIdentity(newUserId: String) async {
        Log.debug("📁 ImageStore: updateIdentity() called")
        guard newUserId != activeUserId else { return }
        Log.debug("📁 ImageStore: 👤 Identity shifting from [\(activeUserId)] to [\(newUserId)].")

        // Block UI interactions globally
        await MainActor.run { self.isMigrating = true }

        // Ensure we clear the flag no matter how the method exits (success or throw)
        defer {
            Task { @MainActor in self.isMigrating = false }
        }

        // 1. Wait for any current setups to finish so we don't corrupt memory
        Log.debug("📁 ImageStore: waiting for initTask")
        _ = await initTask?.value
        Log.debug("📁 ImageStore: initTask finished")

        // 2. 🚚 MIGRATION: If they were offline ("local") and now have a real UID,
        // we must move their offline files to the new permanent folder.
        if activeUserId == "local" {
            Log.debug("📁 ImageStore: 🚚 Migrating offline 'local' files to permanent UID [\(newUserId)].")
            await fileService.migrateDirectory(fromUserId: "local", toUserId: newUserId)
        }

        // 3. Update the lock and clear memory
        self.activeUserId = newUserId

        Log.debug("📁 ImageStore: clearing in-memory state")
        await MainActor.run {
            self.entries.removeAll()
            self.cache.removeAllObjects()
            self.hasLoadedInitialData = false
        }

        // 4. Respawn the Initialization Task for the new ID
        Log.debug("📁 ImageStore: spawning new initTask")
        self.initTask = Task {
            Log.debug("📁 ImageStore: [new identity] loadInitialIndex() begin")
            await loadInitialIndex()
            Log.debug("📁 ImageStore: [new identity] loadInitialIndex() finished")

            let currentEntries = await MainActor.run { entries }
            if !currentEntries.isEmpty {
                prewarmCache(priorityCount: Self.priorityLoadingCount, limit: 24)
            }
        }

        // 5. Wait for the new identity to finish loading
        await self.initTask?.value
    }
    
    nonisolated private func configureCache() {
        Log.debug("🧠 ImageStore: Configuring ConcurrentImageCache limits. Limit: 200 items, Cost: 300MB.")
        cache.countLimit = 200
        cache.totalCostLimit = 300 * 1024 * 1024 // 300MB
    }
    
    // MARK: - Public Actions
    // MARK: 3. Methods that update UI state MUST be @MainActor
    
    @MainActor
    func save(image: UIImage, withId explicitID: UUID? = nil) async throws -> GeneratedImage {
        let id = explicitID ?? UUID()
        let userId = self.activeUserId
        let filename = "\(id.uuidString).jpg"
        let entry = GeneratedImage(id: id, filename: filename, createdAt: Date())
        let thumbSize = self.thumbnailSize
        
        // 1. Move heavy processing OFF the Main Actor
        // We use a detached task or a nonisolated helper to ensure this doesn't block the UI
        let (jpegData, thumbImage, thumbData) = try await Task.detached(priority: .userInitiated) {
            guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
                throw ImageStoreError.encodingFailed
            }
            
            let thumb = await ThumbnailGenerator.generate(from: image, size: thumbSize)
            let tData = thumb.jpegData(compressionQuality: 0.7)
            
            return (jpeg, thumb, tData)
        }.value

        // 2. Back on Main Actor: Disk I/O (Actor-safe via fileService)
        try await fileService.saveImage(jpegData, filename: filename, userId: userId)
        if let td = thumbData {
            try await fileService.saveThumbnail(td, filename: filename, userId: userId)
        }
        
        // 3. Update State (Pre-sorted insertion)
        // Since we know the new image is the 'newest', we insert at 0
        // to maintain the createdAt DESC order without a full sort.
        self.entries.insert(entry, at: 0)
        cache.setObject(thumbImage, forKey: id.uuidString)
        
        // Persist the index
        try await fileService.saveIndex(entries, userId: userId)
        didAddNewImage.send(entry)
        
        return entry
    }
    
    @MainActor
    func delete(entry: GeneratedImage) {
        let userId = self.activeUserId
        
        // Remains sorted after removal
        entries.removeAll(where: { $0.id == entry.id })
        cache.removeObject(forKey: entry.id.uuidString)
        
        Task(priority: .background) {
            await fileService.delete(filename: entry.filename, userId: userId)
            try? await fileService.saveIndex(entries, userId: userId) // Persist removal
        }
    }
    
    @MainActor
    func deleteAll() {
        Log.debug("🧹 ImageStore: ☢️ deleteAll() triggered. Wiping index, memory cache, and filesystem.")
        let userId = self.activeUserId
        entries.removeAll()
        cache.removeAllObjects()
        Task(priority: .background) { await fileService.nukeAllData(userId: userId) }
    }
    
    // MARK: - Loading & Prewarming
    
    // The "Fast Lane" check (No MainActor hop)
    nonisolated func thumbnail(for entry: GeneratedImage) -> UIImage? {
        // This hits the lock in ConcurrentImageCache and returns immediately
        if let cached = cache.object(forKey: entry.id.uuidString) {
            return cached
        }
        return nil // Don't block UI; let the view trigger the async load
    }
    
    @MainActor
    func loadThumbnail(for entry: GeneratedImage, allowGeneration: Bool = true, forceGeneration: Bool = false) async -> UIImage? {
        let userId = self.activeUserId
        
        if !forceGeneration {
            if let cached = thumbnail(for: entry) { return cached }
            
            // Load from disk
            if let data = await fileService.loadThumbnailData(filename: entry.filename, userId: userId),
               let image = UIImage(data: data) {
                cache.setObject(image, forKey: entry.id.uuidString)
                return image
            }
        }
        
        // Fallback: Regenerate from full image (Slow path)
        if allowGeneration || forceGeneration {
            let url = await fileService.getFullImageURL(filename: entry.filename, userId: userId)
            if let restoredThumb = ThumbnailGenerator.generateFromURL(url, maxPixelSize: Int(thumbnailSize.width)) {
                cache.setObject(restoredThumb, forKey: entry.id.uuidString)
                
                // Save repaired thumbnail to disk for next time
                if let data = restoredThumb.jpegData(compressionQuality: 0.7) {
                    try? await fileService.saveThumbnail(data, filename: entry.filename, userId: userId)
                }
                return restoredThumb
            }
        }
        
        return nil
    }
    
    @MainActor
    func loadFullImage(for entry: GeneratedImage) async -> UIImage? {
        let userId = self.activeUserId
        
        // 1. Fetch raw data from actor
        guard let data = try? await fileService.loadImageData(filename: entry.filename, userId: userId) else { return nil }
        
        // 2. Offload decoding to a background thread
        return await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            
            // This force-decodes the image into a bitmap buffer on the background thread
            return image.preparingForDisplay()
        }.value
    }
    
    @MainActor
    func prewarmCache(priorityCount: Int = 12, limit: Int = 24) {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            Log.debug("🔋 ImageStore: 🛑 Skipping prewarmCache because Low Power Mode is enabled.")
            return
        }
        
        let batch = Array(entries.prefix(limit))
        let maxConcurrentTasks = 4 // 🛡️ Keep disk I/O and CPU overhead low
        let priorityCount = min(entries.count, priorityCount)
        
        Log.debug("🚀 ImageStore: ⏳ Prewarming cache. Limit: \(limit) total items, \(priorityCount) high-priority items.")
        
        Task(priority: .userInitiated) { // Higher priority for launch prewarming
            // 1. PHASE ONE: The "UI Gatekeepers" (Items 1-12)
            // We load these in a small, fast parallel group.
            // This fulfills the UI's 12-item requirement as fast as the SSD allows.
            // This guarantees they hit the cache before the rest of the tasks saturate the queue.
            let priorityBatch = batch.prefix(priorityCount)
            
            await withTaskGroup(of: Void.self) { group in
                for entry in priorityBatch {
                    group.addTask {
                        _ = await self.loadThumbnail(for: entry)
                    }
                }
            }
            
            try? await Task.sleep(for: .milliseconds(50)) // Let the Main Actor process the UI reveal
            
            // 2. PHASE TWO: The "Scroll Buffer" (Items 13-24)
            // Now that the UI is "Ready", we load the rest more politely
            // so we don't lag the reveal animation.
            let remainingBatch = batch.dropFirst(priorityCount)
            
            await withTaskGroup(of: Void.self) { group in
                for (index, entry) in remainingBatch.enumerated() {
                    // If we've hit our concurrency limit, wait for one to finish
                    if index >= maxConcurrentTasks {
                        await group.next()
                    }
                    group.addTask {
                        _ = await self.loadThumbnail(for: entry)
                    }
                }
            }
            
            Log.debug("✅ ImageStore: 🏁 Prewarming of \(batch.count) items finished.")
        }
    }
    
    // MARK: - Private Setup
    
    @MainActor
    private func loadInitialIndex() async {
        Log.debug("📂 ImageStore: loadInitialIndex() started")
        let userId = self.activeUserId
        let entries: [GeneratedImage]
        let needsSave: Bool

        Log.debug("📂 ImageStore: Attempting to pull index for user [\(userId)]...")

        if let loaded = await fileService.loadIndex(userId: userId) {
            Log.debug("📂 ImageStore: Index pulled from disk successfully.")
            entries = loaded //Array(loaded[...5])
            needsSave = false
        } else {
            Log.error("📂 ImageStore: ⚠️ Index missing or corrupted! Forcing filesystem directory rebuild scan for user [\(userId)]...")
            // Index missing: Service rebuilds and handles its own sorting
            entries = await fileService.rebuildIndexFromDisk(userId: userId)
            needsSave = !entries.isEmpty
        }

//        entries = await fileService.rebuildIndexFromDisk(userId: userId)
//        needsSave = true

        Log.debug("📂 ImageStore: publishing entries to MainActor")
        // Use the MainActor to ensure these hit the UI in the same frame
        await MainActor.run {
            self.entries = entries
            self.hasLoadedInitialData = true
        }
        Log.debug("📂 ImageStore: state published")

        Log.debug("📂 ImageStore: 🚀 Hydrated state. Verifiable on-disk images: \(entries.count). UI state marked hasLoadedInitialData = true.")

        if needsSave {
            Log.debug("📂 ImageStore: 💾 Saving rebuilt index snapshot back to disk.")
            // Persist the newly rebuilt index
            try? await fileService.saveIndex(entries, userId: userId)
        }
        Log.debug("📂 ImageStore: loadInitialIndex() completed")
    }
    
    @MainActor
    func upgradeThumbnailsIfNeeded() {
        migrationTask?.cancel() // Cancel any previous run
        
        let userId = self.activeUserId
        let targetWidth = thumbnailSize.width
        let snapshotEntries = self.entries // Local copy to avoid actor isolation issues during iteration
        
        Log.debug("✨ ImageStore: [MAINTENANCE] Checking \(snapshotEntries.count) thumbnails for dynamic resolution migrations.")
        
        migrationTask = Task(priority: .background) {
            var upgradedCount = 0
            
            // Check one by one so we don't saturate the system (no task group)
            for entry in snapshotEntries {
                // 🛑 Check for cancellation (e.g., if we start a new migration or app closes)
                if Task.isCancelled {
                    Log.debug("✨ ImageStore: [MAINTENANCE] Task cancelled. Stopping migration.")
                    return
                }
                
                // 1. Check if the file on disk is too small
                let needsUpgrade = await self.fileService.thumbnailNeedsUpgrade(
                    filename: entry.filename,
                    targetSize: targetWidth, userId: userId
                )
                
                if needsUpgrade {
                    upgradedCount += 1
                    
                    // 2. loadThumbnailAsync already has logic to regenerate from full image
                    // and save back to disk. We just call it with allowGeneration: true.
                    _ = await self.loadThumbnail(for: entry, forceGeneration: true)
                    
                    // 😴 SLEEP: Give the Main Thread room to breathe
                    // 100ms is enough to keep the phone cool and the UI at 120fps
                    // Brief pause between upgrades to keep the phone cool/responsive
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            Log.debug("✨ ImageStore: [MAINTENANCE] Thumbnail migration complete. Upgraded \(upgradedCount) files.")
        }
    }
}
