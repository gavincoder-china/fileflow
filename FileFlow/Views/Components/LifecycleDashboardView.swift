//
//  LifecycleDashboardView.swift
//  FileFlow
//
//  生命周期统计仪表盘 + 流转报告导出
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Lifecycle Dashboard View
/// 生命周期统计仪表盘 - 整合所有数据分析图表
struct LifecycleDashboardView: View {
    @State private var selectedTab = 0
    @State private var lifecycleStats: [FileLifecycleStage: Int] = [:]
    @State private var recentTransitions: [FileTransition] = []
    @State private var isLoading = true
    @State private var showingExportSheet = false
    
    var isEmbedded: Bool = false
    
    var totalFiles: Int {
        lifecycleStats.values.reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            tabSelector
            
            Divider()
            
            // Tab Content
            switch selectedTab {
            case 0:
                lifecycleContent
            case 1:
                TagHeatmapEmbeddedView()
            case 2:
                TagMergeSuggestionEmbeddedView()
            case 3:
                StorageAnalysisView()
            default:
                lifecycleContent
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tabButton(title: "生命周期", icon: "arrow.triangle.2.circlepath", index: 0, color: .blue)
                tabButton(title: "标签热力图", icon: "chart.bar.fill", index: 1, color: .green)
                tabButton(title: "智能合并", icon: "arrow.triangle.merge", index: 2, color: .orange)
                tabButton(title: "存储分析", icon: "externaldrive.fill", index: 3, color: .purple)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
    
    private func tabButton(title: String, icon: String, index: Int, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == index ? color.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(selectedTab == index ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Lifecycle Content
    private var lifecycleContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                if !isEmbedded {
                    headerView
                }
                
                // Stats Overview
                statsOverview
                
                // Distribution Chart
                distributionChart
                
                // Recent Transitions
                recentTransitionsCard
                
                // Actions
                actionButtons
            }
            .padding(24)
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("📊 生命周期仪表盘")
                    .font(.title.bold())
                Text("文件状态分布与流转概览")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Stats Overview
    private var statsOverview: some View {
        HStack(spacing: 16) {
            ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(stage.color.opacity(0.15))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: stage.icon)
                            .font(.title2)
                            .foregroundStyle(stage.color)
                    }
                    
                    Text("\(lifecycleStats[stage] ?? 0)")
                        .font(.title2.bold())
                    
                    Text(stage.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if totalFiles > 0 {
                        let percentage = Double(lifecycleStats[stage] ?? 0) / Double(totalFiles) * 100
                        Text(String(format: "%.1f%%", percentage))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
    }
    
    // MARK: - Distribution Chart
    private var distributionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态分布")
                .font(.headline)
            
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
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Legend
                HStack(spacing: 16) {
                    ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
                        if (lifecycleStats[stage] ?? 0) > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(stage.color)
                                    .frame(width: 8, height: 8)
                                Text(stage.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("暂无文件数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    // MARK: - Recent Transitions
    private var recentTransitionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近流转")
                    .font(.headline)
                Spacer()
                Text("\(recentTransitions.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if recentTransitions.isEmpty {
                Text("暂无流转记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(recentTransitions.prefix(5)) { transition in
                    HStack(spacing: 12) {
                        Image(systemName: transition.reason.icon)
                            .foregroundStyle(transition.toCategory.color)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transition.fileName)
                                .font(.body)
                                .lineLimit(1)
                            
                            Text("\(transition.fromCategory.displayName) → \(transition.toCategory.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(transition.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    
                    if transition.id != recentTransitions.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                showingExportSheet = true
            } label: {
                Label("导出流转报告", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.bordered)
            
            Button {
                Task {
                    await LifecycleService.shared.refreshAllLifecycleStages()
                    await loadData()
                }
            } label: {
                Label("刷新所有状态", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: TransitionReportDocument(transitions: recentTransitions),
            contentType: .json,
            defaultFilename: "FileFlow-Transitions-\(Date().ISO8601Format())"
        ) { result in
            switch result {
            case .success(let url):
                Logger.success("Report exported to: \(url)")
            case .failure(let error):
                Logger.error("Export failed: \(error)")
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadData() async {
        isLoading = true
        lifecycleStats = await LifecycleService.shared.getLifecycleStats()
        recentTransitions = await LifecycleService.shared.getRecentTransitions(limit: 20)
        isLoading = false
    }
}

// MARK: - Transition Report Document
struct TransitionReportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    
    let transitions: [FileTransition]
    
    init(transitions: [FileTransition]) {
        self.transitions = transitions
    }
    
    init(configuration: ReadConfiguration) throws {
        transitions = []
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(transitions)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Tag Heatmap Embedded View
struct TagHeatmapEmbeddedView: View {
    @StateObject private var viewModel = TagHeatmapViewModel()
    @State private var selectedChart = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Chart Selector
                Picker("", selection: $selectedChart) {
                    Text("使用频率").tag(0)
                    Text("时间分布").tag(1)
                    Text("热力矩阵").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                
                // Time Range Picker
                HStack {
                    Spacer()
                    Picker("时间范围", selection: $viewModel.timeRange) {
                        Text("7天").tag(7)
                        Text("30天").tag(30)
                        Text("90天").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: viewModel.timeRange) { _, _ in
                        Task { await viewModel.loadData() }
                    }
                }
                .padding(.horizontal, 24)
                
                // Chart Content
                if viewModel.isLoading {
                    ProgressView()
                        .frame(height: 300)
                } else {
                    switch selectedChart {
                    case 0:
                        frequencyChart
                    case 1:
                        timeDistributionChart
                    case 2:
                        heatmapMatrix
                    default:
                        frequencyChart
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .task {
            await viewModel.loadData()
        }
    }
    
    private var frequencyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("标签使用频率 Top 15")
                .font(.headline)
                .padding(.horizontal, 24)
            
            ForEach(viewModel.topTags.prefix(15)) { stat in
                HStack(spacing: 12) {
                    Text(stat.tagName)
                        .font(.body)
                        .frame(width: 100, alignment: .trailing)
                    
                    GeometryReader { geo in
                        let maxCount = viewModel.topTags.first?.usageCount ?? 1
                        let width = CGFloat(stat.usageCount) / CGFloat(maxCount) * geo.size.width
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stat.color.gradient)
                            .frame(width: max(width, 4))
                    }
                    .frame(height: 20)
                    
                    Text("\(stat.usageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 16)
    }
    
    private var timeDistributionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每日标签活动趋势")
                .font(.headline)
                .padding(.horizontal, 24)
            
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(viewModel.timeEntries.suffix(30)) { entry in
                    let maxCount = viewModel.timeEntries.map { $0.count }.max() ?? 1
                    let height = maxCount > 0 ? CGFloat(entry.count) / CGFloat(maxCount) * 150 : 0
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.gradient)
                        .frame(width: 16, height: max(height, 2))
                }
            }
            .frame(height: 180)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
    }
    
    private var heatmapMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("活动热力图")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("少").font(.caption2).foregroundStyle(.secondary)
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatColor(intensity: Double(i) / 4.0))
                            .frame(width: 12, height: 12)
                    }
                    Text("多").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(viewModel.heatmapData) { cell in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(heatColor(intensity: cell.intensity))
                        .frame(height: 24)
                        .overlay(
                            Text(cell.dayLabel)
                                .font(.caption2)
                                .foregroundStyle(cell.intensity > 0.5 ? .white : .secondary)
                        )
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
    }
    
    private func heatColor(intensity: Double) -> Color {
        intensity == 0 ? Color.gray.opacity(0.1) : Color.green.opacity(0.2 + intensity * 0.8)
    }
}

// MARK: - Tag Merge Suggestion Embedded View
struct TagMergeSuggestionEmbeddedView: View {
    @StateObject private var viewModel = TagMergeSuggestionViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("检测到 \(viewModel.suggestions.count) 对相似标签")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text("相似度").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $viewModel.minSimilarity, in: 0.5...0.95)
                        .frame(width: 100)
                        .onChange(of: viewModel.minSimilarity) { _, _ in
                            Task { await viewModel.loadSuggestions() }
                        }
                    Text("\(Int(viewModel.minSimilarity * 100))%")
                        .font(.caption.monospacedDigit())
                }
            }
            .padding(24)
            
            if viewModel.isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if viewModel.suggestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("没有发现相似标签")
                        .font(.headline)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.suggestions) { pair in
                        HStack(spacing: 16) {
                            Text(pair.tag1.name).font(.body)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(pair.tag2.name).font(.body)
                            Spacer()
                            Text(pair.displayReason).font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(pair.similarity * 100))%")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .cornerRadius(4)
                            
                            Button { Task { await viewModel.mergeSinglePair(pair) } } label: {
                                Image(systemName: "arrow.triangle.merge")
                            }
                            .buttonStyle(.bordered)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task { await viewModel.loadSuggestions() }
    }
}

// MARK: - Storage Analysis View
struct StorageAnalysisView: View {
    @State private var stats: (totalFiles: Int, totalSize: Int64, byCategory: [PARACategory: Int])?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView().frame(height: 200)
                } else if let stats = stats {
                    HStack(spacing: 16) {
                        statCard(title: "总文件数", value: "\(stats.totalFiles)", icon: "doc.fill", color: .blue)
                        statCard(title: "总大小", value: formatBytes(stats.totalSize), icon: "externaldrive.fill", color: .purple)
                        statCard(title: "分类数", value: "\(stats.byCategory.count)", icon: "folder.fill", color: .green)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("分类分布").font(.headline)
                        
                        ForEach(PARACategory.allCases) { category in
                            let count = stats.byCategory[category] ?? 0
                            let percentage = stats.totalFiles > 0 ? Double(count) / Double(stats.totalFiles) : 0
                            
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(category.color)
                                    .frame(width: 24)
                                Text(category.displayName).frame(width: 80, alignment: .leading)
                                
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(category.color.gradient)
                                        .frame(width: geo.size.width * percentage)
                                }
                                .frame(height: 16)
                                
                                Text("\(count) 个")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 24)
        }
        .task {
            isLoading = true
            stats = FileFlowManager.shared.getStatistics()
            isLoading = false
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(color)
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.05)))
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview
#Preview {
    LifecycleDashboardView()
        .frame(width: 800, height: 700)
}
