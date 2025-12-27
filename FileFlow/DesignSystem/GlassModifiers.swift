//
//  GlassModifiers.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import SwiftUI

/// 玻璃态效果修饰符
/// 提供毛玻璃背景、圆角和阴影的统一实现
public struct GlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let shadow: ShadowStyle?
    let border: Color?
    let borderWidth: CGFloat?

    public init(
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.cardShadow,
        border: Color? = nil,
        borderWidth: CGFloat? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadow = shadow
        self.border = border
        self.borderWidth = borderWidth
    }

    public func body(content: Content) -> some View {
        content
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                Group {
                    if let border = border, let borderWidth = borderWidth {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(border, lineWidth: borderWidth)
                    }
                }
            )
            .shadow(
                color: shadow?.color ?? .clear,
                radius: shadow?.radius ?? 0,
                x: shadow?.x ?? 0,
                y: shadow?.y ?? 0
            )
    }
}

/// 玻璃态容器视图
public struct GlassContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let material: Material
    let shadow: ShadowStyle?
    let border: Color?
    let borderWidth: CGFloat?
    let content: Content

    public init(
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.cardShadow,
        border: Color? = nil,
        borderWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadow = shadow
        self.border = border
        self.borderWidth = borderWidth
        self.content = content()
    }

    public var body: some View {
        content
            .modifier(GlassModifier(
                cornerRadius: cornerRadius,
                material: material,
                shadow: shadow,
                border: border,
                borderWidth: borderWidth
            ))
    }
}

/// 玻璃态按钮样式
public struct GlassButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let material: Material
    let shadow: ShadowStyle?

    public init(
        cornerRadius: CGFloat = DesignTokens.cornerRadius.sm,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.buttonShadow
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadow = shadow
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, DesignTokens.spacing.lg)
            .padding(.vertical, DesignTokens.spacing.md)
            .background(
                configuration.isPressed ? material.opacity(0.8) : material
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: configuration.isPressed ? shadow?.color.opacity(0.5) : shadow?.color ?? .clear,
                radius: configuration.isPressed ? (shadow?.radius ?? 0) * 0.5 : shadow?.radius ?? 0,
                x: shadow?.x ?? 0,
                y: configuration.isPressed ? (shadow?.y ?? 0) + 1 : shadow?.y ?? 0
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignTokens.animation.fast, value: configuration.isPressed)
    }
}

/// 玻璃态卡片视图
public struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let material: Material
    let shadow: ShadowStyle?
    let border: Color?
    let borderWidth: CGFloat?
    let content: Content

    public init(
        padding: CGFloat = DesignTokens.spacing.lg,
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.cardShadow,
        border: Color? = nil,
        borderWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadow = shadow
        self.border = border
        self.borderWidth = borderWidth
        self.content = content()
    }

    public var body: some View {
        GlassContainer(
            cornerRadius: cornerRadius,
            material: material,
            shadow: shadow,
            border: border,
            borderWidth: borderWidth
        ) {
            content
                .padding(padding)
        }
    }
}

/// 玻璃态输入框样式
public struct GlassTextFieldStyle: TextFieldStyle {
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(DesignTokens.spacing.md)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.sm))
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

/// 渐变玻璃态效果
public struct GradientGlassModifier: ViewModifier {
    let gradient: LinearGradient
    let cornerRadius: CGFloat
    let opacity: Double

    public init(
        gradient: LinearGradient = DesignTokens.auroraGradient,
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        opacity: Double = 0.1
    ) {
        self.gradient = gradient
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }

    public func body(content: Content) -> some View {
        content
            .background(gradient.opacity(opacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        gradient,
                        lineWidth: 1
                    )
                    .blendMode(.overlay)
            )
    }
}

// MARK: - View 扩展

extension View {
    /// 应用玻璃态效果
    public func glass(
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.cardShadow,
        border: Color? = nil,
        borderWidth: CGFloat? = nil
    ) -> some View {
        self.modifier(GlassModifier(
            cornerRadius: cornerRadius,
            material: material,
            shadow: shadow,
            border: border,
            borderWidth: borderWidth
        ))
    }

    /// 玻璃态卡片
    public func glassCard(
        padding: CGFloat = DesignTokens.spacing.lg,
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.cardShadow,
        border: Color? = nil,
        borderWidth: CGFloat? = nil
    ) -> some View {
        GlassCard(
            padding: padding,
            cornerRadius: cornerRadius,
            material: material,
            shadow: shadow,
            border: border,
            borderWidth: borderWidth
        ) {
            self
        }
    }

    /// 渐变玻璃态效果
    public func gradientGlass(
        gradient: LinearGradient = DesignTokens.auroraGradient,
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        opacity: Double = 0.1
    ) -> some View {
        self.modifier(GradientGlassModifier(
            gradient: gradient,
            cornerRadius: cornerRadius,
            opacity: opacity
        ))
    }

    /// 悬浮效果（鼠标悬停时）
    public func hoverEffect(
        shadow: ShadowStyle = DesignTokens.floatingShadow,
        scale: CGFloat = 1.02
    ) -> some View {
        self.scaleEffect(1.0)
            .onHover { hovering in
                withAnimation(DesignTokens.animation.fast) {
                    if hovering {
                        self.scaleEffect(scale)
                    } else {
                        self.scaleEffect(1.0)
                    }
                }
            }
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }

    /// 脉冲动画
    public func pulse(
        color: Color = DesignTokens.primary,
        scale: CGFloat = 1.05,
        duration: Double = 1.5
    ) -> some View {
        self
            .overlay(
                Circle()
                    .stroke(color.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.0)
                    .animation(
                        Animation.easeInOut(duration: duration)
                            .repeatForever(autoreverses: true),
                        value: UUID()
                    )
            )
            .scaleEffect(scale)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: UUID()
            )
    }

    /// 闪光效果
    public func shimmer() -> some View {
        self
            .modifier(ShimmerModifier())
    }
}

/// 闪光效果修饰符
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        .white.opacity(0.4),
                        .clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(45))
                .offset(x: phase * 200)
                .blendMode(.overlay)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

// MARK: - 便捷构造函数

extension Button {
    /// 玻璃态按钮
    public init(
        title: String,
        icon: String? = nil,
        style: GlassButtonStyle = GlassButtonStyle(),
        action: @escaping () -> Void
    ) where Label == Text {
        self.init(action: action) {
            HStack(spacing: DesignTokens.spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
        }
        .buttonStyle(style)
    }
}

// MARK: - 使用示例

struct GlassComponentsDemo: View {
    var body: some View {
        VStack(spacing: DesignTokens.spacing.lg) {
            // 玻璃态卡片
            Text("Glass Card")
                .font(DesignTokens.fontScale.xl)
                .glassCard {
                    Text("This is a glass card")
                }

            // 玻璃态按钮
            Button("Glass Button") {}
                .buttonStyle(GlassButtonStyle())

            // 渐变玻璃态
            Text("Gradient Glass")
                .padding()
                .gradientGlass()

            // 悬浮效果
            Text("Hover Effect")
                .padding()
                .glass()
                .hoverEffect()

            // 闪光效果
            Text("Shimmer")
                .padding()
                .glass()
                .shimmer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.auroraGradient)
    }
}
