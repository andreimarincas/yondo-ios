//
//  ImageFileService+Selfie.swift
//  Yondo
//
//  Created by Andrei Marincas on 22.03.2026.
//

import Foundation
import ImageIO

extension ImageFileService {
    // MARK: - Selfie Paths
    private func selfieDir(for userId: String) -> URL {
        ensureDir(at: documentsDir
            .appendingPathComponent("LastSelfie")
            .appendingPathComponent(userId)
        )
    }
    
    private func selfieURL(isThumbnail: Bool, userId: String) -> URL {
        let filename = isThumbnail ? "lastSelfieThumbnail.jpg" : "lastSelfie.jpg"
        return selfieDir(for: userId).appendingPathComponent(filename)
    }
    
    // MARK: - Selfie I/O
    func saveSelfieData(_ data: Data, isThumbnail: Bool, userId: String) throws {
        let url = selfieURL(isThumbnail: isThumbnail, userId: userId)
        let typeLabel = isThumbnail ? "Thumbnail" : "Full Image"
        
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            
            // Exclude from iCloud
            var urlCopy = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try urlCopy.setResourceValues(resourceValues)
            
            Log.debug("💾 FileService: Written \(typeLabel) to disk for [\(userId)]. Size: \(data.count) bytes.")
        } catch {
            Log.error("❌ FileService: Failed to write \(typeLabel) to disk for [\(userId)]. Error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func loadSelfieData(isThumbnail: Bool, userId: String) -> Data? {
        let url = selfieURL(isThumbnail: isThumbnail, userId: userId)
        let typeLabel = isThumbnail ? "Thumbnail" : "Full Image"
        
        guard fileManager.fileExists(atPath: url.path) else {
            return nil // Normal path: user hasn't taken a selfie yet
        }
        
        do {
            let data = try Data(contentsOf: url)
            Log.debug("📂 FileService: Successfully loaded \(typeLabel) for [\(userId)].")
            return data
        } catch {
            Log.error("❌ FileService: Error reading \(typeLabel) from disk for [\(userId)]: \(error.localizedDescription)")
            return nil
        }
    }
    
    func loadSelfieCGImage(userId: String) -> CGImage? {
        let url = selfieURL(isThumbnail: false, userId: userId)
        
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        
        Log.debug("🛰️ FileService: Instantiating ImageSource for large photo decompression [\(userId)].")
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            Log.error("❌ FileService: Failed to decode CGImage from disk for [\(userId)].")
            return nil
        }
        return cgImage
    }
    
    func deleteSelfieFolder(userId: String) {
        let dir = selfieDir(for: userId)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        
        do {
            try fileManager.removeItem(at: dir)
            Log.debug("🧹 FileService: Nuke selfie folder complete for [\(userId)].")
        } catch {
            Log.error("❌ FileService: Failed to delete selfie folder for [\(userId)]: \(error.localizedDescription)")
        }
    }
}

extension ImageFileService {
    
    // MARK: - Selfie Migration
    func migrateSelfieDirectory(fromUserId oldId: String, toUserId newId: String) async {
        let sourceDir = selfieDir(for: oldId)
        let destinationDir = selfieDir(for: newId)
        
        guard fileManager.fileExists(atPath: sourceDir.path) else {
            Log.debug("ℹ️ FileService: No selfies found in [\(oldId)] directory. Skipping migration.")
            return
        }
        
        Log.debug("🚚 FileService: Starting physical migration of selfies from [\(oldId)] to [\(newId)]...")
        
        do {
            if !fileManager.fileExists(atPath: destinationDir.path) {
                // Scenario A: Fresh move (Fastest)
                Log.debug("🚚 FileService [Scenario A]: Destination directory is fresh. Moving entire folder.")
                try fileManager.createDirectory(at: destinationDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: sourceDir, to: destinationDir)
                Log.debug("✅ FileService [Scenario A]: Entire selfie folder successfully moved.")
            } else {
                // Scenario B: Merge files into existing directory if it already exists
                Log.debug("🚚 FileService [Scenario B]: Destination directory already exists. Beginning file-by-file merge.")
                let files = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
                
                var mergedCount = 0
                for fileURL in files {
                    await Task.yield() // 🚥 Yield to keep the UI snappy
                    
                    let targetURL = destinationDir.appendingPathComponent(fileURL.lastPathComponent)
                    
                    if fileManager.fileExists(atPath: targetURL.path) {
                        Log.debug("⚠️ FileService: Duplicate found for [\(fileURL.lastPathComponent)]. Overwriting older destination file.")
                        try? fileManager.removeItem(at: targetURL)
                    }
                    
                    try fileManager.moveItem(at: fileURL, to: targetURL)
                    mergedCount += 1
                }
                try? fileManager.removeItem(at: sourceDir) // Clean up old empty folder
                Log.debug("✅ FileService [Scenario B]: Merged \(mergedCount) files and purged the old [\(oldId)] folder.")
            }
            Log.debug("🎉 FileService: Selfie physical migration complete.")
        } catch {
            Log.error("❌ FileService: Severe failure during selfie migration! From [\(oldId)] to [\(newId)]: \(error.localizedDescription)")
        }
    }
}
