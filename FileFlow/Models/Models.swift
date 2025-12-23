//
//  Models.swift
//  FileFlow
//
//  核心数据模型
//

import Foundation
import SwiftUI

// MARK: - PARA Category
enum PARACategory: String, CaseIterable, Codable, Identifiable {
    case projects = "Projects"
    case areas = "Areas"
    case resources = "Resources"
    case archives = "Archives"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .projects: return "项目"
        case .areas: return "领域"
        case .resources: return "资源"
        case .archives: return "归档"
        }
    }
    
    var icon: String {
        switch self {
        case .projects: return "folder.fill"
        case .areas: return "square.stack.3d.up.fill"
        case .resources: return "books.vertical.fill"
        case .archives: return "archivebox.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .projects: return .blue
        case .areas: return .purple
        case .resources: return .green
        case .archives: return .gray
        }
    }
    
    var folderName: String {
        switch self {
        case .projects: return "1_Projects"
        case .areas: return "2_Areas"
        case .resources: return "3_Resources"
        case .archives: return "4_Archives"
        }
    }
    
    var description: String {
        switch self {
        case .projects: return "当前正在进行的项目"
        case .areas: return "持续关注的责任领域"
        case .resources: return "未来可能有用的资料"
        case .archives: return "已完成或不再活跃的内容"
        }
    }
}

// MARK: - Tag
struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String // Hex color
    var usageCount: Int
    var isFavorite: Bool
    var createdAt: Date
    var lastUsedAt: Date
    
    // Hierarchy support
    var parentId: UUID?
    
    init(id: UUID = UUID(), name: String, color: String = "#007AFF", usageCount: Int = 0, isFavorite: Bool = false, parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.usageCount = usageCount
        self.isFavorite = isFavorite
        self.parentId = parentId
        self.createdAt = Date()
        self.lastUsedAt = Date()
    }
    
    var swiftUIColor: Color {
        Color(hex: color) ?? .blue
    }
}


// MARK: - Managed File
struct ManagedFile: Identifiable, Codable {
    let id: UUID
    var originalName: String
    var newName: String
    var originalPath: String
    var newPath: String
    var category: PARACategory
    var subcategory: String?
    var tags: [Tag]
    var summary: String?
    var notes: String?
    var fileSize: Int64
    var fileType: String
    var createdAt: Date
    var importedAt: Date
    var modifiedAt: Date
    
    init(
        id: UUID = UUID(),
        originalName: String,
        originalPath: String,
        category: PARACategory = .resources,
        subcategory: String? = nil,
        tags: [Tag] = [],
        summary: String? = nil,
        notes: String? = nil,
        fileSize: Int64 = 0,
        fileType: String = ""
    ) {
        self.id = id
        self.originalName = originalName
        self.newName = originalName
        self.originalPath = originalPath
        self.newPath = ""
        self.category = category
        self.subcategory = subcategory
        self.tags = tags
        self.summary = summary
        self.notes = notes
        self.fileSize = fileSize
        self.fileType = fileType
        self.createdAt = Date()
        self.importedAt = Date()
        self.modifiedAt = Date()
    }
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var fileExtension: String {
        (originalName as NSString).pathExtension.lowercased()
    }
    
    var icon: String {
        switch fileExtension {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "avi": return "video.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "play.rectangle.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "md", "txt": return "doc.plaintext.fill"
        default: return "doc.fill"
        }
    }
    
    var displayName: String {
        newName.isEmpty ? originalName : newName
    }
}

// MARK: - Subcategory
struct Subcategory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var parentCategory: PARACategory
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, parentCategory: PARACategory) {
        self.id = id
        self.name = name
        self.parentCategory = parentCategory
        self.createdAt = Date()
    }
}

// MARK: - AI Analysis Result
struct AIAnalysisResult {
    var summary: String
    var suggestedTags: [String]
    var suggestedCategory: PARACategory
    var suggestedSubcategory: String?
    var confidence: Double
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else { return "#007AFF" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Preset Tag Colors
struct TagColors {
    static let presets: [String] = [
        "#FF6B6B", // Red
        "#4ECDC4", // Teal
        "#45B7D1", // Blue
        "#96CEB4", // Green
        "#FFEAA7", // Yellow
        "#DDA0DD", // Plum
        "#98D8C8", // Mint
        "#F7DC6F", // Gold
        "#BB8FCE", // Purple
        "#85C1E9", // Sky Blue
    ]
    
    static func random() -> String {
        presets.randomElement() ?? "#007AFF"
    }
}

// MARK: - Auto Archive Rules

enum RuleConditionField: String, Codable, CaseIterable {
    case fileName = "文件名"
    case fileExtension = "文件扩展名"
    case fileSize = "文件大小(KB)"
//    case creationDate = "创建日期"
//    case lastModifiedDate = "修改日期"
}

enum RuleOperator: String, Codable, CaseIterable {
    case contains = "包含"
    case equals = "等于"
    case startsWith = "开头是"
    case endsWith = "结尾是"
    case greaterThan = "大于" // For size
    case lessThan = "小于"    // For size
}

struct RuleCondition: Identifiable, Codable, Hashable {
    var id: UUID
    var field: RuleConditionField
    var `operator`: RuleOperator
    var value: String
    
    init(id: UUID = UUID(), field: RuleConditionField, operator: RuleOperator, value: String) {
        self.id = id
        self.field = field
        self.operator = `operator`
        self.value = value
    }
}

enum RuleActionType: String, Codable, CaseIterable {
    case move = "移动到分类"
    case addTag = "添加标签"
    case delete = "删除文件"
}

struct RuleAction: Identifiable, Codable, Hashable {
    var id: UUID
    var type: RuleActionType
    var targetValue: String // Folder path (Category/Subcategory), Tag ID, etc.
    
    init(id: UUID = UUID(), type: RuleActionType, targetValue: String) {
        self.id = id
        self.type = type
        self.targetValue = targetValue
    }
}

enum RuleMatchType: String, Codable, CaseIterable {
    case all = "满足所有条件"
    case any = "满足任一条件"
}

struct AutoRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var matchType: RuleMatchType
    var conditions: [RuleCondition]
    var actions: [RuleAction]
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, matchType: RuleMatchType = .all, conditions: [RuleCondition] = [], actions: [RuleAction] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchType = matchType
        self.conditions = conditions
        self.actions = actions
        self.createdAt = Date()
    }
}
