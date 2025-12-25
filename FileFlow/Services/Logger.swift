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
        
        var name: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .success: return "SUCCESS"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }
    }
    
    // MARK: - Log Entry
    
    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let level: String
        let message: String
        let file: String
        let line: Int
        
        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }
    
    // MARK: - Private Properties
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.fileflow"
    private static let osLog = OSLog(subsystem: subsystem, category: "FileFlow")
    
    // Log history buffer (for export)
    private static var logHistory: [LogEntry] = []
    private static let maxHistorySize = 1000
    private static let historyQueue = DispatchQueue(label: "com.fileflow.logger.history")
    
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
        
        // Store in history buffer (thread-safe)
        historyQueue.async {
            let entry = LogEntry(
                id: UUID(),
                timestamp: Date(),
                level: level.name,
                message: message,
                file: fileName,
                line: line
            )
            logHistory.append(entry)
            
            // Trim if exceeds max size
            if logHistory.count > maxHistorySize {
                logHistory.removeFirst(logHistory.count - maxHistorySize)
            }
        }
    }
    
    // MARK: - Log History Access
    
    /// Get recent log entries
    static func getRecentLogs(limit: Int = 100) -> [LogEntry] {
        historyQueue.sync {
            Array(logHistory.suffix(limit))
        }
    }
    
    /// Get logs filtered by level
    static func getLogs(level: Level, limit: Int = 100) -> [LogEntry] {
        historyQueue.sync {
            logHistory.filter { $0.level == level.name }.suffix(limit).map { $0 }
        }
    }
    
    /// Clear log history
    static func clearHistory() {
        historyQueue.async {
            logHistory.removeAll()
        }
    }
    
    // MARK: - Log Export
    
    /// Export logs to a file
    static func exportLogs() -> URL? {
        let logs = getRecentLogs(limit: maxHistorySize)
        
        var content = "FileFlow Diagnostic Logs\n"
        content += "Exported: \(Date())\n"
        content += "===================================\n\n"
        
        for entry in logs {
            content += "[\(entry.formattedDate)] [\(entry.level)] [\(entry.file):\(entry.line)]\n"
            content += "  \(entry.message)\n\n"
        }
        
        // Save to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "fileflow_logs_\(Date().timeIntervalSince1970).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Logger.error("Failed to export logs: \(error)")
            return nil
        }
    }
    
    /// Export logs as JSON
    static func exportLogsAsJSON() -> URL? {
        let logs = getRecentLogs(limit: maxHistorySize)
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "fileflow_logs_\(Date().timeIntervalSince1970).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(logs)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            Logger.error("Failed to export logs as JSON: \(error)")
            return nil
        }
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
