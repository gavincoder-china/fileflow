//
//  BatchImportModels.swift
//  FileFlow
//
//  批量导入数据模型
//  支持重复检测、冲突处理、撤销回滚
//

import Foundation
import SwiftUI

// MARK: - Conflict Resolution Strategy
/// 文件名冲突解决策略
enum ConflictResolution: String, CaseIterable, Identifiable {
    case autoRename = "auto_rename"   // 自动重命名 (添加序号)
    case overwrite = "overwrite"      // 覆盖现有文件
    case skip = "skip"                // 跳过此文件
    case ask = "ask"                  // 每次询问
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .autoRename: return "自动重命名"
        case .overwrite: return "覆盖"
        case .skip: return "跳过"
        case .ask: return "逐个询问"
        }
    }
    
    var icon: String {
        switch self {
        case .autoRename: return "doc.badge.plus"
        case .overwrite: return "arrow.triangle.2.circlepath"
        case .skip: return "forward.fill"
        case .ask: return "questionmark.circle"
        }
    }
}

// MARK: - Duplicate Handling Strategy
/// 重复文件处理策略
enum DuplicateHandling: String, CaseIterable, Identifiable {
    case skip = "skip"                // 跳过重复
    case keepBoth = "keep_both"       // 保留两者
    case replaceExisting = "replace"  // 替换现有
    case ask = "ask"                  // 每次询问
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .skip: return "跳过重复"
        case .keepBoth: return "保留两者"
        case .replaceExisting: return "替换现有"
        case .ask: return "逐个询问"
        }
    }
    
    var icon: String {
        switch self {
        case .skip: return "doc.on.doc.fill"
        case .keepBoth: return "plus.square.on.square"
        case .replaceExisting: return "arrow.triangle.swap"
        case .ask: return "questionmark.circle"
        }
    }
}

// MARK: - Import Status
/// 单个文件导入状态
enum ImportStatus: Equatable {
    case pending                      // 待处理
    case analyzing                    // AI 分析中
    case ready                        // 准备导入
    case importing                    // 导入中
    case success                      // 成功
    case skipped(reason: String)      // 已跳过
    case failed(error: String)        // 失败
    case duplicate(existingId: UUID)  // 检测到重复
    case conflict(existingPath: String) // 名称冲突
    
    var isFinished: Bool {
        switch self {
        case .success, .skipped, .failed:
            return true
        default:
            return false
        }
    }
    
    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .analyzing: return "分析中"
        case .ready: return "就绪"
        case .importing: return "导入中"
        case .success: return "成功"
        case .skipped: return "已跳过"
        case .failed: return "失败"
        case .duplicate: return "重复"
        case .conflict: return "冲突"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .gray
        case .analyzing: return .blue
        case .ready: return .green
        case .importing: return .orange
        case .success: return .green
        case .skipped: return .yellow
        case .failed: return .red
        case .duplicate: return .purple
        case .conflict: return .orange
        }
    }
}

// MARK: - Import File Item
/// 待导入文件项
struct ImportFileItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let fileName: String
    let fileSize: Int64
    var contentHash: String?          // SHA256 哈希
    
    // AI 分析结果
    var suggestedCategory: PARACategory = .resources
    var suggestedSubcategory: String?
    var suggestedName: String?
    var suggestedTags: [String] = []
    
    // 用户选择
    var selectedCategory: PARACategory = .resources
    var selectedSubcategory: String?
    var customName: String?
    var isSelected: Bool = true
    
    // 状态
    var status: ImportStatus = .pending
    
    /// 最终使用的文件名
    var finalName: String {
        customName ?? suggestedName ?? fileName
    }
    
    /// 文件扩展名
    var fileExtension: String {
        sourceURL.pathExtension.lowercased()
    }
    
    /// 格式化文件大小
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    init(url: URL) {
        self.sourceURL = url
        self.fileName = url.lastPathComponent
        
        // 获取文件大小
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            self.fileSize = size
        } else {
            self.fileSize = 0
        }
    }
}

// MARK: - Import Result
/// 单个文件导入结果
struct ImportResult: Identifiable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL?
    let fileId: UUID?                 // 数据库中的文件 ID
    let status: ImportStatus
    let timestamp: Date
    
    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }
}

// MARK: - Batch Import Session
/// 批量导入会话 - 支持撤销
struct BatchImportSession: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var completedAt: Date?
    var sourceFolder: URL?            // 导入来源文件夹
    var importedFileIds: [UUID]       // 已导入文件的 ID 列表
    var appliedTags: [String]         // 批量应用的标签
    var totalCount: Int
    var successCount: Int
    var skippedCount: Int
    var failedCount: Int
    
    init(sourceFolder: URL? = nil) {
        self.id = UUID()
        self.startedAt = Date()
        self.sourceFolder = sourceFolder
        self.importedFileIds = []
        self.appliedTags = []
        self.totalCount = 0
        self.successCount = 0
        self.skippedCount = 0
        self.failedCount = 0
    }
    
    /// 是否可以撤销
    var canUndo: Bool {
        !importedFileIds.isEmpty
    }
    
    /// 格式化时间
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: startedAt)
    }
}

// MARK: - Import Options
/// 导入选项配置
struct ImportOptions {
    var conflictResolution: ConflictResolution = .autoRename
    var duplicateHandling: DuplicateHandling = .skip
    var enableAIAnalysis: Bool = true
    var applyBatchTags: [String] = []
    var rememberSourcePath: Bool = true
    var showPreview: Bool = true
    
    /// 默认选项
    static let `default` = ImportOptions()
}

// MARK: - Import Progress
/// 导入进度
struct ImportProgress {
    var phase: Phase = .scanning
    var current: Int = 0
    var total: Int = 0
    var currentFileName: String = ""
    
    enum Phase: String {
        case scanning = "扫描文件"
        case hashing = "计算哈希"
        case analyzing = "AI 分析"
        case importing = "导入文件"
        case complete = "完成"
    }
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    var displayText: String {
        if phase == .complete {
            return "导入完成"
        }
        return "\(phase.rawValue) (\(current)/\(total))"
    }
}
