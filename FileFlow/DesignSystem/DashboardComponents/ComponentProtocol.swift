//
//  ComponentProtocol.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import SwiftUI

/// 仪表盘组件协议
/// 所有仪表盘组件必须遵守此协议
public protocol DashboardComponent: Identifiable, Equatable {
    /// 组件 ID
    var id: UUID { get }

    /// 组件标题
    var title: String { get }

    /// 组件图标
    var icon: String { get }

    /// 组件描述
    var description: String { get }

    /// 组件大小
    var size: ComponentSize { get }

    /// 组件数据
    var data: Any? { get }

    /// 组件视图
    var view: AnyView { get }

    /// 组件是否可交互
    var isInteractive: Bool { get }

    /// 组件优先级（影响渲染顺序）
    var priority: Int { get }

    /// 组件是否需要实时更新
    var needsRealTimeUpdate: Bool { get }

    /// 组件刷新间隔（秒）
    var refreshInterval: TimeInterval { get }

    /// 更新组件数据
    mutating func updateData(_ data: Any?)

    /// 刷新组件
    mutating func refresh() async
}

/// 组件大小枚举
public enum ComponentSize: Equatable {
    case small
    case medium
    case large
    case fullWidth
    case custom(width: Int, height: Int) // 自定义尺寸

    /// 返回网格列数
    public var gridColumnCount: Int {
        switch self {
        case .small:
            return 2
        case .medium:
            return 3
        case .large:
            return 4
        case .fullWidth:
            return 6
        case .custom(let width, _):
            return width
        }
    }

    /// 返回网格行数
    public var gridRowCount: Int {
        switch self {
        case .small:
            return 2
        case .medium:
            return 3
        case .large:
            return 4
        case .fullWidth:
            return 2
        case .custom(_, let height):
            return height
        }
    }

    /// 估算高度
    public func estimatedHeight() -> CGFloat {
        switch self {
        case .small:
            return 150
        case .medium:
            return 200
        case .large:
            return 300
        case .fullWidth:
            return 200
        case .custom(_, let height):
            return CGFloat(height * 60) // 每行约 60pt
        }
    }
}

/// 组件配置
public struct ComponentConfiguration {
    public let cornerRadius: CGFloat
    public let padding: CGFloat
    public let material: Material
    public let shadow: ShadowStyle?
    public let border: Color?
    public let borderWidth: CGFloat?

    public init(
        cornerRadius: CGFloat = DesignTokens.cornerRadius.md,
        padding: CGFloat = DesignTokens.spacing.md,
        material: Material = .regularMaterial,
        shadow: ShadowStyle? = DesignTokens.cardShadow,
        border: Color? = nil,
        borderWidth: CGFloat? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.material = material
        self.shadow = shadow
        self.border = border
        self.borderWidth = borderWidth
    }

    public static let `default` = ComponentConfiguration()
    public static let compact = ComponentConfiguration(
        cornerRadius: DesignTokens.cornerRadius.sm,
        padding: DesignTokens.spacing.sm
    )
    public static let spacious = ComponentConfiguration(
        cornerRadius: DesignTokens.cornerRadius.lg,
        padding: DesignTokens.spacing.lg
    )
}

/// 组件容器
public struct ComponentContainer<Content: View>: View {
    let component: any DashboardComponent
    let configuration: ComponentConfiguration
    let content: Content

    public init(
        component: any DashboardComponent,
        configuration: ComponentConfiguration = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.component = component
        self.configuration = configuration
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.sm) {
            // 组件标题栏
            ComponentHeader(
                title: component.title,
                icon: component.icon,
                description: component.description,
                isInteractive: component.isInteractive
            )

            Spacer()

            // 组件内容
            content
        }
        .padding(configuration.padding)
        .frame(
            minWidth: minWidth(for: component.size),
            minHeight: component.size.estimatedHeight(),
            alignment: .topLeading
        )
        .glass(
            cornerRadius: configuration.cornerRadius,
            material: configuration.material,
            shadow: configuration.shadow,
            border: configuration.border,
            borderWidth: configuration.borderWidth
        )
        .contentShape(RoundedRectangle(cornerRadius: configuration.cornerRadius))
        .contextMenu {
            ComponentContextMenu(component: component)
        }
        .animation(DesignTokens.animation.standard, value: component.id)
    }

    private func minWidth(for size: ComponentSize) -> CGFloat {
        let screenWidth = NSScreen.main?.frame.width ?? 1200
        let totalColumns = 6
        let columnWidth = (screenWidth - CGFloat(totalColumns + 1) * DesignTokens.spacing.md) / CGFloat(totalColumns)

        return columnWidth * CGFloat(size.gridColumnCount) + CGFloat(size.gridColumnCount - 1) * DesignTokens.spacing.md
    }
}

/// 组件标题栏
struct ComponentHeader: View {
    let title: String
    let icon: String
    let description: String
    let isInteractive: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(DesignTokens.primary)

            VStack(alignment: .leading) {
                Text(title)
                    .font(DesignTokens.fontScale.lg)
                    .fontWeight(.semibold)

                if !description.isEmpty {
                    Text(description)
                        .font(DesignTokens.fontScale.sm)
                        .foregroundColor(DesignTokens.textTertiary)
                }
            }

            Spacer()

            if isInteractive {
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline)
                    .foregroundColor(DesignTokens.textTertiary)
            }
        }
    }
}

/// 组件上下文菜单
struct ComponentContextMenu<Component: DashboardComponent>: View {
    let component: Component

    var body: some View {
        Button("刷新") {
            Task {
                // 刷新逻辑
            }
        }

        Button("移动到顶部") {
            // 移动逻辑
        }

        Divider()

        Button("移除") {
            // 移除逻辑
        }
        .foregroundColor(.red)
    }
}

/// 组件刷新策略
public enum ComponentRefreshStrategy {
    /// 永不刷新
    case never
    /// 手动刷新
    case manual
    /// 定时刷新
    case interval(TimeInterval)
    /// 基于条件刷新
    case condition(() -> Bool)
    /// 实时更新
    case realTime

    public var isRealTime: Bool {
        switch self {
        case .realTime:
            return true
        default:
            return false
        }
    }
}

/// 组件事件
public struct ComponentEvent {
    public let id: UUID
    public let type: EventType
    public let timestamp: Date
    public let componentId: UUID
    public let data: [String: Any]

    public init(type: EventType, componentId: UUID, data: [String: Any] = [:]) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.componentId = componentId
        self.data = data
    }

    public enum EventType {
        case tapped
        case refreshed
        case dataChanged
        case error(Error)
        case custom(String)
    }
}

/// 组件错误类型
public enum ComponentError: Error, LocalizedError {
    case invalidData
    case networkError(Error)
    case renderingError(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "组件数据无效"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .renderingError(let message):
            return "渲染错误: \(message)"
        case .configurationError(let message):
            return "配置错误: \(message)"
        }
    }
}

/// 组件状态
public enum ComponentState {
    case idle
    case loading
    case loaded
    case error(Error)
    case updating

    public var isLoading: Bool {
        switch self {
        case .loading, .updating:
            return true
        default:
            return false
        }
    }

    public var hasError: Bool {
        switch self {
        case .error:
            return true
        default:
            return false
        }
    }
}
