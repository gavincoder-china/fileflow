import SwiftUI

/// Defines the mode for batch file uploads.
enum UploadMode: String, CaseIterable, Identifiable {
    case smart   // AI recommends everything (category, folder, tags, filename)
    case manual  // User picks folder/tags, AI only suggests tags and generates summary
    case mirror  // Preserve original folder structure, AI tags only
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .smart: return "brain.head.profile"
        case .manual: return "folder.badge.person.crop"
        case .mirror: return "rectangle.on.rectangle"
        }
    }
    
    var title: String {
        switch self {
        case .smart: return "智能模式"
        case .manual: return "手动模式"
        case .mirror: return "镜像模式"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .smart: return "AI 全权推荐"
        case .manual: return "我来选择目标"
        case .mirror: return "保留原有结构"
        }
    }
    
    var color: Color {
        switch self {
        case .smart: return .blue
        case .manual: return .purple
        case .mirror: return .teal
        }
    }
}
