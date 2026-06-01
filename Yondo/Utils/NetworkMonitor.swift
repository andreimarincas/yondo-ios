//
//  NetworkMonitor.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.01.2026.
//

import Network

final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    
    var isConnected: Bool {
        monitor.currentPath.status == .satisfied
    }
    
    /// This property creates a stream that yields 'true' when connected and 'false' when not.
    var statusStream: AsyncStream<Bool> {
        // Only keep the most recent update, drop the rest if we are busy
        AsyncStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            // 0. Yield the INITIAL state immediately so the listener isn't waiting
            continuation.yield(monitor.currentPath.status == .satisfied)
            
            // 1. Define what happens when the monitor finds a change
            monitor.pathUpdateHandler = { path in
                let isConnected = (path.status == .satisfied)
                // Push the new value into the stream
                continuation.yield(isConnected)
            }

            // 2. Start the monitor
            monitor.start(queue: queue)

            // 3. Cleanup: If the listener cancels the task, stop the monitor
            continuation.onTermination = { @Sendable _ in
                self.monitor.cancel()
            }
        }
    }
}
