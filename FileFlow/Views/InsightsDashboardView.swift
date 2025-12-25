//
//  InsightsDashboardView.swift
//  FileFlow
//
//  Unified Insights Dashboard - Single scrollable canvas
//  Integrates: Health Score, Action Items, Timeline, Analytics
//

import SwiftUI

struct InsightsDashboardView: View {
    @EnvironmentObject var appState: AppState
    
    // Data States
    @State private var healthScore: Int = 0
    @State private var activeFilesPercent: Double = 0
    @State private var staleFilesCount: Int = 0
    @State private var knowledgeLinksCount: Int = 0
    @State private var pendingReviewCount: Int = 0
    
    @State private var actionItems: [ActionItem] = []
    @State private var timelineEvents: [TimelineEvent] = []
    @State private var lifecycleStats: [FileLifecycleStage: Int] = [:]
    @State private var categoryStats: [PARACategory: Int] = [:]
    
    @State private var isLoading = true
    @State private var showAnalytics = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // MARK: - Section 1: Health Score Hero
                HealthScoreSection(
                    score: healthScore,
                    activePercent: activeFilesPercent,
                    staleCount: staleFilesCount,
                    linksCount: knowledgeLinksCount,
                    reviewCount: pendingReviewCount,
                    onCleanup: performBulkCleanup,
                    onDiscover: discoverKnowledgeLinks
                )
                
                // MARK: - Section 2: Action Items
                if !actionItems.isEmpty {
                    ActionItemsSection(
                        items: actionItems,
                        onAction: handleActionItem
                    )
                }
                
                // MARK: - Section 3: Activity Timeline
                ActivityTimelineSection(events: timelineEvents)
                
                // MARK: - Section 4: Analytics (Collapsible)
                AnalyticsSummarySection(
                    isExpanded: $showAnalytics,
                    lifecycleStats: lifecycleStats,
                    categoryStats: categoryStats
                )
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadAllData()
        }
        .refreshable {
            await loadAllData()
        }
    }
    
    // MARK: - Data Loading
    private func loadAllData() async {
        isLoading = true
        
        // Load lifecycle stats
        lifecycleStats = await LifecycleService.shared.getLifecycleStats()
        
        // Calculate health metrics
        let totalFiles = lifecycleStats.values.reduce(0, +)
        let activeFiles = lifecycleStats[.active] ?? 0
        activeFilesPercent = totalFiles > 0 ? Double(activeFiles) / Double(totalFiles) * 100 : 0
        
        // Stale files
        let suggestions = await LifecycleService.shared.getCleanupSuggestions()
        staleFilesCount = suggestions.count
        
        // Knowledge stats
        let knowledgeStats = await KnowledgeLinkService.shared.getStats()
        knowledgeLinksCount = knowledgeStats.links
        pendingReviewCount = knowledgeStats.needsReview
        
        // Calculate health score (weighted average)
        let activeScore = min(activeFilesPercent, 100)
        let staleScore = max(0, 100 - Double(staleFilesCount) * 5) // -5 per stale file
        let linkScore = min(Double(knowledgeLinksCount) * 2, 100) // +2 per link, max 100
        let reviewScore = max(0, 100 - Double(pendingReviewCount) * 10) // -10 per pending
        healthScore = Int((activeScore * 0.3 + staleScore * 0.3 + linkScore * 0.2 + reviewScore * 0.2))
        
        // Build action items
        actionItems = await buildActionItems(suggestions: suggestions)
        
        // Load timeline
        timelineEvents = await buildTimelineEvents()
        
        // Category stats
        let statsResult = FileFlowManager.shared.getStatistics()
        categoryStats = statsResult.byCategory
        
        isLoading = false
    }
    
    private func buildActionItems(suggestions: [LifecycleCleanupSuggestion]) async -> [ActionItem] {
        var items: [ActionItem] = []
        
        // Stale files
        if !suggestions.isEmpty {
            items.append(ActionItem(
                id: UUID(),
                type: .staleFiles,
                title: "\(suggestions.count) 个文件超过30天未访问",
                subtitle: "建议归档以保持知识库整洁",
                count: suggestions.count,
                action: .archive
            ))
        }
        
        // Pending reviews
        let cards = await KnowledgeLinkService.shared.getCardsForReview()
        if !cards.isEmpty {
            items.append(ActionItem(
                id: UUID(),
                type: .pendingReview,
                title: "\(cards.count) 张知识卡片待复习",
                subtitle: "定期复习有助于知识内化",
                count: cards.count,
                action: .review
            ))
        }
        
        // Similar tags (placeholder - would need TagMergeSuggestionViewModel)
        // items.append(...)
        
        return items
    }
    
    private func buildTimelineEvents() async -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        
        // Recent transitions
        let transitions = await LifecycleService.shared.getRecentTransitions(limit: 10)
        for t in transitions {
            events.append(TimelineEvent(
                id: UUID(),
                date: t.triggeredAt,
                type: .transition,
                title: t.fileName,
                detail: "\(t.fromCategory.displayName) → \(t.toCategory.displayName)",
                color: t.toCategory.color
            ))
        }
        
        // Recent files (last 5)
        let recentFiles = await DatabaseManager.shared.getRecentFiles(limit: 5)
        for file in recentFiles {
            events.append(TimelineEvent(
                id: UUID(),
                date: file.importedAt,
                type: .fileImport,
                title: file.displayName,
                detail: "导入到 \(file.category.displayName)",
                color: file.category.color
            ))
        }
        
        // Sort by date descending
        events.sort { $0.date > $1.date }
        return Array(events.prefix(15))
    }
    
    // MARK: - Actions
    private func performBulkCleanup() {
        Task {
            let suggestions = await LifecycleService.shared.getCleanupSuggestions()
            let files = suggestions.map { $0.file }
            await LifecycleService.shared.batchArchiveStaleFiles(files: files)
            await loadAllData()
        }
    }
    
    private func discoverKnowledgeLinks() {
        // Trigger knowledge link discovery
        Task {
            // Placeholder - would trigger actual discovery
            await loadAllData()
        }
    }
    
    private func handleActionItem(_ item: ActionItem) {
        switch item.action {
        case .archive:
            performBulkCleanup()
        case .review:
            // Navigate to review (could use navigationTarget)
            break
        case .merge:
            // Open merge UI
            break
        case .move:
            break
        }
    }
}

// MARK: - Data Models
struct ActionItem: Identifiable {
    let id: UUID
    let type: ActionItemType
    let title: String
    let subtitle: String
    let count: Int
    let action: ActionType
    
    enum ActionItemType {
        case staleFiles, pendingReview, similarTags, suggestedMove
        
        var icon: String {
            switch self {
            case .staleFiles: return "moon.zzz.fill"
            case .pendingReview: return "book.fill"
            case .similarTags: return "arrow.triangle.merge"
            case .suggestedMove: return "arrow.right.square"
            }
        }
        
        var color: Color {
            switch self {
            case .staleFiles: return .orange
            case .pendingReview: return .purple
            case .similarTags: return .cyan
            case .suggestedMove: return .blue
            }
        }
    }
    
    enum ActionType {
        case archive, review, merge, move
        
        var label: String {
            switch self {
            case .archive: return "归档"
            case .review: return "开始复习"
            case .merge: return "合并"
            case .move: return "移动"
            }
        }
    }
}

struct TimelineEvent: Identifiable {
    let id: UUID
    let date: Date
    let type: EventType
    let title: String
    let detail: String
    let color: Color
    
    enum EventType {
        case transition, fileImport, tagAdded, reviewed
        
        var icon: String {
            switch self {
            case .transition: return "arrow.right"
            case .fileImport: return "square.and.arrow.down"
            case .tagAdded: return "tag"
            case .reviewed: return "checkmark.circle"
            }
        }
    }
}

// MARK: - Section Components

struct HealthScoreSection: View {
    let score: Int
    let activePercent: Double
    let staleCount: Int
    let linksCount: Int
    let reviewCount: Int
    let onCleanup: () -> Void
    let onDiscover: () -> Void
    
    var scoreColor: Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Hero Score
            HStack(spacing: 40) {
                // Circular Progress
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 12)
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(scoreColor.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: score)
                    
                    VStack(spacing: 4) {
                        Text("\(score)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor)
                        Text("健康分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Metrics Grid
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 32) {
                        MetricPill(icon: "bolt.fill", value: "\(Int(activePercent))%", label: "活跃文件", color: .green)
                        MetricPill(icon: "moon.zzz.fill", value: "\(staleCount)", label: "待整理", color: .orange)
                    }
                    HStack(spacing: 32) {
                        MetricPill(icon: "link", value: "\(linksCount)", label: "知识链接", color: .blue)
                        MetricPill(icon: "book.fill", value: "\(reviewCount)", label: "待复习", color: .purple)
                    }
                }
            }
            
            // Quick Actions
            HStack(spacing: 16) {
                Button(action: onCleanup) {
                    Label("一键整理休眠文件", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(staleCount == 0)
                
                Button(action: onDiscover) {
                    Label("发现知识链接", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 20, y: 10)
        )
    }
}

struct MetricPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, alignment: .leading)
    }
}

struct ActionItemsSection: View {
    let items: [ActionItem]
    let onAction: (ActionItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("需要关注")
                    .font(.headline)
            }
            
            VStack(spacing: 12) {
                ForEach(items) { item in
                    HStack(spacing: 16) {
                        Image(systemName: item.type.icon)
                            .font(.title2)
                            .foregroundStyle(item.type.color)
                            .frame(width: 36)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body.weight(.medium))
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(item.action.label) {
                            onAction(item)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(item.type.color)
                        .controlSize(.small)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(item.type.color.opacity(0.08))
                    )
                }
            }
        }
    }
}

struct ActivityTimelineSection: View {
    let events: [TimelineEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                Text("最近动态")
                    .font(.headline)
            }
            
            if events.isEmpty {
                Text("暂无活动记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 16) {
                            // Timeline dot and line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(event.color)
                                    .frame(width: 10, height: 10)
                                
                                if index < events.count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(width: 2)
                                        .frame(minHeight: 40)
                                }
                            }
                            .frame(width: 10)
                            
                            // Content
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: event.type.icon)
                                        .font(.caption)
                                        .foregroundStyle(event.color)
                                    Text(event.title)
                                        .font(.body)
                                        .lineLimit(1)
                                }
                                
                                HStack {
                                    Text(event.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(event.date.timeAgo())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

struct AnalyticsSummarySection: View {
    @Binding var isExpanded: Bool
    let lifecycleStats: [FileLifecycleStage: Int]
    let categoryStats: [PARACategory: Int]
    
    var totalFiles: Int {
        lifecycleStats.values.reduce(0, +)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeInOut) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.purple)
                    Text("数据概览")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 24) {
                    // Lifecycle Distribution
                    VStack(alignment: .leading, spacing: 8) {
                        Text("生命周期分布")
                            .font(.subheadline.weight(.medium))
                        
                        if totalFiles > 0 {
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
                                        let count = lifecycleStats[stage] ?? 0
                                        let width = (CGFloat(count) / CGFloat(totalFiles)) * geo.size.width
                                        
                                        if count > 0 {
                                            Rectangle()
                                                .fill(stage.color)
                                                .frame(width: max(width, 4))
                                        }
                                    }
                                }
                            }
                            .frame(height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            // Legend
                            HStack(spacing: 16) {
                                ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
                                    if (lifecycleStats[stage] ?? 0) > 0 {
                                        HStack(spacing: 4) {
                                            Circle().fill(stage.color).frame(width: 8, height: 8)
                                            Text("\(stage.displayName): \(lifecycleStats[stage] ?? 0)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Category Distribution
                    VStack(alignment: .leading, spacing: 8) {
                        Text("分类分布")
                            .font(.subheadline.weight(.medium))
                        
                        ForEach(PARACategory.allCases) { category in
                            let count = categoryStats[category] ?? 0
                            let total = categoryStats.values.reduce(0, +)
                            let percentage = total > 0 ? Double(count) / Double(total) : 0
                            
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(category.color)
                                    .frame(width: 20)
                                Text(category.displayName)
                                    .font(.caption)
                                    .frame(width: 60, alignment: .leading)
                                
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(category.color.gradient)
                                        .frame(width: geo.size.width * percentage)
                                }
                                .frame(height: 12)
                                
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Preview
#Preview {
    InsightsDashboardView()
        .environmentObject(AppState())
        .frame(width: 900, height: 800)
}
