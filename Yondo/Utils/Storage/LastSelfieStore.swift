//
//  LastSelfieStore.swift
//  Yondo
//
//  Created by Andrei Marincas on 04.01.2026.
//

import UIKit

actor LastSelfieStore {
    static let shared = LastSelfieStore()

    // MARK: - Dependencies
    private let fileService = ImageFileService()
    
    // MARK: - State (In-Memory Cache)
    private var cachedFullSelfie: UIImage?
    private(set) var cachedThumbnail: UIImage?
    
    private(set) var activeUserId: String
    
    private init() {
        self.activeUserId = "local"
    }
    
    /// Called during app boot-up by AuthManager to bridge any offline 'local' data to the cloud.
    func initialize(with userId: String?) async {
        let targetId = userId ?? "local"
        
        Log.debug("🤳 LastSelfieStore: 🏁 Initializing for user [\(targetId)]. Check for pending migrations...")
        
        if targetId != "local" {
            // This triggers your migrateSelfieDirectory and shifts the memory pointers!
            await updateIdentity(newUserId: targetId)
        } else {
            // No user, just prewarm the local files
            Log.debug("🤳 LastSelfieStore: ℹ️ Initialized as 'local'. Pre-warming local caches.")
            await prewarm()
        }
    }
    
    func prewarm() async {
        // Only load if we haven't already
        guard cachedThumbnail == nil else {
            Log.debug("🤳 LastSelfieStore: ⏩ Skipping prewarm. Thumbnail already in memory.")
            return
        }
        let userId = self.activeUserId
        
        if let data = await fileService.loadSelfieData(isThumbnail: true, userId: userId) {
            Log.debug("🤳 LastSelfieStore: ✅ Pre-warmed thumbnail into memory for [\(userId)].")
            self.cachedThumbnail = UIImage(data: data)
        } else {
            Log.debug("🤳 LastSelfieStore: ℹ️ Pre-warm yield was empty. No stored thumbnail on disk for [\(userId)].")
        }
    }
    
    func updateIdentity(newUserId: String) async {
        guard newUserId != activeUserId else { return }
        Log.debug("🤳 LastSelfieStore: 👤 Identity shifting from [\(activeUserId)] to [\(newUserId)].")
        
        // 🚚 1. Move files if upgrading from a local session!
        if activeUserId == "local" {
            Log.debug("🤳 LastSelfieStore: 🚚 Upgrading anonymous session. Attempting physical file migration to [\(newUserId)]...")
            await fileService.migrateSelfieDirectory(fromUserId: "local", toUserId: newUserId)
        }
        
        self.activeUserId = newUserId
        
        // 2. Clear out memory caches for the old user
        Log.debug("🤳 LastSelfieStore: 🧹 Purging memory cache for old session.")
        self.cachedFullSelfie = nil
        self.cachedThumbnail = nil
        
        // 3. Prewarm the new user's thumbnail
        await prewarm()
    }
    
    // MARK: - Save Selfie
    func saveSelfie(_ image: UIImage) async throws {
        let userId = self.activeUserId
        Log.debug("🤳 LastSelfieStore: ⏳ Preparing to save new selfie for user [\(userId)]. Generating square thumbnail...")
        
        // 1. Prepare Data
        let thumbnail = await ThumbnailGenerator.generateSquare(from: image, maxPixelSize: 256)
        
        guard let fullData = image.jpegData(compressionQuality: 0.95),
              let thumbData = thumbnail.jpegData(compressionQuality: 0.95) else {
            Log.error("🤳 LastSelfieStore: ❌ Failed to bake JPEG data. Aborting save.")
            return
        }
        
        do {
            // 2. Delegate Disk I/O to Service
            try await fileService.saveSelfieData(fullData, isThumbnail: false, userId: userId)
            try await fileService.saveSelfieData(thumbData, isThumbnail: true, userId: userId)
            
            // 3. Update Memory Cache
            // TODO: Set these first, at the beginning of the function? because views that depend on these should not wait for the sync write to disk
            self.cachedFullSelfie = image
            self.cachedThumbnail = thumbnail
            
            Log.debug("🤳 LastSelfieStore: ✅ Successfully saved selfie & thumbnail to disk and memory for [\(userId)].")
        } catch {
            Log.error("🤳 LastSelfieStore: ❌ Disk write failure: \(error.localizedDescription)")
            throw error
        }
        
        Log.debug("🤳 LastSelfieStore: Successfully saved selfie and 256x256 square thumbnail.")
    }
    
    // MARK: - Load Selfie
    func loadSelfie() async -> UIImage? {
        if let cached = cachedFullSelfie {
            Log.debug("🤳 LastSelfieStore: 🧠 Cache Hit (Full Image). Skipping Disk I/O.")
            return cached
        }
        let userId = self.activeUserId
        
        Log.debug("🤳 LastSelfieStore: 🛰️ Cache Miss. Pulling full selfie from Disk for [\(userId)]...")
        guard let data = await fileService.loadSelfieData(isThumbnail: false, userId: userId),
              let image = UIImage(data: data) else {
            Log.debug("🤳 LastSelfieStore: ℹ️ No full selfie found on disk for [\(userId)].")
            return nil
        }
        
        self.cachedFullSelfie = image
        return image
    }
    
//    func loadSelfieCGImage() async -> CGImage? {
//        // 1. Check memory cache first
//        if let cached = cachedFullSelfie {
//            Log.debug("🤳 LastSelfieStore: 🧠 Cache Hit (CGImage). Skipping Disk I/O.")
//            return cached.cgImage
//        }
//        let userId = self.activeUserId
//        
//        // 2. Ask Service to do the heavy I/O lifting
//        Log.debug("🤳 LastSelfieStore: 🛰️ Cache Miss. Pulling CGImage from Disk for [\(userId)]...")
//        guard let cgImage = await fileService.loadSelfieCGImage(userId: userId) else {
//            Log.debug("🤳 LastSelfieStore: ℹ️ No CGImage found on disk for [\(userId)].")
//            return nil
//        }
//        
//        // 3. Back-fill the UIImage cache
//        // We do the UIImage conversion here because that's "UI Logic"
//        self.cachedFullSelfie = await MainActor.run {
//            UIImage.fromCapturedCGImage(cgImage, mirrorSelfie: true)
//        }
//        
//        return cgImage
//    }
    
    func loadThumbnail() async -> UIImage? {
        if let cached = cachedThumbnail {
            Log.debug("🤳 LastSelfieStore: 🧠 Cache Hit (Thumbnail). Skipping Disk I/O.")
            return cached
        }
        let userId = self.activeUserId
        
        Log.debug("🤳 LastSelfieStore: 🛰️ Cache Miss. Pulling thumbnail from Disk for [\(userId)]...")
        guard let data = await fileService.loadSelfieData(isThumbnail: true, userId: userId),
              let image = UIImage(data: data) else {
            Log.debug("🤳 LastSelfieStore: ℹ️ No thumbnail found on disk for [\(userId)].")
            return nil
        }
        
        self.cachedThumbnail = image
        return image
    }
    
    // MARK: - Clear
    func clear() async throws {
        let userId = self.activeUserId
        Log.debug("🤳 LastSelfieStore: 🗑️ Clearing selfie folder and memory caches for user [\(userId)].")
        
        await fileService.deleteSelfieFolder(userId: userId)
        cachedFullSelfie = nil
        cachedThumbnail = nil
        Log.debug("🤳 LastSelfieStore: ✅ Clean wipe complete.")
    }
}
