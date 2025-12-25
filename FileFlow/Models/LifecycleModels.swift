//
//  LifecycleModels.swift
//  FileFlow
//
//  文件生命周期管理模型
//  基于 PARA 方法论的文件状态流转系统
//

import Foundation
import SwiftUI

// MARK: - File Lifecycle Stage
/// 文件生命周期阶段
/// 追踪文件的活跃状态，用于自动归档建议
enum FileLifecycleStage: String, Codable, CaseIterable, Identifiable {
    case active = "active"       // 🟢 活跃 - 30天内有访问
    case dormant = "dormant"     // 🟡 休眠 - 30-90天未访问
    case stale = "stale"         // 🟠 过期候选 - 90天以上未访问
    case archived = "archived"   // ⚫ 已归档 - 已明确归档
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .active: return "活跃"
        case .dormant: return "休眠"
        case .stale: return "待清理"
        case .archived: return "已归档"
        }
    }
    
    var icon: String {
        switch self {
        case .active: return "circle.fill"
        case .dormant: return "moon.fill"
        case .stale: return "exclamationmark.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .active: return .green
        case .dormant: return .yellow
        case .stale: return .orange
        case .archived: return .gray
        }
    }
    
    var description: String {
        switch self {
        case .active: return "近期使用过的文件"
        case .dormant: return "一段时间未使用"
        case .stale: return "长期未使用，建议归档"
        case .archived: return "已完成归档"
        }
    }
    
    /// 根据最后访问时间计算生命周期阶段
    static func calculateStage(lastAccessedAt: Date?, category: PARACategory) -> FileLifecycleStage {
        // 如果已经在 Archives，直接返回 archived
        if category == .archives {
            return .archived
        }
        
        guard let lastAccess = lastAccessedAt else {
            return .active // 新文件默认为活跃
        }
        
        let daysSinceAccess = Calendar.current.dateComponents([.day], from: lastAccess, to: Date()).day ?? 0
        
        switch daysSinceAccess {
        case 0..<30:
            return .active
        case 30..<90:
            return .dormant
        default:
            return .stale
        }
    }
}

// MARK: - Transition Reason
/// 文件流转原因
/// 记录为什么文件从一个分类移动到另一个分类
enum TransitionReason: String, Codable, CaseIterable, Identifiable {
    // Projects 相关
    case projectCompleted = "project_completed"        // 项目完成
    case projectCanceled = "project_canceled"          // 项目取消
    case projectPaused = "project_paused"              // 项目暂停
    case projectEvolved = "project_evolved"            // 项目演变为责任
    case projectOutputReuse = "project_output_reuse"   // 项目产出复用
    
    // Areas 相关
    case areaResponsibilityEnded = "area_ended"        // 领域职责结束
    case areaInterestLost = "area_interest_lost"       // 不再持续关注
    case areaDemoted = "area_demoted"                  // 领域降级为参考
    
    // Resources 相关
    case resourceActivated = "resource_activated"       // 资源被激活使用
    case resourcePromoted = "resource_promoted"         // 资源固化为标准
    case resourceOutdated = "resource_outdated"         // 资源过期
    case resourceConsumed = "resource_consumed"         // 资源已消费完毕
    
    // 通用
    case userManual = "user_manual"                     // 用户手动操作
    case autoRuleTriggered = "auto_rule"                // 自动规则触发
    case aiSuggestion = "ai_suggestion"                 // AI 建议
    case inactivityTimeout = "inactivity"               // 长期未使用
    case initialImport = "initial_import"               // 初始导入
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .projectCompleted: return "项目完成"
        case .projectCanceled: return "项目取消"
        case .projectPaused: return "项目暂停"
        case .projectEvolved: return "项目演变为责任"
        case .projectOutputReuse: return "项目产出复用"
        case .areaResponsibilityEnded: return "领域职责结束"
        case .areaInterestLost: return "不再持续关注"
        case .areaDemoted: return "领域降级为参考"
        case .resourceActivated: return "资源被激活使用"
        case .resourcePromoted: return "资源固化为标准"
        case .resourceOutdated: return "资源过期"
        case .resourceConsumed: return "资源已消费完毕"
        case .userManual: return "用户手动操作"
        case .autoRuleTriggered: return "自动规则触发"
        case .aiSuggestion: return "AI 建议"
        case .inactivityTimeout: return "长期未使用"
        case .initialImport: return "初始导入"
        }
    }
    
    var icon: String {
        switch self {
        case .projectCompleted: return "checkmark.circle.fill"
        case .projectCanceled: return "xmark.circle.fill"
        case .projectPaused: return "pause.circle.fill"
        case .projectEvolved: return "arrow.up.circle.fill"
        case .projectOutputReuse: return "doc.on.doc.fill"
        case .areaResponsibilityEnded: return "person.fill.xmark"
        case .areaInterestLost: return "heart.slash.fill"
        case .areaDemoted: return "arrow.down.circle.fill"
        case .resourceActivated: return "bolt.fill"
        case .resourcePromoted: return "star.fill"
        case .resourceOutdated: return "clock.badge.xmark.fill"
        case .resourceConsumed: return "checkmark.seal.fill"
        case .userManual: return "hand.tap.fill"
        case .autoRuleTriggered: return "gearshape.fill"
        case .aiSuggestion: return "brain.fill"
        case .inactivityTimeout: return "zzz"
        case .initialImport: return "plus.circle.fill"
        }
    }
    
    /// 根据来源和目标分类返回推荐的流转原因列表
    static func suggestedReasons(from: PARACategory, to: PARACategory) -> [TransitionReason] {
        switch (from, to) {
        case (.projects, .archives):
            return [.projectCompleted, .projectCanceled, .projectPaused, .inactivityTimeout]
        case (.projects, .resources):
            return [.projectOutputReuse, .userManual]
        case (.projects, .areas):
            return [.projectEvolved, .userManual]
        case (.areas, .archives):
            return [.areaResponsibilityEnded, .areaInterestLost, .inactivityTimeout]
        case (.areas, .resources):
            return [.areaDemoted, .userManual]
        case (.resources, .projects):
            return [.resourceActivated, .userManual]
        case (.resources, .areas):
            return [.resourcePromoted, .userManual]
        case (.resources, .archives):
            return [.resourceOutdated, .resourceConsumed, .inactivityTimeout]
        case (.archives, _):
            return [.resourceActivated, .userManual]
        default:
            return [.userManual, .autoRuleTriggered, .aiSuggestion]
        }
    }
}

// MARK: - File Transition Record
/// 文件流转记录
/// 追踪文件在 PARA 分类间的移动历史
struct FileTransition: Identifiable, Codable, Hashable {
    let id: UUID
    let fileId: UUID
    let fileName: String
    let fromCategory: PARACategory
    let toCategory: PARACategory
    let fromSubcategory: String?
    let toSubcategory: String?
    let reason: TransitionReason
    let notes: String?
    let triggeredAt: Date
    let isAutomatic: Bool
    let confirmedByUser: Bool
    
    init(
        id: UUID = UUID(),
        fileId: UUID,
        fileName: String,
        from: PARACategory,
        to: PARACategory,
        fromSub: String? = nil,
        toSub: String? = nil,
        reason: TransitionReason,
        notes: String? = nil,
        isAutomatic: Bool = false,
        confirmedByUser: Bool = true
    ) {
        self.id = id
        self.fileId = fileId
        self.fileName = fileName
        self.fromCategory = from
        self.toCategory = to
        self.fromSubcategory = fromSub
        self.toSubcategory = toSub
        self.reason = reason
        self.notes = notes
        self.triggeredAt = Date()
        self.isAutomatic = isAutomatic
        self.confirmedByUser = confirmedByUser
    }
    
    /// 格式化的流转描述
    var transitionDescription: String {
        let fromPath = fromSubcategory.map { "\(fromCategory.displayName)/\($0)" } ?? fromCategory.displayName
        let toPath = toSubcategory.map { "\(toCategory.displayName)/\($0)" } ?? toCategory.displayName
        return "\(fromPath) → \(toPath)"
    }
    
    /// 格式化的时间描述
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: triggeredAt)
    }
}

// MARK: - Lifecycle Cleanup Suggestion
/// 清理建议
/// 用于向用户展示需要处理的过期文件
struct LifecycleCleanupSuggestion: Identifiable {
    let id: UUID
    let file: ManagedFile
    let stage: FileLifecycleStage
    let daysSinceAccess: Int
    let suggestedAction: SuggestedAction
    
    enum SuggestedAction: String, CaseIterable {
        case archive = "归档"
        case review = "检查"
        case delete = "删除"
        case keep = "保留"
        
        var icon: String {
            switch self {
            case .archive: return "archivebox.fill"
            case .review: return "eye.fill"
            case .delete: return "trash.fill"
            case .keep: return "checkmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .archive: return .gray
            case .review: return .blue
            case .delete: return .red
            case .keep: return .green
            }
        }
    }
    
    init(file: ManagedFile, lastAccessedAt: Date?) {
        self.id = file.id
        self.file = file
        
        let lastAccess = lastAccessedAt ?? file.importedAt
        self.daysSinceAccess = Calendar.current.dateComponents([.day], from: lastAccess, to: Date()).day ?? 0
        self.stage = FileLifecycleStage.calculateStage(lastAccessedAt: lastAccessedAt, category: file.category)
        
        // 根据阶段和天数建议操作
        switch stage {
        case .stale:
            self.suggestedAction = daysSinceAccess > 180 ? .archive : .review
        case .dormant:
            self.suggestedAction = .review
        case .active:
            self.suggestedAction = .keep
        case .archived:
            self.suggestedAction = .keep
        }
    }
}

// MARK: - Project Archive Options
/// 项目归档选项
/// 用于项目完成时的归档向导
enum ProjectArchiveStrategy: String, CaseIterable, Identifiable {
    case archiveAll = "archive_all"          // 整体归档
    case smartArchive = "smart_archive"      // 智能归档（提取可复用资源）
    case markComplete = "mark_complete"      // 仅标记完成
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .archiveAll: return "整体归档"
        case .smartArchive: return "智能归档"
        case .markComplete: return "仅标记完成"
        }
    }
    
    var description: String {
        switch self {
        case .archiveAll: return "将所有项目文件移至归档目录"
        case .smartArchive: return "提取可复用资源后归档剩余文件"
        case .markComplete: return "暂不移动文件，仅标记项目状态"
        }
    }
    
    var icon: String {
        switch self {
        case .archiveAll: return "archivebox.fill"
        case .smartArchive: return "wand.and.stars"
        case .markComplete: return "checkmark.circle"
        }
    }
}

// MARK: - Reusable Asset Detection
/// 可复用资源检测结果
/// AI 分析项目文件时识别出的可复用资产
struct ReusableAssetDetection: Identifiable {
    let id: UUID
    let file: ManagedFile
    let assetType: AssetType
    let suggestedPath: String  // e.g., "Resources/Templates"
    let confidence: Double
    
    enum AssetType: String, CaseIterable {
        case template = "模板"
        case code = "代码"
        case design = "设计"
        case documentation = "文档"
        case research = "研究"
        case other = "其他"
        
        var icon: String {
            switch self {
            case .template: return "doc.badge.plus"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .design: return "paintbrush.fill"
            case .documentation: return "doc.text.fill"
            case .research: return "magnifyingglass"
            case .other: return "folder.fill"
            }
        }
        
        var suggestedSubcategory: String {
            switch self {
            case .template: return "Templates"
            case .code: return "Code"
            case .design: return "Design"
            case .documentation: return "Documentation"
            case .research: return "Research"
            case .other: return "General"
            }
        }
    }
    
    init(file: ManagedFile, assetType: AssetType, confidence: Double = 0.8) {
        self.id = UUID()
        self.file = file
        self.assetType = assetType
        self.suggestedPath = "Resources/\(assetType.suggestedSubcategory)"
        self.confidence = confidence
    }
}
