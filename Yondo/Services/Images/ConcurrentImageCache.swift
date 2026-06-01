//
//  ConcurrentImageCache.swift
//  Yondo
//
//  Created by Andrei Marincas on 10.02.2026.
//

import UIKit
import os

final class ConcurrentImageCache: @unchecked Sendable {
    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    private let lock = OSAllocatedUnfairLock()

    init() {}

    nonisolated func setObject(_ obj: UIImage, forKey key: String) {
        // Pass the Sendable 'String' into the lock
        lock.withLock {
            // Cast to NSString INSIDE the closure
            cache.setObject(obj, forKey: key as NSString)
        }
    }

    nonisolated func object(forKey key: String) -> UIImage? {
        lock.withLock {
            cache.object(forKey: key as NSString)
        }
    }

    nonisolated func removeObject(forKey key: String) {
        lock.withLock {
            cache.removeObject(forKey: key as NSString)
        }
    }

    nonisolated func removeAllObjects() {
        lock.withLock {
            cache.removeAllObjects()
        }
    }

    nonisolated var countLimit: Int {
        get { lock.withLock { cache.countLimit } }
        set { lock.withLock { cache.countLimit = newValue } }
    }

    nonisolated var totalCostLimit: Int {
        get { lock.withLock { cache.totalCostLimit } }
        set { lock.withLock { cache.totalCostLimit = newValue } }
    }
}
