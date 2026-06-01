//
//  ImageFileService.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import Foundation
import UIKit

/// Responsible exclusively for Disk I/O operations (Reading/Writing/Deleting).
/// implementation as an 'actor' prevents race conditions on file writes.
actor ImageFileService {
    let fileManager = FileManager.default
    
    // MARK: - Paths
    lazy var documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private lazy var appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    private lazy var cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    
    // MARK: - Dynamic User Paths
    private func imagesDir(for userId: String) -> URL {
        ensureDir(at: documentsDir
            .appendingPathComponent("GeneratedImages")
            .appendingPathComponent(userId)
        )
    }
    
    private func thumbnailsDir(for userId: String) -> URL {
        ensureDir(at: cacheDir
            .appendingPathComponent("GeneratedImageThumbnails")
            .appendingPathComponent(userId)
        )
    }
    
    private func indexURL(for userId: String) -> URL {
        let userDir = ensureDir(at: appSupportDir
            .appendingPathComponent("Yondo")
            .appendingPathComponent(userId)
        )
        return userDir.appendingPathComponent("generated_images.json")
    }
    
    private var pendingIndexTask: Task<Void, Error>?

    // MARK: - Writing
    func saveImage(_ data: Data, filename: String, userId: String) throws {
        try data.write(
            to: imagesDir(for: userId).appendingPathComponent(filename),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
    
    func saveThumbnail(_ data: Data, filename: String, userId: String) throws {
        try data.write(
            to: thumbnailsDir(for: userId).appendingPathComponent(filename),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
    
    func saveIndex(_ entries: [GeneratedImage], userId: String) async throws {
        // Capture the current task so we can chain onto it
        let previousTask = pendingIndexTask
        
        let newTask = Task {
            // Wait for the previous save to finish (even if it failed)
            _ = await previousTask?.result
            
            let data = try JSONEncoder().encode(entries)
            try data.write(
                to: indexURL(for: userId),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            
            // Keep the index out of iCloud to stay lean
            try? (indexURL(for: userId) as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        }
        
        pendingIndexTask = newTask
        return try await newTask.value
    }
    
    // MARK: - Reading
    func loadIndex(userId: String) -> [GeneratedImage]? {
        guard let data = try? Data(contentsOf: indexURL(for: userId)) else { return nil }
        guard let decoded = try? JSONDecoder().decode([GeneratedImage].self, from: data) else {
            return nil
        }
        // Index exists: Sort it (since JSON might not preserve order)
        return decoded.sorted(by: { $0.createdAt > $1.createdAt })
    }
    
    func loadImageData(filename: String, userId: String) throws -> Data {
        try Data(contentsOf: imagesDir(for: userId).appendingPathComponent(filename), options: .mappedIfSafe)
    }
    
    func loadThumbnailData(filename: String, userId: String) -> Data? {
        try? Data(contentsOf: thumbnailsDir(for: userId).appendingPathComponent(filename), options: .mappedIfSafe)
    }

    // MARK: - Deletion
    func delete(filename: String, userId: String) {
        try? fileManager.removeItem(at: imagesDir(for: userId).appendingPathComponent(filename))
        try? fileManager.removeItem(at: thumbnailsDir(for: userId).appendingPathComponent(filename))
    }
    
    func nukeAllData(userId: String) {
        try? fileManager.removeItem(at: imagesDir(for: userId))
        try? fileManager.removeItem(at: thumbnailsDir(for: userId))
        try? fileManager.removeItem(at: indexURL(for: userId))
        
        // Explicitly recreate to ensure next writes don't fail
        try? fileManager.createDirectory(at: imagesDir(for: userId), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDir(for: userId), withIntermediateDirectories: true)
    }
    
    // MARK: - Recovery
    func rebuildIndexFromDisk(userId: String) -> [GeneratedImage] {
        // Specify the key explicitly to improve performance of the directory scan
        // Request both creation and modification dates for maximum reliability
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: imagesDir(for: userId),
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        let entries = files.filter { $0.pathExtension.lowercased() == "jpg" }.compactMap { url -> GeneratedImage? in
            // Extract UUID from filename (e.g., "UUID.jpg")
            let filename = url.lastPathComponent
            let uuidString = url.deletingPathExtension().lastPathComponent
            
            // Ensure this is actually one of our generated images
            guard let id = UUID(uuidString: uuidString) else { return nil }
            
            let resourceValues = try? url.resourceValues(forKeys: keys)
            
            // Priority: Creation Date -> Modification Date -> Current Date
            let date = resourceValues?.creationDate
                    ?? resourceValues?.contentModificationDate
                    ?? Date()
            
            return GeneratedImage(id: id, filename: filename, createdAt: date)
        }
        
        // Trigger Janitor in a detached background task so it doesn't
        // delay the return of the index to the UI.
        let validIds = Set(entries.map { $0.id })
        Task(priority: .background) {
            await self.cleanupOrphanThumbnails(validIds: validIds, userId: userId)
        }
        
        // Deterministic sorting: Primary by date, Secondary by ID
        return entries.sorted {
            ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
        }
    }
    
    // MARK: - Helpers
    func ensureDir(at url: URL) -> URL {
        // Check existence using the URL itself
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == true {
            return url
        }
        
        // If we get here, directory doesn't exist
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    // Inside ImageFileService actor
    func thumbnailNeedsUpgrade(filename: String, targetSize: CGFloat, userId: String) -> Bool {
        let url = thumbnailsDir(for: userId).appendingPathComponent(filename)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat else {
            return true // If we can't read it, assume it needs recreation
        }
        // If the existing thumbnail is smaller than our new target, it's "low quality"
        return width < targetSize
    }
}

extension ImageFileService {
    func getFullImageURL(filename: String, userId: String) -> URL {
        return imagesDir(for: userId).appendingPathComponent(filename)
    }
}

extension ImageFileService {
    
    // MARK: - Migration Logic
    
    func migrateDirectory(fromUserId oldId: String, toUserId newId: String) async {
        Log.debug("🚚 FileService: Starting migration [\(oldId)] -> [\(newId)]")
        
        let categories: [(name: String, source: URL, destination: URL)] = [
            ("Images", rawImagesDir(for: oldId), rawImagesDir(for: newId)),
            ("Thumbnails", rawThumbnailsDir(for: oldId), rawThumbnailsDir(for: newId))
        ]
        
        for cat in categories {
            guard fileManager.fileExists(atPath: cat.source.path) else { continue }
            
            do {
                if !fileManager.fileExists(atPath: cat.destination.path) {
                    // Scenario A: Fresh move (Fastest)
                    try fileManager.createDirectory(at: cat.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.moveItem(at: cat.source, to: cat.destination)
                } else {
                    // Scenario B: Merge files into existing directory
                    try await mergeContents(from: cat.source, to: cat.destination)
                    try? fileManager.removeItem(at: cat.source)
                }
            } catch {
                Log.error("❌ FileService: Failed to migrate \(cat.name): \(error.localizedDescription)")
            }
        }
        
        // IMPORTANT: Nuke the old index files.
        // We don't want to use the 'local' index anymore;
        // we want the Store to trigger a fresh scan of the new unified folder.
        try? fileManager.removeItem(at: rawUserSupportDir(for: oldId))
        
        Log.debug("✅ FileService: Physical migration complete. Old indices purged.")
    }
    
    /// Moves files one-by-one from source to destination.
    private func mergeContents(from source: URL, to destination: URL) async throws {
        let files = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        
        for fileURL in files {
            // 🚥 Yield here so saves aren't blocked during heavy moves
            await Task.yield()
            
            let targetURL = destination.appendingPathComponent(fileURL.lastPathComponent)
            
            // If the file exists in both places, the "local" one wins (most recent).
            // Delete the existing one in the permanent folder first.
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            
            try fileManager.moveItem(at: fileURL, to: targetURL)
        }
    }
    
    // MARK: - "Raw" Path Helpers
    // These do NOT call ensureDir(), which is vital for the moveItem logic to work.
    
    private func rawImagesDir(for userId: String) -> URL {
        documentsDir.appendingPathComponent("GeneratedImages").appendingPathComponent(userId)
    }
    
    private func rawThumbnailsDir(for userId: String) -> URL {
        cacheDir.appendingPathComponent("GeneratedImageThumbnails").appendingPathComponent(userId)
    }
    
    private func rawUserSupportDir(for userId: String) -> URL {
        appSupportDir.appendingPathComponent("Yondo").appendingPathComponent(userId)
    }
}

private extension ImageFileService {
    
    // MARK: - Cleanup
    
    /// Scans the thumbnails directory and removes any files that don't have
    /// a corresponding entry in the provided set of valid IDs.
    func cleanupOrphanThumbnails(validIds: Set<UUID>, userId: String) async {
        let thumbDir = thumbnailsDir(for: userId)
        
        guard let thumbFiles = try? fileManager.contentsOfDirectory(
            at: thumbDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for url in thumbFiles {
            // 🚥 YIELD: Pauses the janitor to let other Actor tasks (like saves) run!
            await Task.yield()
            
            let uuidString = url.deletingPathExtension().lastPathComponent
            
            // If the thumbnail ID isn't in our "Valid" set, it's an orphan.
            if let id = UUID(uuidString: uuidString), !validIds.contains(id) {
                try? fileManager.removeItem(at: url)
                Log.debug("🧹 Janitor: Removed orphan thumbnail: \(uuidString)")
            }
        }
    }
}
