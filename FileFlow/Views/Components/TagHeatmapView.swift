//
//  TagHeatmapView.swift
//  FileFlow
//
//  标签热力图视图
//  可视化标签使用频率和时间分布
//

import SwiftUI
import Charts

// MARK: - Tag Usage Stats
struct TagUsageStats: Identifiable {
    let id: UUID
    let tagName: String
    let usageCount: Int
    let color: Color
    let lastUsed: Date?
}

// MARK: - Tag Time Entry
struct TagTimeEntry: Identifiable {
    let id = UUID()
    let date: Date
    let tagName: String
    let count: Int
}

// MARK: - Tag Heatmap View
struct TagHeatmapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TagHeatmapViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("使用频率").tag(0)
                Text("时间分布").tag(1)
                Text("热力矩阵").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            if viewModel.isLoading {
                loadingView
            } else {
                switch selectedTab {
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
        .frame(width: 800, height: 600)
        .background(.ultraThinMaterial)
        .task {
            await viewModel.loadData()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("标签热力图")
                    .font(.title2.bold())
                Text("共 \(viewModel.tagStats.count) 个标签")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Time Range
            Picker("时间范围", selection: $viewModel.timeRange) {
                Text("7天").tag(7)
                Text("30天").tag(30)
                Text("90天").tag(90)
                Text("全部").tag(365)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .onChange(of: viewModel.timeRange) { _, _ in
                Task { await viewModel.loadData() }
            }
            
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Frequency Chart
    private var frequencyChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("标签使用频率 Top 20")
                .font(.headline)
                .padding(.horizontal)
            
            Chart(viewModel.topTags) { stat in
                BarMark(
                    x: .value("使用次数", stat.usageCount),
                    y: .value("标签", stat.tagName)
                )
                .foregroundStyle(stat.color.gradient)
                .annotation(position: .trailing) {
                    Text("\(stat.usageCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .padding()
        }
        .padding()
    }
    
    // MARK: - Time Distribution Chart
    private var timeDistributionChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("标签活动时间分布")
                .font(.headline)
                .padding(.horizontal)
            
            Chart(viewModel.timeEntries) { entry in
                LineMark(
                    x: .value("日期", entry.date),
                    y: .value("次数", entry.count)
                )
                .foregroundStyle(Color.blue.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("日期", entry.date),
                    y: .value("次数", entry.count)
                )
                .foregroundStyle(Color.blue.opacity(0.1).gradient)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: viewModel.timeRange > 30 ? 7 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                    AxisGridLine()
                }
            }
            .padding()
        }
        .padding()
    }
    
    // MARK: - Heatmap Matrix
    private var heatmapMatrix: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("标签使用热力矩阵")
                    .font(.headline)
                
                Spacer()
                
                // Legend
                HStack(spacing: 4) {
                    Text("少")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatColor(intensity: Double(i) / 4.0))
                            .frame(width: 12, height: 12)
                    }
                    
                    Text("多")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(viewModel.heatmapData) { cell in
                        heatmapCell(cell)
                    }
                }
                .padding()
            }
        }
        .padding()
    }
    
    private func heatmapCell(_ cell: HeatmapCell) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(heatColor(intensity: cell.intensity))
            .frame(height: 20)
            .overlay(
                Text(cell.dayLabel)
                    .font(.caption2)
                    .foregroundStyle(cell.intensity > 0.5 ? .white : .secondary)
            )
            .help("\(cell.date.formatted(date: .abbreviated, time: .omitted)): \(cell.count) 次操作")
    }
    
    private func heatColor(intensity: Double) -> Color {
        if intensity == 0 { return Color.gray.opacity(0.1) }
        return Color.green.opacity(0.2 + intensity * 0.8)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载数据...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Heatmap Cell
struct HeatmapCell: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let intensity: Double // 0.0 - 1.0
    
    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - ViewModel
@MainActor
class TagHeatmapViewModel: ObservableObject {
    @Published var tagStats: [TagUsageStats] = []
    @Published var timeEntries: [TagTimeEntry] = []
    @Published var heatmapData: [HeatmapCell] = []
    @Published var isLoading = false
    @Published var timeRange = 30
    
    private let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan, .indigo, .mint, .teal, .yellow]
    
    var topTags: [TagUsageStats] {
        Array(tagStats.sorted { $0.usageCount > $1.usageCount }.prefix(20))
    }
    
    func loadData() async {
        isLoading = true
        
        // Load all tags
        let tags = await DatabaseManager.shared.getAllTags()
        
        // Create tag stats
        tagStats = tags.enumerated().map { index, tag in
            TagUsageStats(
                id: tag.id,
                tagName: tag.name,
                usageCount: tag.usageCount,
                color: colors[index % colors.count],
                lastUsed: nil
            )
        }
        
        // Generate time entries (aggregated by day)
        await loadTimeDistribution()
        
        // Generate heatmap data
        generateHeatmapData()
        
        isLoading = false
    }
    
    private func loadTimeDistribution() async {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -timeRange, to: endDate)!
        
        // Get recent files to analyze their import dates
        let files = await DatabaseManager.shared.getRecentFiles(limit: 1000)
        
        // Group by date
        var dailyCounts: [Date: Int] = [:]
        
        for file in files {
            let dayStart = calendar.startOfDay(for: file.importedAt)
            if dayStart >= startDate {
                dailyCounts[dayStart, default: 0] += file.tags.count
            }
        }
        
        // Fill in missing days
        var entries: [TagTimeEntry] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            let dayStart = calendar.startOfDay(for: currentDate)
            entries.append(TagTimeEntry(
                date: dayStart,
                tagName: "all",
                count: dailyCounts[dayStart] ?? 0
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        timeEntries = entries
    }
    
    private func generateHeatmapData() {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -timeRange, to: endDate)!
        
        // Find max count for normalization
        let maxCount = timeEntries.map { $0.count }.max() ?? 1
        
        var cells: [HeatmapCell] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            let dayStart = calendar.startOfDay(for: currentDate)
            let count = timeEntries.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.count ?? 0
            let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0
            
            cells.append(HeatmapCell(date: dayStart, count: count, intensity: intensity))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        heatmapData = cells
    }
}
