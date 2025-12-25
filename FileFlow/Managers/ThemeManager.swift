//
//  ThemeManager.swift
//  FileFlow
//
//  主题管理器 - 管理应用外观模式和强调色
//

import SwiftUI

// MARK: - App Theme
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled.inverse"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - App Accent Color
enum AppAccent: String, CaseIterable, Identifiable {
    case blue = "默认为蓝"
    case purple = "优雅紫"
    case pink = "活力粉"
    case teal = "清新青"
    case orange = "温暖橙"
    case indigo = "静谧靛"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .teal: return .teal
        case .orange: return .orange
        case .indigo: return .indigo
        }
    }
    
    var icon: String { "circle.fill" }
}

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("app_theme") var currentTheme: AppTheme = .system
    @AppStorage("app_accent") var currentAccent: AppAccent = .blue
    
    private init() {}
    
    /// 获取当前强调色
    var accentColor: Color {
        currentAccent.color
    }
    
    /// 获取当前配色方案（用于 .preferredColorScheme）
    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }
}
