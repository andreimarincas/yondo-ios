//
//  Log.swift
//  Yondo
//
//  Created by Andrei Marincas on 06.01.2026.
//

/// A thread-safe logging utility that provides formatted console output.
/// All methods are marked as `nonisolated` to allow synchronous calling from any
/// actor or background thread without context switching or compiler warnings.
import OSLog
import Foundation

enum Log: Sendable {
    // We mark this nonisolated. Since Logger is Sendable, this is perfectly safe.
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.yondo.app", category: "General")

    // App-wide start reference for elapsed time
    nonisolated static let appStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    nonisolated static func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        let elapsed = CFAbsoluteTimeGetCurrent() - appStartTime
        let formatted = String(format: "%.3f", elapsed)
        log(level: .debug, message: "\(message) (+\(formatted)s)", file: file, function: function, line: line)
    }
    
    nonisolated static func warning(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        let elapsed = CFAbsoluteTimeGetCurrent() - appStartTime
        let formatted = String(format: "%.3f", elapsed)
        log(level: .info, message: "\(message) (+\(formatted)s)", file: file, function: function, line: line)
    }

    nonisolated static func error(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        let elapsed = CFAbsoluteTimeGetCurrent() - appStartTime
        let formatted = String(format: "%.3f", elapsed)
        log(level: .error, message: "\(message) (+\(formatted)s)", file: file, function: function, line: line)
    }

    nonisolated static func error(_ error: Error, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(level: .error, message: "\(error)", file: file, function: function, line: line)
    }

    nonisolated static func error(_ message: String, _ error: Error, file: String = #fileID, function: String = #function, line: Int = #line) {
        log(level: .error, message: "\(message): \(error)", file: file, function: function, line: line)
    }

    private nonisolated static func log(level: OSLogType, message: String, file: String, function: String, line: Int) {
        let entry = "[\(file):\(line)] \(function) → \(message)"
        
        #if DEBUG
        // Using a local helper instead of the protocol extension to avoid isolation issues
//        print("[\(levelName(level))] \(entry)")
        #endif
        
        switch level {
        case .debug:
            // .default is persistent but 'lesser' than .error
            logger.log(level: .default, "DEBUG 🕹️ \(entry, privacy: .public)")
//            logger.debug("\(entry, privacy: .public)")
        case .error:
            // .error is always persistent and shows a red icon
            logger.error("\(entry, privacy: .public)")
        case .info:
            // Using .default for warnings so they survive the archive
            logger.log(level: .default, "WARN ⚠️ \(entry, privacy: .public)")
//            logger.info("\(entry, privacy: .public)")
        default:
            logger.log(level: .default, "\(entry, privacy: .public)")
        }
    }

    // A simple nonisolated helper to stringify the level
    private nonisolated static func levelName(_ level: OSLogType) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        case .info: return "WARNING"
        default: return "LOG"
        }
    }
}
