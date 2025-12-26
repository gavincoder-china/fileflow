//
//  UnifiedHomeView.swift
//  FileFlow
//
//  Unified Command Center - Merged Home + Insights Dashboard
//

import SwiftUI
import UniformTypeIdentifiers

struct UnifiedHomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedFileURL: URL?
    @Binding var pendingFileURLs: [URL]
    
    // Callbacks
    var onSearch: (String) -> Void = { _ in }
    var onFilesDropped: (UploadMode) -> Void = { _ in }
    
    // State
    @State private var searchText = ""
    @State private var isTargeted = false
    @State private var selectedMode: UploadMode = .smart
    
    // Dashboard Data
    @State private var healthScore: Int = 0
    @State private var activeFilesPercent: Double = 0
    @State private var staleFilesCount: Int = 0
    @State private var knowledgeLinksCount: Int = 0
    @State private var pendingReviewCount: Int = 0
    @State private var actionItems: [HomeActionItem] = []
    @State private var knowledgeLinks: [(source: String, target: String, date: Date)] = []
    @State private var tagHeatmapData: [(tag: String, count: Int, color: Color)] = []
    @State private var lifecycleStats: [FileLifecycleStage: Int] = [:]
    @State private var reviewedFilesCount: Int = 0
    @State private var showCardReview = false
    @State private var reverseSearchQuery = ""
    @State private var reverseSearchResults: [ManagedFile] = []
    
    var body: some View {
        ScrollView {
                VStack(spacing: 32) {
                    
                    // MARK: - Hero Section (Search + Health Score)
                    HStack(alignment: .top, spacing: 32) {
                        // Left: Search & Upload
                        VStack(spacing: 24) {
                            VStack(spacing: 8) {
                                Text(greetingText())
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                Text("今天想整理些什么？")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HeroSearchBar(
                                searchText: $searchText,
                                isTargeted: $isTargeted,
                                onCommit: { if !searchText.isEmpty { onSearch(searchText) } },
                                onUpload: { appState.showFileImporter = true },
                                onDrop: { handleDrop(providers: $0) }
                            )
                            .frame(maxWidth: 700)
                            
                            // Mode Pills
                            HStack(spacing: 8) {
                                ForEach(UploadMode.allCases) { mode in
                                    ModeSelectorPill(mode: mode, isSelected: selectedMode == mode) {
                                        withAnimation { selectedMode = mode }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        

                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // MARK: - Action Items Banner
                    if !actionItems.isEmpty {
                        ActionItemsBanner(items: actionItems, onAction: handleActionItem)
                            .padding(.horizontal, 24)
                    }
                    
                    // MARK: - Main Content Grid
                    HStack(alignment: .top, spacing: 20) {
                        // Main content (Files + Knowledge Links)
                        dashboardLeftContent
                        
                        // Right sidebar (Analytics) - only show if there's room
                        dashboardRightContent
                            .frame(width: 260) // Slightly reduced width
                            .layoutPriority(-1) // Lower priority, can be compressed
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
        .task {
            await loadDashboardData()
        }
        .sheet(isPresented: $showCardReview) {
            ReviewSessionView()
        }
    }
    
    // MARK: - Data Loading
    private func loadDashboardData() async {
        // Lifecycle stats
        lifecycleStats = await LifecycleService.shared.getLifecycleStats()
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
        reviewedFilesCount = knowledgeStats.reviewed
        
        // Health score
        let activeScore = min(activeFilesPercent, 100)
        let staleScore = max(0, 100 - Double(staleFilesCount) * 5)
        let linkScore = min(Double(knowledgeLinksCount) * 2, 100)
        let reviewScore = max(0, 100 - Double(pendingReviewCount) * 10)
        healthScore = Int((activeScore * 0.3 + staleScore * 0.3 + linkScore * 0.2 + reviewScore * 0.2))
        
        // Build action items
        actionItems = await buildActionItems(suggestions: suggestions)
        
        // Load tag heatmap
        tagHeatmapData = await loadTagHeatmap()
        
        // Load knowledge links
        knowledgeLinks = await loadKnowledgeLinks()
    }
    
    private func buildActionItems(suggestions: [LifecycleCleanupSuggestion]) async -> [HomeActionItem] {
        var items: [HomeActionItem] = []
        
        if !suggestions.isEmpty {
            items.append(HomeActionItem(
                type: .staleFiles,
                title: "\(suggestions.count) 个休眠文件",
                action: { Task { await performBulkCleanup() } }
            ))
        }
        
        let cards = await KnowledgeLinkService.shared.getCardsForReview()
        if !cards.isEmpty {
            items.append(HomeActionItem(
                type: .pendingReview,
                title: "\(cards.count) 张待复习",
                action: { showCardReview = true }
            ))
        }
        
        // Similar tags (placeholder)
        // items.append(...)
        
        return items
    }
    
    private func loadTagHeatmap() async -> [(tag: String, count: Int, color: Color)] {
        let tags = await DatabaseManager.shared.getAllTags()
        return tags.sorted { $0.usageCount > $1.usageCount }
            .prefix(10)
            .map { ($0.name, $0.usageCount, $0.swiftUIColor) }
    }
    
    private func loadKnowledgeLinks() async -> [(source: String, target: String, date: Date)] {
        // Placeholder - would load from KnowledgeLinkService
        return []
    }
    
    private func performReverseSearch() {
        guard !reverseSearchQuery.isEmpty else { return }
        Task {
            let results = await KnowledgeLinkService.shared.reverseSearch(keyword: reverseSearchQuery)
            reverseSearchResults = results.map { $0.0 }
        }
    }
    
    private func performBulkCleanup() async {
        let suggestions = await LifecycleService.shared.getCleanupSuggestions()
        let files = suggestions.map { $0.file }
        await LifecycleService.shared.batchArchiveStaleFiles(files: files)
        await loadDashboardData()
    }
    
    private func handleActionItem(_ item: HomeActionItem) {
        item.action()
    }
    
    private func greetingText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        // 使用 detached task 避免阻塞主线程
        Task.detached(priority: .userInitiated) {
            let urls: [URL] = await withTaskGroup(of: URL?.self) { group in
                for provider in providers {
                    group.addTask {
                        return await withCheckedContinuation { continuation in
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                continuation.resume(returning: url)
                            }
                        }
                    }
                }
                var results: [URL] = []
                for await url in group {
                    if let url = url { results.append(url) }
                }
                return results
            }
            
            await MainActor.run { [self] in
                // 使用 Set 进行 O(1) 去重检查
                let existingSet = Set(self.pendingFileURLs)
                let uniqueNewURLs = urls.filter { !existingSet.contains($0) }
                if !uniqueNewURLs.isEmpty {
                    self.pendingFileURLs.append(contentsOf: uniqueNewURLs)
                    self.onFilesDropped(self.selectedMode)
                }
            }
        }
    }
    private func todayCount() -> Int {
        appState.recentFiles.filter { Calendar.current.isDateInToday($0.importedAt) }.count
    }
}

// MARK: - Supporting Components

struct HomeActionItem: Identifiable {
    let id = UUID()
    let type: ActionType
    let title: String
    let action: () -> Void
    
    enum ActionType {
        case staleFiles, pendingReview, similarTags
        
        var icon: String {
            switch self {
            case .staleFiles: return "moon.zzz.fill"
            case .pendingReview: return "book.fill"
            case .similarTags: return "arrow.triangle.merge"
            }
        }
        
        var color: Color {
            switch self {
            case .staleFiles: return .orange
            case .pendingReview: return .purple
            case .similarTags: return .cyan
            }
        }
        
        var actionLabel: String {
            switch self {
            case .staleFiles: return "归档"
            case .pendingReview: return "复习"
            case .similarTags: return "合并"
            }
        }
    }
}

struct HealthScoreMiniCard: View {
    let score: Int
    let activePercent: Double
    let staleCount: Int
    let linksCount: Int
    let reviewCount: Int
    
    var scoreColor: Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Score Circle
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: score)
                
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("健康分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            
            // Mini Metrics
            HStack(spacing: 16) {
                MiniMetric(icon: "bolt.fill", value: "\(Int(activePercent))%", color: .green)
                MiniMetric(icon: "moon.zzz", value: "\(staleCount)", color: .orange)
                MiniMetric(icon: "link", value: "\(linksCount)", color: .blue)
            }
        }
        .padding(20)
        .background(.regularMaterial) // Updated to regular material
        .cornerRadius(16) // Updated radius
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

struct MiniMetric: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.bold())
        }
    }
}

struct ActionItemsBanner: View {
    let items: [HomeActionItem]
    let onAction: (HomeActionItem) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text("需要关注")
                .font(.subheadline.bold())
            
            Spacer()
            
            ForEach(items) { item in
                Button {
                    onAction(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.type.icon)
                        Text(item.title)
                            .font(.caption)
                        Text(item.type.actionLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.type.color.opacity(0.2))
                            .cornerRadius(6)
                    }
                    .foregroundStyle(item.type.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.regularMaterial) // Updated material
        .cornerRadius(12) // Updated radius
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

struct AnalyticsDashboardCard: View {
    let lifecycleStats: [FileLifecycleStage: Int]
    let categoryStats: [PARACategory: Int]
    let totalFiles: Int
    let totalSize: Int64
    let todayCount: Int
    let reviewedCount: Int
    
    @State private var showTreemap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            HStack {
                Label("存储分析", systemImage: "chart.pie.fill")
                    .font(.headline)
                    .foregroundStyle(.primary) // Standard color
                Spacer()
                
                Button(action: { showTreemap = true }) {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("查看磁盘分布图")
            }
            
            // Key Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatItem(label: "总文件", value: "\(totalFiles)", color: .primary)
                
                StatItem(label: "存储占用", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file), color: .orange)
                    .contentShape(Rectangle())
                    .onTapGesture { showTreemap = true }
                    .help("点击查看详细分布")
                
                StatItem(label: "今日新增", value: "+\(todayCount)", color: .blue)
                StatItem(label: "已学习", value: "\(reviewedCount)", color: .green)
            }
            .padding(.vertical, 4)
            .sheet(isPresented: $showTreemap) {
                DiskUsageView()
                    .frame(width: 800, height: 600)
            }
            
            Divider()
            
            // Lifecycle Bar
            if totalFiles > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("生命周期流转")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(lifecycleStats[.active] ?? 0)) 活跃")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    
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
                    .frame(height: 8) // Thinner bar
                    .cornerRadius(4)
                    
                    // Legend
                    HStack(spacing: 8) {
                        ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
                            if (lifecycleStats[stage] ?? 0) > 0 {
                                HStack(spacing: 4) {
                                    Circle().fill(stage.color).frame(width: 6, height: 6)
                                    Text(stage.displayName)
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
            VStack(alignment: .leading, spacing: 12) {
                Text("分类分布")
                    .font(.subheadline.bold())
                
                ForEach(PARACategory.allCases) { cat in
                    let count = categoryStats[cat] ?? 0
                    if count > 0 {
                        HStack {
                            Label(cat.displayName, systemImage: cat.icon)
                                .font(.caption)
                                .foregroundStyle(cat.color)
                                .frame(width: 80, alignment: .leading)
                            
                            GeometryReader { geo in
                                let maxCount = categoryStats.values.max() ?? 1
                                let width = CGFloat(count) / CGFloat(maxCount) * geo.size.width
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cat.color.opacity(0.3))
                                    .frame(width: max(width, 4))
                            }
                            .frame(height: 6) // Thinner bars
                            
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial) // Updated material
        .cornerRadius(16) // Updated radius
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

struct KnowledgeCardReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            HStack {
                Text("知识卡片复习")
                    .font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding()
            
            ContentUnavailableView("复习功能", systemImage: "book.fill", description: Text("知识卡片复习界面"))
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Preserved Components (Refactored)

struct HeroSearchBar: View {
    @Binding var searchText: String
    @Binding var isTargeted: Bool
    var onCommit: () -> Void
    var onUpload: () -> Void
    var onDrop: ([NSItemProvider]) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            
            TextField("搜索文件、标签或拖拽上传...", text: $searchText)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(onCommit)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: onUpload) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.gradient) // Standard accent
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("上传文件")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial) // Standard glass
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 1) // Native focus ring feel
        )
        // Removed scale animations for cleaner feel
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            onDrop(providers)
            return true
        }
        .onTapGesture { isFocused = true }
    }
}

struct ModeSelectorPill: View {
    let mode: UploadMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon).font(.system(size: 12))
                Text(mode.title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct BentoCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color) // Use category color for icon/text
                Spacer()
            }
            content
        }
        .padding(20)
        .background(.regularMaterial) // Standard macOS card material
        .cornerRadius(16) // Updated radius
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5) // Standard border
        )
    }
}

struct RecentFileDetailedRow: View {
    typealias File = ManagedFile
    let file: File
    @State private var isHovering = false
    @EnvironmentObject var appState: AppState // Add EnvironmentObject
    
    var body: some View {
        HStack {
            // Updated Icon size and style
            RichFileIcon(path: file.newPath)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Label(file.category.displayName, systemImage: file.category.icon)
                        .font(.caption2)
                        .foregroundColor(file.category.color)
                    
                    if let sub = file.subcategory {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(file.importedAt.timeAgo())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear) // Hover effect
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 } // Hover trigger
        .onTapGesture(count: 2) {
             NSWorkspace.shared.open(URL(fileURLWithPath: file.newPath))
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.newPath))
            } label: {
                Label("打开文件", systemImage: "doc.text")
            }
            
            Button {
                FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            
            Divider()
            
            Button {
                 appState.navigationTarget = AppState.NavigationTarget(
                    category: file.category,
                    subcategory: file.subcategory,
                    file: file
                )
            } label: {
                Label("在分类中查看", systemImage: "sidebar.left")
            }
            
            Button {
                let link = "fileflow://open?id=\(file.id.uuidString)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            } label: {
                Label("复制文件链接", systemImage: "link")
            }
        }
    }
}

struct StatisticsCardContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                StatItem(label: "今日新增", value: "\(todayCount())", color: .blue)
                Divider().frame(height: 24)
                StatItem(label: "总文件", value: "\(appState.statistics?.totalFiles ?? 0)", color: .purple)
                Divider().frame(height: 24)
                StatItem(label: "存储占用", value: formatSize(appState.statistics?.totalSize ?? 0), color: .orange)
            }
        }
    }
    
    private func todayCount() -> Int {
        return appState.recentFiles.filter { Calendar.current.isDateInToday($0.importedAt) }.count
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.headline, design: .rounded)).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Layout Extensions
extension UnifiedHomeView {
    @ViewBuilder
    var dashboardLeftContent: some View {
        VStack(spacing: 24) {
            // Recent Files
            BentoCard(title: "最近文件", icon: "clock.fill", color: .blue) {
                if appState.recentFiles.isEmpty {
                    ContentUnavailableView("暂无最近文件", systemImage: "doc.on.doc")
                        .frame(height: 200)
                } else {
                    VStack(spacing: 0) {
                        ForEach(appState.recentFiles.prefix(6)) { file in
                            RecentFileDetailedRow(file: file)
                            if file.id != appState.recentFiles.prefix(6).last?.id {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
            }
            
            // Knowledge Links Panel
            BentoCard(title: "知识链接", icon: "link", color: .cyan) {
                VStack(spacing: 12) {
                    // Reverse Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("反向搜索：查找提及某关键词的文件...", text: $reverseSearchQuery)
                            .textFieldStyle(.plain)
                            .onSubmit { performReverseSearch() }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(10)
                    
                    if !reverseSearchResults.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(reverseSearchResults.prefix(5)) { file in
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.cyan)
                                    Text(file.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else if knowledgeLinks.isEmpty {
                        Text("暂无知识链接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: 60)
                    } else {
                        // Show recent links
                        ForEach(knowledgeLinks.prefix(5), id: \.source) { link in
                            HStack {
                                Text(link.source)
                                    .font(.caption)
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(link.target)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(link.date.timeAgo())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var dashboardRightContent: some View {
        VStack(spacing: 24) {
             // Analytics Dashboard
             AnalyticsDashboardCard(
                 lifecycleStats: lifecycleStats,
                 categoryStats: appState.statistics?.byCategory ?? [:],
                 totalFiles: appState.statistics?.totalFiles ?? 0,
                 totalSize: appState.statistics?.totalSize ?? 0,
                 todayCount: todayCount(),
                 reviewedCount: reviewedFilesCount
             )
        }
    }
}
