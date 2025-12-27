//
//  DesignTokens.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import SwiftUI

/// 设计令牌 - 统一管理视觉设计参数
/// 确保整个应用的一致性和可维护性
public struct DesignTokens {
    // MARK: - 颜色系统

    /// 主要色彩
    public static let primary = Color.blue
    public static let primaryLight = Color.blue.opacity(0.6)
    public static let primaryDark = Color.blue.opacity(0.8)

    /// 次要色彩
    public static let secondary = Color.purple
    public static let secondaryLight = Color.purple.opacity(0.6)
    public static let secondaryDark = Color.purple.opacity(0.8)

    /// 语义色彩
    public static let success = Color.green
    public static let warning = Color.orange
    public static let error = Color.red
    public static let info = Color.cyan

    /// 中性色
    public static let neutral = Color.gray
    public static let neutralLight = Color.gray.opacity(0.3)
    public static let neutralDark = Color.gray.opacity(0.7)

    /// 文本颜色
    public static let textPrimary = Color.primary
    public static let textSecondary = Color.secondary
    public static let textTertiary = Color.secondary.opacity(0.6)
    public static let textDisabled = Color.secondary.opacity(0.3)

    // MARK: - 渐变系统

    /// 极光渐变 - 用于背景装饰
    public static let auroraGradient = LinearGradient(
        colors: [
            Color.blue.opacity(0.3),
            Color.purple.opacity(0.3),
            Color.pink.opacity(0.3)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 成功渐变
    public static let successGradient = LinearGradient(
        colors: [Color.green.opacity(0.3), Color.green.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 警告渐变
    public static let warningGradient = LinearGradient(
        colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - 阴影系统

    public static let cardShadow = ShadowStyle(
        color: Color.black.opacity(0.1),
        radius: 10,
        x: 0,
        y: 4
    )

    public static let cardShadowLarge = ShadowStyle(
        color: Color.black.opacity(0.15),
        radius: 20,
        x: 0,
        y: 8
    )

    public static let buttonShadow = ShadowStyle(
        color: Color.black.opacity(0.2),
        radius: 4,
        x: 0,
        y: 2
    )

    public static let floatingShadow = ShadowStyle(
        color: Color.black.opacity(0.25),
        radius: 15,
        x: 0,
        y: 10
    )

    // MARK: - 间距系统

    public static let spacing = SpacingTokens()

    // MARK: - 圆角系统

    public static let cornerRadius = CornerRadiusTokens()

    // MARK: - 字体系统

    public static let fontScale = FontScaleTokens()

    // MARK: - 动画系统

    public static let animation = AnimationTokens()
}

/// 阴影样式
public struct ShadowStyle: Equatable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

/// 间距令牌
public struct SpacingTokens {
    public let xs: CGFloat = 4
    public let sm: CGFloat = 8
    public let md: CGFloat = 16
    public let lg: CGFloat = 24
    public let xl: CGFloat = 32
    public let xxl: CGFloat = 48
    public let xxxl: CGFloat = 64

    // 快捷访问
    public static let zero: CGFloat = 0
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 32
}

/// 圆角令牌
public struct CornerRadiusTokens {
    public let sm: CGFloat = 6
    public let md: CGFloat = 12
    public let lg: CGFloat = 16
    public let xl: CGFloat = 24
    public let xxl: CGFloat = 32

    // 特殊圆角
    public let circular: CGFloat = 9999 // 用于圆形
    public let pill: CGFloat = 20 // 用于药丸形状
}

/// 字体令牌
public struct FontScaleTokens {
    public let xs: Font = .caption2
    public let sm: Font = .caption
    public let base: Font = .footnote
    public let md: Font = .subheadline
    public let lg: Font = .callout
    public let xl: Font = .headline
    public let xxl: Font = .title3
    public let xxxl: Font = .title2
    public let title: Font = .title
    public let largeTitle: Font = .largeTitle

    // 字体重量
    public enum Weight {
        case light, regular, medium, semibold, bold, heavy, black

        public var fontWeight: Font.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }
    }
}

/// 动画令牌
public struct AnimationTokens {
    /// 快速交互
    public let fast = Animation.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)

    /// 标准动画
    public let standard = Animation.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)

    /// 慢速动画
    public let slow = Animation.spring(response: 0.8, dampingFraction: 0.9, blendDuration: 0.3)

    /// 弹性动画
    public let bouncy = Animation.interpolatingSpring(stiffness: 170, damping: 26)

    /// 淡入淡出
    public let fade = Animation.easeInOut(duration: 0.3)

    /// 旋转
    public let rotate = Animation.linear(duration: 1.0).repeatForever(autoreverses: false)

    // 持续时间
    public struct Duration {
        public static let instant: Double = 0.0
        public static let fast: Double = 0.15
        public static let medium: Double = 0.25
        public static let slow: Double = 0.4
        public static let verySlow: Double = 0.6
    }
}

// MARK: - 便捷扩展

extension Color {
    /// 从十六进制创建颜色
    public init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// 转换为十六进制字符串
    public func toHexString() -> String {
        let uiColor = NSColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        return String(format: "#%06x", rgb)
    }
}

extension Font {
    /// 从大小创建字体
    public static func size(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight)
    }

    /// 标题字体
    public static func titleCustom(size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }

    /// 正文字体
    public static func bodyCustom(size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }

    /// 标签字体
    public static func labelCustom(size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - 暗色模式支持

extension DesignTokens {
    /// 根据当前外观返回适配的颜色
    public static func adaptiveColor(light: Color, dark: Color) -> Color {
        return Color.primary.opacity(0) // 占位符，实际由系统处理
    }

    /// 获取当前主题的颜色
    public static func getColor(for colorScheme: ColorScheme) -> (background: Color, foreground: Color) {
        switch colorScheme {
        case .light:
            return (background: Color.white, foreground: Color.black)
        case .dark:
            return (background: Color.black, foreground: Color.white)
        @unknown default:
            return (background: Color.white, foreground: Color.black)
        }
    }
}
