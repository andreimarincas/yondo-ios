//
//  Task+Utils.swift
//  Yondo
//
//  Created by Andrei Marincas on 11.01.2026.
//

import Foundation

extension Task where Success == Never, Failure == Never {
    /// Executes a closure in a non-cancellable way by wrapping it in a
    /// new Task, shielding it from the caller's cancellation state.
    static func withExternalCancellationIgnored<T>(
        priority: TaskPriority? = .background,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let task = Task<T, Error>(priority: priority) {
            try await operation()
        }
        return try await task.value
    }
}

extension Task where Success == Never, Failure == Never {
    /// Runs an async operation with a maximum time limit.
    /// Returns the result of the operation or throws SyncError.timeout.
    static func runWithTimeout<T>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Task 1: The actual work
            group.addTask {
                try await operation()
            }
            
            // Task 2: The ticking clock
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TaskError.timeout
            }
            
            // The first one to finish (or throw) wins.
            // If the timer wins, it throws .timeout and cancels the work.
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

enum TaskError: Error {
    case timeout
}
