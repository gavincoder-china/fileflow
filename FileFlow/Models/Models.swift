//
//  Models.swift
//  FileFlow
//
//  核心数据模型
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTType for Drag-and-Drop
extension UTType {
    static var managedFile: UTType {
        UTType(exportedAs: "com.fileflow.managedfile")
    }
}

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
        case .projects: return Color(hex: "#5856D6") ?? .indigo      // System Indigo
        case .areas: return Color(hex: "#AF52DE") ?? .purple       // System Purple
        case .resources: return Color(hex: "#28CD41") ?? .green    // System Green
        case .archives: return Color(hex: "#8E8E93") ?? .gray      // System Gray
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

// ... (omitted lines) ...

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
        // Auto-migration for legacy pastel colors to vivid system colors
        let legacyMap: [String: String] = [
            "#FF6B6B": "#FF3B30", // Red
            "#4ECDC4": "#30B0C7", // Teal
            "#45B7D1": "#007AFF", // Blue
            "#96CEB4": "#28CD41", // Green
            "#FFEAA7": "#FFCC00", // Yellow
            "#DDA0DD": "#AF52DE", // Purple
            "#98D8C8": "#00C7BE", // Mint
            "#F7DC6F": "#FF9500", // Orange
            "#BB8FCE": "#AF52DE", // Purple
            "#85C1E9": "#32ADE6"  // Cyan
        ]
        let hex = legacyMap[color] ?? color
        return Color(hex: hex) ?? .blue
    }
}


// MARK: - Managed File
struct ManagedFile: Identifiable, Codable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .managedFile)
    }
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
    
    // MARK: - Lifecycle Tracking (PARA Lifecycle Management)
    /// 文件生命周期阶段
    var lifecycleStage: FileLifecycleStage
    /// 最后访问时间（用于计算生命周期状态）
    var lastAccessedAt: Date
    /// 内容哈希（用于重复检测）
    var contentHash: String?
    
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
        fileType: String = "",
        lifecycleStage: FileLifecycleStage = .active,
        lastAccessedAt: Date? = nil,
        contentHash: String? = nil
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
        self.lifecycleStage = category == .archives ? .archived : lifecycleStage
        self.lastAccessedAt = lastAccessedAt ?? Date()
        self.contentHash = contentHash
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
    var parentSubcategoryId: UUID?  // For nested folders (nil = direct child of category)
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, parentCategory: PARACategory, parentSubcategoryId: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentCategory = parentCategory
        self.parentSubcategoryId = parentSubcategoryId
        self.createdAt = Date()
    }
    
    /// Full path from category root, e.g., "Web Design/Landing Pages"
    func fullPath(allSubcategories: [Subcategory]) -> String {
        var path = [name]
        var current = self
        while let parentId = current.parentSubcategoryId,
              let parent = allSubcategories.first(where: { $0.id == parentId }) {
            path.insert(parent.name, at: 0)
            current = parent
        }
        return path.joined(separator: "/")
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
        "#FF3B30", // System Red
        "#FF9500", // System Orange
        "#FFCC00", // System Yellow
        "#28CD41", // System Green
        "#007AFF", // System Blue
        "#5856D6", // System Indigo
        "#AF52DE", // System Purple
        "#FF2D55", // System Pink
        "#A2845E", // System Brown
        "#8E8E93", // System Gray
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
    
    // Lifecycle-related conditions
    case lastAccessDays = "未访问天数"
    case lifecycleStage = "生命周期阶段"
    case currentCategory = "当前分类"
    case createdDaysAgo = "创建天数"
    
    /// 是否为数值类型条件
    var isNumeric: Bool {
        switch self {
        case .fileSize, .lastAccessDays, .createdDaysAgo:
            return true
        default:
            return false
        }
    }
    
    /// 适用的操作符
    var applicableOperators: [RuleOperator] {
        if isNumeric {
            return [.equals, .greaterThan, .lessThan]
        } else {
            return [.equals, .contains, .startsWith, .endsWith]
        }
    }
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

// MARK: - Preset Rule Templates
/// 预置规则模板，用户可一键添加
struct PresetRuleTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let rule: AutoRule
    
    /// 创建实际规则（生成新 ID）
    func createRule() -> AutoRule {
        AutoRule(
            name: rule.name,
            isEnabled: true,
            matchType: rule.matchType,
            conditions: rule.conditions,
            actions: rule.actions
        )
    }
}

extension PresetRuleTemplate {
    /// 所有预置模板
    static let allTemplates: [PresetRuleTemplate] = [
        // 1. 过期项目归档
        PresetRuleTemplate(
            name: "过期项目自动归档",
            description: "Projects 中 90 天未访问的文件自动移至 Archives",
            icon: "archivebox.fill",
            rule: AutoRule(
                name: "过期项目自动归档",
                matchType: .all,
                conditions: [
                    RuleCondition(field: .currentCategory, operator: .equals, value: "Projects"),
                    RuleCondition(field: .lastAccessDays, operator: .greaterThan, value: "90")
                ],
                actions: [
                    RuleAction(type: .move, targetValue: "Archives")
                ]
            )
        ),
        
        // 2. 长期未用资源标记
        PresetRuleTemplate(
            name: "长期未用资源提醒",
            description: "Resources 中 180 天未访问的文件添加「待清理」标签",
            icon: "tag.fill",
            rule: AutoRule(
                name: "长期未用资源提醒",
                matchType: .all,
                conditions: [
                    RuleCondition(field: .currentCategory, operator: .equals, value: "Resources"),
                    RuleCondition(field: .lastAccessDays, operator: .greaterThan, value: "180")
                ],
                actions: [
                    RuleAction(type: .addTag, targetValue: "待清理")
                ]
            )
        ),
        
        // 3. 大文件标记
        PresetRuleTemplate(
            name: "大文件标记",
            description: "超过 100MB 的文件添加「大文件」标签",
            icon: "externaldrive.fill",
            rule: AutoRule(
                name: "大文件标记",
                matchType: .all,
                conditions: [
                    RuleCondition(field: .fileSize, operator: .greaterThan, value: "102400") // 100MB in KB
                ],
                actions: [
                    RuleAction(type: .addTag, targetValue: "大文件")
                ]
            )
        ),
        
        // 4. 休眠文件提醒
        PresetRuleTemplate(
            name: "休眠文件提醒",
            description: "30-90 天未访问的文件添加「休眠」标签",
            icon: "moon.fill",
            rule: AutoRule(
                name: "休眠文件提醒",
                matchType: .all,
                conditions: [
                    RuleCondition(field: .lastAccessDays, operator: .greaterThan, value: "30"),
                    RuleCondition(field: .lifecycleStage, operator: .equals, value: "dormant")
                ],
                actions: [
                    RuleAction(type: .addTag, targetValue: "休眠")
                ]
            )
        ),
        
        // 5. 过期候选归档建议
        PresetRuleTemplate(
            name: "过期文件归档建议",
            description: "生命周期状态为「待清理」的文件添加建议标签",
            icon: "exclamationmark.triangle.fill",
            rule: AutoRule(
                name: "过期文件归档建议",
                matchType: .all,
                conditions: [
                    RuleCondition(field: .lifecycleStage, operator: .equals, value: "stale")
                ],
                actions: [
                    RuleAction(type: .addTag, targetValue: "建议归档")
                ]
            )
        )
    ]
}
