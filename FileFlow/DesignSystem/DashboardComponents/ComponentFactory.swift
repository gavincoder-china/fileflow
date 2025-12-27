//
//  ComponentFactory.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import SwiftUI

/// 仪表盘组件工厂
/// 用于创建和管理各种类型的组件
public class ComponentFactory {
    public static let shared = ComponentFactory()

    private init() {}

    /// 创建组件
    public func createComponent(type: ComponentType, data: Any? = nil) -> any DashboardComponent {
        switch type {
        case .statsCard:
            return StatsCardComponent(data: data)
        case .activityChart:
            return ActivityChartComponent(data: data)
        case .recentFiles:
            return RecentFilesComponent(data: data)
        case .aiSuggestions:
            return AISuggestionsComponent(data: data)
        case .workflowStatus:
            return WorkflowStatusComponent(data: data)
        case .searchTrends:
            return SearchTrendsComponent(data: data)
        case .fileDistribution:
            return FileDistributionComponent(data: data)
        case .storageUsage:
            return StorageUsageComponent(data: data)
        case .quickActions:
            return QuickActionsComponent(data: data)
        case .notifications:
            return NotificationsComponent(data: data)
        }
    }

    /// 获取所有可用组件类型
    public func getAllComponentTypes() -> [ComponentType] {
        return ComponentType.allCases
    }

    /// 获取组件默认配置
    public func getDefaultConfiguration(for type: ComponentType) -> ComponentConfiguration {
        switch type {
        case .statsCard, .workflowStatus:
            return .compact
        case .activityChart, .fileDistribution:
            return .spacious
        default:
            return .default
        }
    }
}

/// 组件类型枚举
public enum ComponentType: String, CaseIterable, Codable {
    case statsCard = "统计卡片"
    case activityChart = "活动图表"
    case recentFiles = "最近文件"
    case aiSuggestions = "AI 建议"
    case workflowStatus = "工作流状态"
    case searchTrends = "搜索趋势"
    case fileDistribution = "文件分布"
    case storageUsage = "存储使用"
    case quickActions = "快捷操作"
    case notifications = "通知中心"

    /// 组件图标
    public var icon: String {
        switch self {
        case .statsCard:
            return "chart.bar"
        case .activityChart:
            return "chart.line.uptrend.xyaxis"
        case .recentFiles:
            return "doc.clock"
        case .aiSuggestions:
            return "brain.head.profile"
        case .workflowStatus:
            return "gearshape.2"
        case .searchTrends:
            return "magnifyingglass"
        case .fileDistribution:
            return "folder"
        case .storageUsage:
            return "internaldrive"
        case .quickActions:
            return "bolt.circle"
        case .notifications:
            return "bell"
        }
    }

    /// 默认大小
    public var defaultSize: ComponentSize {
        switch self {
        case .statsCard, .aiSuggestions, .quickActions, .notifications:
            return .small
        case .activityChart, .fileDistribution, .storageUsage:
            return .large
        case .recentFiles, .workflowStatus:
            return .medium
        case .searchTrends:
            return .fullWidth
        }
    }

    /// 是否支持实时更新
    public var supportsRealTimeUpdate: Bool {
        switch self {
        case .statsCard, .activityChart, .storageUsage, .notifications:
            return true
        default:
            return false
        }
    }
}

/// 组件数据模型
public struct ComponentData {
    public let type: ComponentType
    public let rawData: Any?

    public init(type: ComponentType, rawData: Any? = nil) {
        self.type = type
        self.rawData = rawData
    }
}

/// 统计卡片组件
public struct StatsCardComponent: DashboardComponent {
    public var id = UUID()
    public var title: String
    public var icon: String
    public var description: String = ""
    public var size: ComponentSize
    public var data: Any?
    public var view: AnyView
    public var isInteractive: Bool = true
    public var priority: Int = 1
    public var needsRealTimeUpdate: Bool = false
    public var refreshInterval: TimeInterval = 60

    public var currentValue: Int
    public var previousValue: Int?
    public var trend: Trend
    public var unit: String

    public enum Trend {
        case up(Int) // 上升
        case down(Int) // 下降
        case stable // 稳定
        case unknown // 未知

        public var percentage: Double? {
            switch self {
            case .up(let value):
                return Double(value)
            case .down(let value):
                return -Double(value)
            default:
                return nil
            }
        }

        public var color: Color {
            switch self {
            case .up:
                return DesignTokens.success
            case .down:
                return DesignTokens.error
            case .stable:
                return DesignTokens.warning
            case .unknown:
                return DesignTokens.neutral
            }
        }

        public var icon: String {
            switch self {
            case .up:
                return "arrow.up.right"
            case .down:
                return "arrow.down.right"
            case .stable:
                return "arrow.right"
            case .unknown:
                return "questionmark"
            }
        }
    }

    public init(data: Any? = nil) {
        if let statsData = data as? StatsCardData {
            self.title = statsData.title
            self.icon = statsData.icon
            self.currentValue = statsData.currentValue
            self.previousValue = statsData.previousValue
            self.trend = statsData.trend
            self.unit = statsData.unit
        } else {
            self.title = "默认统计"
            self.icon = "chart.bar"
            self.currentValue = 0
            self.trend = .unknown
            self.unit = ""
        }

        self.size = .small
        self.view = AnyView(StatsCardView(component: self))
    }

    public mutating func updateData(_ data: Any?) {
        if let statsData = data as? StatsCardData {
            self.title = statsData.title
            self.icon = statsData.icon
            self.currentValue = statsData.currentValue
            self.previousValue = statsData.previousValue
            self.trend = statsData.trend
            self.unit = statsData.unit
        }
    }

    public mutating func refresh() async {
        // 刷新逻辑
    }
}

/// 统计卡片数据
public struct StatsCardData {
    public let title: String
    public let icon: String
    public let currentValue: Int
    public let previousValue: Int?
    public let trend: StatsCardComponent.Trend
    public let unit: String

    public init(
        title: String,
        icon: String,
        currentValue: Int,
        previousValue: Int? = nil,
        trend: StatsCardComponent.Trend = .unknown,
        unit: String = ""
    ) {
        self.title = title
        self.icon = icon
        self.currentValue = currentValue
        self.previousValue = previousValue
        self.trend = trend
        self.unit = unit
    }
}

/// 统计卡片视图
struct StatsCardView: View {
    let component: StatsCardComponent

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
            HStack {
                Image(systemName: component.icon)
                    .font(.title2)
                    .foregroundColor(DesignTokens.primary)

                Spacer()

                if let percentage = component.trend.percentage {
                    HStack(spacing: 4) {
                        Image(systemName: component.trend.icon)
                            .font(.caption)
                            .foregroundColor(component.trend.color)

                        Text("\(Int(abs(percentage)))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(component.trend.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(component.trend.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.sm))
                }
            }

            Text("\(component.currentValue)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(DesignTokens.textPrimary)

            Text(component.title)
                .font(DesignTokens.fontScale.md)
                .foregroundColor(DesignTokens.textSecondary)

            // 迷你图表（可选）
            if let previousValue = component.previousValue {
                MiniChartView(data: generateSampleData(from: previousValue, to: component.currentValue))
                    .frame(height: 40)
                    .padding(.top, DesignTokens.spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generateSampleData(from: Int, to: Int) -> [Double] {
        // 生成示例数据
        return [20, 35, 15, 45, 30, 60, 40, Double(to)]
    }
}

/// 迷你图表组件
struct MiniChartView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let step = width / CGFloat(max(data.count - 1, 1))

                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let normalizedValue = (value - (data.min() ?? 0)) / ((data.max() ?? 1) - (data.min() ?? 0))
                    let y = height - normalizedValue * height

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(DesignTokens.primary, lineWidth: 2)
            .fill(
                LinearGradient(
                    colors: [DesignTokens.primary.opacity(0.3), DesignTokens.primary.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - 其他组件占位实现

/// 活动图表组件
public struct ActivityChartComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "活动图表"
    public var icon: String = "chart.line.uptrend.xyaxis"
    public var description: String = "最近7天活动趋势"
    public var size: ComponentSize = .large
    public var data: Any?
    public var view: AnyView = AnyView(Text("Activity Chart"))
    public var isInteractive: Bool = true
    public var priority: Int = 2
    public var needsRealTimeUpdate: Bool = true
    public var refreshInterval: TimeInterval = 300

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 最近文件组件
public struct RecentFilesComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "最近文件"
    public var icon: String = "doc.clock"
    public var description: String = "最近访问的文件"
    public var size: ComponentSize = .medium
    public var data: Any?
    public var view: AnyView = AnyView(Text("Recent Files"))
    public var isInteractive: Bool = true
    public var priority: Int = 3
    public var needsRealTimeUpdate: Bool = false
    public var refreshInterval: TimeInterval = 60

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// AI 建议组件
public struct AISuggestionsComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "AI 建议"
    public var icon: String = "brain.head.profile"
    public var description: String = "智能推荐"
    public var size: ComponentSize = .small
    public var data: Any?
    public var view: AnyView = AnyView(Text("AI Suggestions"))
    public var isInteractive: Bool = true
    public var priority: Int = 4
    public var needsRealTimeUpdate: Bool = false
    public var refreshInterval: TimeInterval = 300

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 工作流状态组件
public struct WorkflowStatusComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "工作流状态"
    public var icon: String = "gearshape.2"
    public var description: String = "后台任务监控"
    public var size: ComponentSize = .medium
    public var data: Any?
    public var view: AnyView = AnyView(Text("Workflow Status"))
    public var isInteractive: Bool = true
    public var priority: Int = 5
    public var needsRealTimeUpdate: Bool = true
    public var refreshInterval: TimeInterval = 10

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 搜索趋势组件
public struct SearchTrendsComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "搜索趋势"
    public var icon: String = "magnifyingglass"
    public var description: String = "热门搜索关键词"
    public var size: ComponentSize = .fullWidth
    public var data: Any?
    public var view: AnyView = AnyView(Text("Search Trends"))
    public var isInteractive: Bool = true
    public var priority: Int = 6
    public var needsRealTimeUpdate: Bool = false
    public var refreshInterval: TimeInterval = 600

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 文件分布组件
public struct FileDistributionComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "文件分布"
    public var icon: String = "folder"
    public var description: String = "按类型分布"
    public var size: ComponentSize = .large
    public var data: Any?
    public var view: AnyView = AnyView(Text("File Distribution"))
    public var isInteractive: Bool = true
    public var priority: Int = 7
    public var needsRealTimeUpdate: Bool = false
    public var refreshInterval: TimeInterval = 300

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 存储使用组件
public struct StorageUsageComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "存储使用"
    public var icon: String = "internaldrive"
    public var description: String = "磁盘空间监控"
    public var size: ComponentSize = .large
    public var data: Any?
    public var view: AnyView = AnyView(Text("Storage Usage"))
    public var isInteractive: Bool = true
    public var priority: Int = 8
    public var needsRealTimeUpdate: Bool = true
    public var refreshInterval: TimeInterval = 60

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 快捷操作组件
public struct QuickActionsComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "快捷操作"
    public var icon: String = "bolt.circle"
    public var description: String = "常用功能"
    public var size: ComponentSize = .small
    public var data: Any?
    public var view: AnyView = AnyView(Text("Quick Actions"))
    public var isInteractive: Bool = true
    public var priority: Int = 9
    public var needsRealTimeUpdate: Bool = false
    public var refreshInterval: TimeInterval = 0

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}

/// 通知中心组件
public struct NotificationsComponent: DashboardComponent {
    public var id = UUID()
    public var title: String = "通知中心"
    public var icon: String = "bell"
    public var description: String = "系统通知"
    public var size: ComponentSize = .small
    public var data: Any?
    public var view: AnyView = AnyView(Text("Notifications"))
    public var isInteractive: Bool = true
    public var priority: Int = 10
    public var needsRealTimeUpdate: Bool = true
    public var refreshInterval: TimeInterval = 5

    public mutating func updateData(_ data: Any?) {}
    public mutating func refresh() async {}
}
