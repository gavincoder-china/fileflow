//
//  Logger.swift
//  FileFlow
//
//  Unified logging system for FileFlow
//  Provides structured logging with levels, emoji indicators, and conditional debug output
//

import Foundation
import os.log

/// Unified logging system for FileFlow
/// Uses os.log in production and print for debug builds
enum Logger {
    
    // MARK: - Log Levels
    
    enum Level: String {
        case debug = "🔍"
        case info = "ℹ️"
        case success = "✅"
        case warning = "⚠️"
        case error = "❌"
        case critical = "🔴"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info, .success: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
    }
    
    // MARK: - Private Properties
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.fileflow"
    private static let osLog = OSLog(subsystem: subsystem, category: "FileFlow")
    
    #if DEBUG
    private static let isDebugBuild = true
    #else
    private static let isDebugBuild = false
    #endif
    
    // MARK: - Public Logging Methods
    
    /// Log debug message (only in DEBUG builds)
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    /// Log info message
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    /// Log success message
    static func success(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .success, message: message, file: file, function: function, line: line)
    }
    
    /// Log warning message
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    /// Log error message
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    /// Log critical error message
    static func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .critical, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - Private Implementation
    
    private static func log(level: Level, message: String, file: String, function: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = "\(level.rawValue) [\(fileName):\(line)] \(message)"
        
        #if DEBUG
        // In debug builds, use print for immediate console output
        print(formattedMessage)
        #endif
        
        // Always log to os.log for system logging
        os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
    }
    
    // MARK: - Convenience Methods for Common Patterns
    
    /// Log file operation
    static func fileOperation(_ operation: String, path: String) {
        info("📁 \(operation): \(path)")
    }
    
    /// Log database operation
    static func database(_ operation: String) {
        debug("💾 DB: \(operation)")
    }
    
    /// Log rule engine operation
    static func rule(_ message: String) {
        info("🤖 Rule: \(message)")
    }
    
    /// Log monitoring event
    static func monitor(_ message: String) {
        info("👁️ Monitor: \(message)")
    }
}
