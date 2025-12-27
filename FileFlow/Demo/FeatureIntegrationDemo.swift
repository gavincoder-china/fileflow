//
//  FeatureIntegrationDemo.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import SwiftUI
import VectorIndexKit
import ProcessingPipeline
import DesignSystem

/// 功能集成演示
/// 展示向量索引、增量处理、设计系统的整合使用
struct FeatureIntegrationDemo: View {
    @StateObject private var vectorStorage = VectorStorageManager.shared
    @StateObject private var processingPipeline = IncrementalProcessingPipeline()
    @StateObject private var viewModel = IntegrationDemoViewModel()

    var body: some View {
        TabView {
            // Tab 1: 向量索引演示
            VectorIndexDemo()
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("向量索引")
                }

            // Tab 2: 增量处理演示
            ProcessingPipelineDemo()
                .tabItem {
                    Image(systemName: "gearshape.2")
                    Text("任务处理")
                }

            // Tab 3: 设计系统演示
            DesignSystemDemo()
                .tabItem {
                    Image(systemName: "paintpalette")
                    Text("设计系统")
                }

            // Tab 4: 仪表盘演示
            DashboardGridView()
                .tabItem {
                    Image(systemName: "square.grid.2x2")
                    Text("仪表盘")
                }
        }
        .frame(width: 1200, height: 800)
        .glass()
    }
}

/// 向量索引演示
struct VectorIndexDemo: View {
    @StateObject private var vectorStorage = VectorStorageManager.shared
    @State private var searchQuery = ""
    @State private var searchResults: [VectorSearchResult] = []

    var body: some View {
        VStack(spacing: DesignTokens.spacing.lg) {
            // 标题
            Text("HNSW 向量索引演示")
                .font(DesignTokens.fontScale.xxxl)
                .fontWeight(.bold)

            // 控制面板
            HStack(spacing: DesignTokens.spacing.md) {
                Button("索引示例文档") {
                    Task {
                        await vectorStorage.indexExampleDocuments()
                    }
                }
                .buttonStyle(GlassButtonStyle())

                Button("预热索引") {
                    Task {
                        await vectorStorage.warmUpIndex()
                    }
                }
                .buttonStyle(GlassButtonStyle())

                Button("清空索引") {
                    Task {
                        await vectorStorage.clearIndex()
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .foregroundColor(DesignTokens.error)

                Spacer()
            }
            .padding()
            .glass()

            // 统计信息
            HStack(spacing: DesignTokens.spacing.lg) {
                StatsCard(
                    title: "文档数量",
                    value: "\(vectorStorage.getStats().documentCount)",
                    trend: .up(5),
                    icon: "doc.on.doc"
                )

                StatsCard(
                    title: "向量维度",
                    value: "\(vectorStorage.getStats().vectorDimension)",
                    trend: .stable,
                    icon: "cube"
                )

                StatsCard(
                    title: "内存使用",
                    value: formatBytes(vectorStorage.getStats().memoryUsage),
                    trend: .down(10),
                    icon: "internaldrive"
                )

                StatsCard(
                    title: "构建时间",
                    value: String(format: "%.2fs", vectorStorage.getStats().buildTime),
                    trend: .stable,
                    icon: "timer"
                )

                Spacer()
            }

            // 搜索区域
            VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
                Text("语义搜索")
                    .font(DesignTokens.fontScale.lg)
                    .fontWeight(.medium)

                HStack {
                    TextField("输入向量查询...", text: $searchQuery)
                        .textFieldStyle(GlassTextFieldStyle())

                    Button("搜索") {
                        performSearch()
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(searchQuery.isEmpty)
                }
            }
            .padding()
            .glass()

            // 搜索结果
            if !searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: DesignTokens.spacing.sm) {
                        ForEach(searchResults) { result in
                            SearchResultRow(result: result)
                        }
                    }
                    .padding()
                }
            }

            Spacer()
        }
        .padding()
    }

    private func performSearch() {
        let query = Vector([0.1, 0.2, 0.3, 0.4, 0.5])
        Task {
            do {
                searchResults = try await vectorStorage.searchSimilar(query: query, limit: 5)
            } catch {
                print("Search failed: \(error)")
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.style = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

/// 任务处理演示
struct ProcessingPipelineDemo: View {
    @StateObject private var pipeline = IncrementalProcessingPipeline()

    var body: some View {
        VStack(spacing: DesignTokens.spacing.lg) {
            // 标题
            Text("增量处理管线演示")
                .font(DesignTokens.fontScale.xxxl)
                .fontWeight(.bold)

            // 状态卡片
            VStack(spacing: DesignTokens.spacing.md) {
                HStack {
                    if pipeline.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignTokens.success)
                            .font(.title2)
                    }

                    VStack(alignment: .leading) {
                        Text(pipeline.isProcessing ? "正在处理..." : "处理完成")
                            .font(DesignTokens.fontScale.lg)
                            .fontWeight(.medium)

                        Text(pipeline.currentTask)
                            .font(DesignTokens.fontScale.sm)
                            .foregroundColor(DesignTokens.textSecondary)
                    }

                    Spacer()

                    Text("\(Int(pipeline.progress * 100))%")
                        .font(DesignTokens.fontScale.xl)
                        .fontWeight(.bold)
                        .foregroundColor(DesignTokens.primary)
                }

                if pipeline.isProcessing {
                    ProgressView(value: pipeline.progress)
                        .progressViewStyle(LinearProgressView())
                }
            }
            .padding()
            .glass()

            // 控制按钮
            HStack(spacing: DesignTokens.spacing.md) {
                Button("添加向量生成任务") {
                    addEmbeddingTasks()
                }
                .buttonStyle(GlassButtonStyle())

                Button("添加文件分析任务") {
                    addFileAnalysisTasks()
                }
                .buttonStyle(GlassButtonStyle())

                if pipeline.isProcessing {
                    Button("暂停") {
                        pipeline.pause()
                    }
                    .buttonStyle(GlassButtonStyle())
                } else {
                    Button("恢复") {
                        pipeline.resume()
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                Button("取消所有") {
                    pipeline.cancelAll()
                }
                .buttonStyle(GlassButtonStyle())
                .foregroundColor(DesignTokens.error)

                Spacer()
            }

            // 队列列表
            VStack(alignment: .leading, spacing: DesignTokens.spacing.sm) {
                Text("任务队列")
                    .font(DesignTokens.fontScale.lg)
                    .fontWeight(.medium)

                if pipeline.queue.isEmpty {
                    Text("暂无任务")
                        .foregroundColor(DesignTokens.textTertiary)
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: DesignTokens.spacing.xs) {
                            ForEach(pipeline.queue) { task in
                                TaskQueueItem(task: task)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding()
            .glass()

            // 统计信息
            HStack(spacing: DesignTokens.spacing.lg) {
                StatsCard(
                    title: "队列中",
                    value: "\(pipeline.getStats().totalQueued)",
                    trend: .stable,
                    icon: "list.bullet"
                )

                StatsCard(
                    title: "已完成",
                    value: "\(pipeline.getStats().totalCompleted)",
                    trend: .up(pipeline.getStats().totalCompleted),
                    icon: "checkmark.circle"
                )

                StatsCard(
                    title: "失败",
                    value: "\(pipeline.getStats().totalFailed)",
                    trend: pipeline.getStats().totalFailed > 0 ? .up(pipeline.getStats().totalFailed) : .stable,
                    icon: "xmark.circle"
                )

                StatsCard(
                    title: "成功率",
                    value: String(format: "%.1f%%", pipeline.getStats().successRate * 100),
                    trend: pipeline.getStats().successRate > 0.9 ? .up(90) : .stable,
                    icon: "percent"
                )

                Spacer()
            }

            Spacer()
        }
        .padding()
    }

    private func addEmbeddingTasks() {
        let sampleFiles = [
            URL(fileURLWithPath: "/tmp/file1.pdf"),
            URL(fileURLWithPath: "/tmp/file2.pdf"),
            URL(fileURLWithPath: "/tmp/file3.pdf")
        ]
        pipeline.addEmbeddingTasks(for: sampleFiles)
    }

    private func addFileAnalysisTasks() {
        let sampleFiles = [
            URL(fileURLWithPath: "/tmp/doc1.txt"),
            URL(fileURLWithPath: "/tmp/doc2.txt")
        ]
        let task = ProcessingTask.fileAnalysis(for: sampleFiles)
        pipeline.enqueueTask(task)
    }
}

/// 设计系统演示
struct DesignSystemDemo: View {
    @State private var isHovered = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spacing.xl) {
                // 标题
                Text("设计系统组件库")
                    .font(DesignTokens.fontScale.xxxl)
                    .fontWeight(.bold)

                // 颜色系统
                ColorSystemDemo()

                // 玻璃态效果
                GlassEffectsDemo()

                // 按钮样式
                ButtonStylesDemo()

                // 卡片组件
                CardComponentsDemo()

                // 动画效果
                AnimationEffectsDemo()

                Spacer()
            }
            .padding()
        }
    }
}

/// 颜色系统演示
struct ColorSystemDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
            Text("颜色系统")
                .font(DesignTokens.fontScale.xl)
                .fontWeight(.semibold)

            HStack(spacing: DesignTokens.spacing.md) {
                ColorSwatch(color: DesignTokens.primary, name: "Primary")
                ColorSwatch(color: DesignTokens.secondary, name: "Secondary")
                ColorSwatch(color: DesignTokens.success, name: "Success")
                ColorSwatch(color: DesignTokens.warning, name: "Warning")
                ColorSwatch(color: DesignTokens.error, name: "Error")
            }
        }
        .padding()
        .glass()
    }
}

struct ColorSwatch: View {
    let color: Color
    let name: String

    var body: some View {
        VStack(spacing: DesignTokens.spacing.xs) {
            Rectangle()
                .fill(color)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.sm))

            Text(name)
                .font(DesignTokens.fontScale.xs)
        }
    }
}

/// 玻璃态效果演示
struct GlassEffectsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
            Text("玻璃态效果")
                .font(DesignTokens.fontScale.xl)
                .fontWeight(.semibold)

            HStack(spacing: DesignTokens.spacing.md) {
                Text("Regular Material")
                    .padding()
                    .glass()

                Text("Thin Material")
                    .padding()
                    .glass(material: .thin)

                Text("Thick Material")
                    .padding()
                    .glass(material: .thick)
            }
        }
        .padding()
        .glass()
    }
}

/// 按钮样式演示
struct ButtonStylesDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
            Text("按钮样式")
                .font(DesignTokens.fontScale.xl)
                .fontWeight(.semibold)

            HStack(spacing: DesignTokens.spacing.md) {
                Button("Default Button") {}
                    .buttonStyle(GlassButtonStyle())

                Button("Primary Button") {}
                    .buttonStyle(GlassButtonStyle())
                    .foregroundColor(DesignTokens.primary)

                Button("Success Button") {}
                    .buttonStyle(GlassButtonStyle())
                    .foregroundColor(DesignTokens.success)

                Button("Danger Button") {}
                    .buttonStyle(GlassButtonStyle())
                    .foregroundColor(DesignTokens.error)
            }
        }
        .padding()
        .glass()
    }
}

/// 卡片组件演示
struct CardComponentsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
            Text("卡片组件")
                .font(DesignTokens.fontScale.xl)
                .fontWeight(.semibold)

            HStack(spacing: DesignTokens.spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.spacing.sm) {
                    Text("标题")
                        .font(DesignTokens.fontScale.lg)
                        .fontWeight(.medium)

                    Text("这是一个示例卡片内容")
                        .font(DesignTokens.fontScale.sm)
                        .foregroundColor(DesignTokens.textSecondary)

                    Button("操作") {}
                        .buttonStyle(GlassButtonStyle())
                }
                .glassCard()

                VStack(alignment: .leading, spacing: DesignTokens.spacing.sm) {
                    Image(systemName: "star")
                        .font(.system(size: 32))
                        .foregroundColor(DesignTokens.warning)

                    Text("特殊卡片")
                        .font(DesignTokens.fontScale.lg)
                        .fontWeight(.medium)

                    Text("带图标的卡片")
                        .font(DesignTokens.fontScale.sm)
                        .foregroundColor(DesignTokens.textSecondary)
                }
                .glassCard(border: DesignTokens.warning, borderWidth: 2)
            }
        }
        .padding()
        .glass()
    }
}

/// 动画效果演示
struct AnimationEffectsDemo: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.md) {
            Text("动画效果")
                .font(DesignTokens.fontScale.xl)
                .fontWeight(.semibold)

            HStack(spacing: DesignTokens.spacing.md) {
                Text("悬浮效果")
                    .padding()
                    .glass()
                    .hoverEffect()
                    .onTapGesture { isAnimating.toggle() }

                Text("脉冲效果")
                    .padding()
                    .glass()
                    .pulse(color: DesignTokens.primary)

                Text("闪光效果")
                    .padding()
                    .glass()
                    .shimmer()

                Button("弹性动画") {
                    withAnimation(DesignTokens.animation.bouncy) {
                        isAnimating.toggle()
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
            }
        }
        .padding()
        .glass()
    }
}

/// 统计卡片组件
struct StatsCard: View {
    let title: String
    let value: String
    let trend: StatsCardComponent.Trend
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(DesignTokens.primary)

                Spacer()

                if let percentage = trend.percentage {
                    HStack(spacing: 4) {
                        Image(systemName: trend.icon)
                            .font(.caption)
                            .foregroundColor(trend.color)

                        Text("\(Int(abs(percentage)))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(trend.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(trend.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.sm))
                }
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(DesignTokens.textPrimary)

            Text(title)
                .font(DesignTokens.fontScale.sm)
                .foregroundColor(DesignTokens.textSecondary)
        }
        .padding()
        .glass()
    }
}

/// 搜索结果行
struct SearchResultRow: View {
    let result: VectorSearchResult

    var body: some View {
        HStack {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundColor(DesignTokens.primary)

            VStack(alignment: .leading) {
                Text("文件 ID: \(result.fileId.uuidString.prefix(8))")
                    .font(DesignTokens.fontScale.md)
                    .fontWeight(.medium)

                Text("相似度: \(Int(result.similarity * 100))%")
                    .font(DesignTokens.fontScale.sm)
                    .foregroundColor(DesignTokens.textSecondary)
            }

            Spacer()

            Text("\(Int(result.similarity * 100))%")
                .font(DesignTokens.fontScale.lg)
                .fontWeight(.bold)
                .foregroundColor(DesignTokens.success)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesignTokens.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.sm))
        }
        .padding()
        .glass()
    }
}

/// 任务队列项
struct TaskQueueItem: View {
    let task: ProcessingTask

    var body: some View {
        HStack {
            PriorityIndicator(priority: task.priority)

            VStack(alignment: .leading) {
                Text(task.description)
                    .font(DesignTokens.fontScale.sm)

                Text(task.createdAt, style: .time)
                    .font(DesignTokens.fontScale.xs)
                    .foregroundColor(DesignTokens.textTertiary)
            }

            Spacer()

            Text(task.type.rawValue)
                .font(DesignTokens.fontScale.xs)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius.sm))
        }
        .padding(.vertical, 4)
    }
}

/// 优先级指示器
struct PriorityIndicator: View {
    let priority: ProcessingTask.TaskPriority

    var body: some View {
        Circle()
            .fill(priority.color)
            .frame(width: 12, height: 12)
    }
}

extension ProcessingTask.TaskPriority {
    var color: Color {
        switch self {
        case .low:
            return DesignTokens.neutral
        case .normal:
            return DesignTokens.primary
        case .high:
            return DesignTokens.warning
        case .urgent:
            return DesignTokens.error
        }
    }
}

/// 集成演示视图模型
@MainActor
class IntegrationDemoViewModel: ObservableObject {
    // 示例视图模型
}

// MARK: - 预览

struct FeatureIntegrationDemo_Previews: PreviewProvider {
    static var previews: some View {
        FeatureIntegrationDemo()
    }
}
