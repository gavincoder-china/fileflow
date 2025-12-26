//
//  ActivityCalendarView.swift
//  FileFlow
//
//  日历视图展示文件活动历史
//

import SwiftUI

struct ActivityCalendarView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var activityData: [Date: [FileActivity]] = [:]
    @State private var isLoading = true
    @State private var selectedDayActivities: [FileActivity] = []
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["日", "一", "二", "三", "四", "五", "六"]
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Calendar
            VStack(spacing: 0) {
                calendarHeader
                
                Divider()
                
                calendarGrid
                    .padding()
                
                Spacer()
                
                // Legend
                legend
                    .padding()
            }
            .frame(width: 340) // Fixed efficient width
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Right: Activity List
            VStack(spacing: 0) {
                activityListHeader
                
                Divider()
                
                if selectedDayActivities.isEmpty {
                    emptyActivityView
                } else {
                    activityList
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            await loadActivityData()
        }
    }
    
    // MARK: - Calendar Header
    private var calendarHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Button {
                    withAnimation { previousMonth() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .padding(4)
                
                Text(monthYearString)
                    .font(.headline)
                    .frame(width: 100, alignment: .center)
                
                Button {
                    withAnimation { nextMonth() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            .padding(4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            
            Spacer()
            
            Button("今天") {
                withAnimation {
                    currentMonth = Date()
                    selectedDate = Date()
                    updateSelectedDayActivities()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(height: 52)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Calendar Grid
    private var calendarGrid: some View {
        VStack(spacing: 12) {
            // Week day headers
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        dayCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
    }
    
    private func dayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let activityCount = activityData[calendar.startOfDay(for: date)]?.count ?? 0
        
        return Button {
            selectedDate = date
            updateSelectedDayActivities()
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? .blue : .primary))
                
                // Activity indicator
                Circle()
                    .fill(activityCount > 0 ? activityIntensityColor(count: activityCount) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 36, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : (isToday ? Color.blue.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Activity List
    private var activityListHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDateString)
                    .font(.headline)
                
                Text("\(selectedDayActivities.count) 项活动")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .frame(height: 52)
        .background(.regularMaterial)
    }
    
    private var activityList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(selectedDayActivities) { activity in
                    ActivityRow(activity: activity)
                }
            }
            .padding()
        }
    }
    
    private var emptyActivityView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("当天无文件活动")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Legend
    private var legend: some View {
        HStack(spacing: 16) {
            ForEach([("低", Color.green), ("中", Color.orange), ("高", Color.red)], id: \.0) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.1)
                        .frame(width: 8, height: 8)
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helpers
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: currentMonth)
    }
    
    private var selectedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: selectedDate)
    }
    
    private var daysInMonth: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: currentMonth)!
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        // Pad to complete last week
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
    
    private func activityIntensityColor(count: Int) -> Color {
        switch count {
        case 1...3: return .green
        case 4...7: return .orange
        default: return .red
        }
    }
    
    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }
    
    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }
    
    private func updateSelectedDayActivities() {
        let dayStart = calendar.startOfDay(for: selectedDate)
        selectedDayActivities = activityData[dayStart] ?? []
    }
    
    private func loadActivityData() async {
        isLoading = true
        
        // 获取最近3个月的文件活动
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let files = await DatabaseManager.shared.getAllFiles()
        
        var activities: [Date: [FileActivity]] = [:]
        
        for file in files {
            // 导入活动
            let importDay = calendar.startOfDay(for: file.importedAt)
            if file.importedAt >= threeMonthsAgo {
                let activity = FileActivity(
                    id: UUID(),
                    fileId: file.id,
                    fileName: file.displayName,
                    type: .imported,
                    date: file.importedAt
                )
                activities[importDay, default: []].append(activity)
            }
            
            // 最后访问活动
            let lastAccess = file.lastAccessedAt
            if lastAccess >= threeMonthsAgo {
                let accessDay = calendar.startOfDay(for: lastAccess)
                if accessDay != importDay { // 不重复显示同一天
                    let activity = FileActivity(
                        id: UUID(),
                        fileId: file.id,
                        fileName: file.displayName,
                        type: .accessed,
                        date: lastAccess
                    )
                    activities[accessDay, default: []].append(activity)
                }
            }
        }
        
        // 获取流转记录
        let transitions = await DatabaseManager.shared.getRecentTransitions(limit: 200)
        for transition in transitions where transition.triggeredAt >= threeMonthsAgo {
            let day = calendar.startOfDay(for: transition.triggeredAt)
            let activity = FileActivity(
                id: UUID(),
                fileId: transition.fileId,
                fileName: transition.fileName,
                type: .transitioned(from: transition.fromCategory, to: transition.toCategory),
                date: transition.triggeredAt
            )
            activities[day, default: []].append(activity)
        }
        
        await MainActor.run {
            activityData = activities
            updateSelectedDayActivities()
            isLoading = false
        }
    }
}

// MARK: - File Activity Model
struct FileActivity: Identifiable {
    let id: UUID
    let fileId: UUID
    let fileName: String
    let type: ActivityType
    let date: Date
    
    enum ActivityType {
        case imported
        case accessed
        case transitioned(from: PARACategory, to: PARACategory)
        case reviewed
        case tagged
        
        var icon: String {
            switch self {
            case .imported: return "arrow.down.doc.fill"
            case .accessed: return "eye.fill"
            case .transitioned: return "arrow.right.circle.fill"
            case .reviewed: return "checkmark.circle.fill"
            case .tagged: return "tag.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .imported: return .blue
            case .accessed: return .green
            case .transitioned: return .orange
            case .reviewed: return .purple
            case .tagged: return .cyan
            }
        }
        
        var description: String {
            switch self {
            case .imported: return "导入"
            case .accessed: return "访问"
            case .transitioned(let from, let to): return "\(from.displayName) → \(to.displayName)"
            case .reviewed: return "复习"
            case .tagged: return "标签"
            }
        }
    }
}

// MARK: - Activity Row
struct ActivityRow: View {
    @EnvironmentObject var appState: AppState
    let activity: FileActivity
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.icon)
                .font(.title3)
                .foregroundStyle(activity.type.color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text(activity.type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(activity.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            if isHovering {
                Image(systemName: "arrow.up.right.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { // Double click to open
            openFile()
        }
        .contextMenu {
            Button {
                openFile()
            } label: {
                Label("打开文件", systemImage: "doc.text")
            }
            
            Button {
                revealInFinder()
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            
            Divider()
            
            Button {
                showInApp()
            } label: {
                Label("在分类中查看", systemImage: "sidebar.left")
            }
        }
    }
    
    private func openFile() {
        Task {
            if let file = await DatabaseManager.shared.getFile(byId: activity.fileId) {
                await MainActor.run {
                    NSWorkspace.shared.open(URL(fileURLWithPath: file.newPath))
                }
            }
        }
    }
    
    private func revealInFinder() {
        Task {
            if let file = await DatabaseManager.shared.getFile(byId: activity.fileId) {
                await MainActor.run {
                    FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
                }
            }
        }
    }
    
    private func showInApp() {
        Task {
            if let file = await DatabaseManager.shared.getFile(byId: activity.fileId) {
                await MainActor.run {
                    appState.navigationTarget = AppState.NavigationTarget(
                        category: file.category,
                        subcategory: file.subcategory,
                        file: file
                    )
                }
            }
        }
    }
}

#Preview {
    ActivityCalendarView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
