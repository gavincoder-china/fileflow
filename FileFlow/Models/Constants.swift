//
//  Constants.swift
//  FileFlow
//
//  Application-wide constants and configuration values
//  Centralizes magic numbers and hardcoded values for easier maintenance
//

import Foundation

/// Application-wide configuration constants
enum AppConstants {
    
    // MARK: - UI Constants
    
    enum UI {
        /// Maximum number of recent files to display on home screen
        static let recentFilesDisplayLimit = 10
        
        /// Maximum number of tags to show in sidebar when no favorites
        static let sidebarTagLimit = 5
        
        /// Maximum number of tags to show inline with file info
        static let inlineTagLimit = 3
        
        /// Corner radius for cards and containers
        static let cardCornerRadius: CGFloat = 16
        
        /// Large corner radius for major UI elements
        static let largeCornerRadius: CGFloat = 24
    }
    
    // MARK: - Rule Engine
    
    enum Rules {
        /// Maximum number of files to process in batch rule execution
        static let batchProcessLimit = 100
        
        /// Similarity threshold for semantic search (0.0 - 1.0)
        static let similarityThreshold: Float = 0.5
    }
    
    // MARK: - Database
    
    enum Database {
        /// Database file name
        static let fileName = "fileflow.db"
        
        /// Metadata folder name (hidden)
        static let metadataFolder = ".fileflow"
    }
    
    // MARK: - File Operations
    
    enum FileOps {
        /// Delay before checking for new files after directory change (seconds)
        static let newFileCheckDelay: Double = 1.0
        
        /// Maximum file name length after sanitization
        static let maxFileNameLength = 50
    }
    
    // MARK: - Date Formats
    
    enum DateFormat {
        /// Format for file naming
        static let fileName = "yyyy-MM-dd"
    }
}
