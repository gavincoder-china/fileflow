//
//  LifecycleViews.swift
//  FileFlow
//
//  文件生命周期 UI 组件
//  包含状态徽章、流转历史、清理建议等视图
//

import SwiftUI

// MARK: - Lifecycle Status Badge
/// 显示文件生命周期状态的小徽章
struct LifecycleStatusBadge: View {
    let stage: FileLifecycleStage
    var showLabel: Bool = true
    var size: BadgeSize = .regular
    
    enum BadgeSize {
        case mini, small, regular, large
        
        var iconSize: CGFloat {
            switch self {
            case .mini: return 8
            case .small: return 10
            case .regular: return 12
            case .large: return 16
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .mini: return 9
            case .small: return 10
            case .regular: return 11
            case .large: return 13
            }
        }
        
        var padding: CGFloat {
            switch self {
            case .mini: return 2
            case .small: return 4
            case .regular: return 6
            case .large: return 8
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: stage.icon)
                .font(.system(size: size.iconSize, weight: .semibold))
            
            if showLabel {
                Text(stage.displayName)
                    .font(.system(size: size.fontSize, weight: .medium))
            }
        }
        .foregroundStyle(stage.color)
        .padding(.horizontal, size.padding)
        .padding(.vertical, size.padding / 2)
        .background(
            Capsule()
                .fill(stage.color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(stage.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Days Since Access Label
struct DaysSinceAccessLabel: View {
    let lastAccessedAt: Date
    
    var daysSince: Int {
        Calendar.current.dateComponents([.day], from: lastAccessedAt, to: Date()).day ?? 0
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
            Text(formattedDays)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
    
    private var formattedDays: String {
        switch daysSince {
        case 0: return "今天"
        case 1: return "昨天"
        case 2...7: return "\(daysSince)天前"
        case 8...30: return "\(daysSince / 7)周前"
        case 31...365: return "\(daysSince / 30)个月前"
        default: return "超过1年"
        }
    }
}

// MARK: - Transition Reason Badge
struct TransitionReasonBadge: View {
    let reason: TransitionReason
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: reason.icon)
                .font(.system(size: 10))
            Text(reason.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - File Transition History View
/// 显示单个文件的流转历史时间线
struct FileTransitionHistoryView: View {
    let fileId: UUID
    @State private var transitions: [FileTransition] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("流转历史")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 12)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if transitions.isEmpty {
                emptyState
            } else {
                timelineView
            }
        }
        .task {
            await loadTransitions()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("暂无流转记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    private var timelineView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(transitions.enumerated()), id: \.element.id) { index, transition in
                TransitionTimelineItem(
                    transition: transition,
                    isFirst: index == 0,
                    isLast: index == transitions.count - 1
                )
            }
        }
    }
    
    private func loadTransitions() async {
        transitions = await LifecycleService.shared.getTransitionHistory(for: fileId)
        isLoading = false
    }
}

// MARK: - Transition Timeline Item
struct TransitionTimelineItem: View {
    let transition: FileTransition
    let isFirst: Bool
    let isLast: Bool
    var onUndo: ((FileTransition) -> Void)? = nil
    
    @State private var isUndoing = false
    @State private var showUndoSuccess = false
    
    // 检查是否可撤销 (24小时内)
    private var isUndoable: Bool {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return transition.triggeredAt > cutoff
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline Line + Dot
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2, height: 12)
                }
                
                Circle()
                    .fill(transition.toCategory.color)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
                
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .frame(minHeight: 40)
                }
            }
            .frame(width: 12)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Date
                Text(transition.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Transition description
                HStack(spacing: 8) {
                    categoryBadge(transition.fromCategory)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    categoryBadge(transition.toCategory)
                }
                
                // Reason
                TransitionReasonBadge(reason: transition.reason)
                
                // Notes
                if let notes = transition.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            
            Spacer()
            
            // Undo Button (24小时内可撤销)
            if isUndoable && onUndo != nil {
                Button {
                    performUndo()
                } label: {
                    if isUndoing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 24, height: 24)
                    } else if showUndoSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("撤销此操作")
                .disabled(isUndoing || showUndoSuccess)
            }
        }
    }
    
    private func performUndo() {
        isUndoing = true
        Task {
            let success = await LifecycleService.shared.undoTransition(transition)
            await MainActor.run {
                isUndoing = false
                if success {
                    showUndoSuccess = true
                    onUndo?(transition)
                }
            }
        }
    }
    
    @ViewBuilder
    private func categoryBadge(_ category: PARACategory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10))
            Text(category.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(category.color.opacity(0.1))
        )
    }
}

// MARK: - Cleanup Suggestions View
/// 显示需要清理的文件建议列表
struct CleanupSuggestionsView: View {
    @State private var suggestions: [LifecycleCleanupSuggestion] = []
    @State private var isLoading = true
    @State private var selectedSuggestions: Set<UUID> = []
    @State private var showingConfirmation = false
    
    var isEmbedded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            if !isEmbedded {
                headerView
                Divider()
            }
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if suggestions.isEmpty {
                emptyStateView
            } else {
                suggestionsList
            }
            
            if !suggestions.isEmpty {
                Divider()
                actionBar
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await loadSuggestions()
        }
        .confirmationDialog(
            "确认归档所选文件",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("归档 \(selectedSuggestions.count) 个文件", role: .destructive) {
                Task { await archiveSelected() }
            }
            Button("取消", role: .cancel) {}
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("🧹 整理建议")
                    .font(.title2.bold())
                Text("以下文件长期未使用，建议归档或清理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                Task { await loadSuggestions() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("太棒了！")
                .font(.title2.bold())
            
            Text("没有需要整理的文件")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    CleanupSuggestionRow(
                        suggestion: suggestion,
                        isSelected: selectedSuggestions.contains(suggestion.id)
                    ) {
                        toggleSelection(suggestion.id)
                    }
                }
            }
            .padding()
        }
    }
    
    private var actionBar: some View {
        HStack {
            Button("全选") {
                selectedSuggestions = Set(suggestions.map { $0.id })
            }
            .buttonStyle(.borderless)
            
            Button("取消全选") {
                selectedSuggestions.removeAll()
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Text("\(selectedSuggestions.count) 个已选")
                .foregroundStyle(.secondary)
                .font(.callout)
            
            Button("归档所选") {
                showingConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSuggestions.isEmpty)
        }
        .padding()
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedSuggestions.contains(id) {
            selectedSuggestions.remove(id)
        } else {
            selectedSuggestions.insert(id)
        }
    }
    
    private func loadSuggestions() async {
        isLoading = true
        suggestions = await LifecycleService.shared.getCleanupSuggestions()
        isLoading = false
    }
    
    private func archiveSelected() async {
        let filesToArchive = suggestions
            .filter { selectedSuggestions.contains($0.id) }
            .map { $0.file }
        
        await LifecycleService.shared.batchArchiveStaleFiles(files: filesToArchive)
        
        // Reload suggestions
        await loadSuggestions()
        selectedSuggestions.removeAll()
    }
}

// MARK: - Cleanup Suggestion Row
struct CleanupSuggestionRow: View {
    let suggestion: LifecycleCleanupSuggestion
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.title3)
            
            // File Icon
            Image(systemName: suggestion.file.icon)
                .foregroundStyle(suggestion.file.category.color)
                .font(.title2)
                .frame(width: 32)
            
            // File Info
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.file.displayName)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    LifecycleStatusBadge(stage: suggestion.stage, size: .small)
                    DaysSinceAccessLabel(lastAccessedAt: suggestion.file.lastAccessedAt)
                    
                    Text(suggestion.file.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Suggested Action
            Text(suggestion.suggestedAction.rawValue)
                .font(.caption)
                .foregroundStyle(suggestion.suggestedAction.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(suggestion.suggestedAction.color.opacity(0.1))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Lifecycle Stats Card
/// 显示生命周期统计数据的卡片组件
struct LifecycleStatsCard: View {
    @State private var stats: [FileLifecycleStage: Int] = [:]
    @State private var isLoading = true
    
    var totalFiles: Int {
        stats.values.reduce(0, +)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.blue)
                Text("文件状态概览")
                    .font(.headline)
                Spacer()
            }
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 16) {
                    ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
                        statItem(stage: stage, count: stats[stage] ?? 0)
                    }
                }
            }
        }
        .padding()
        .glass(cornerRadius: 16)
        .task {
            stats = await LifecycleService.shared.getLifecycleStats()
            isLoading = false
        }
    }
    
    @ViewBuilder
    private func statItem(stage: FileLifecycleStage, count: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: stage.icon)
                .font(.title2)
                .foregroundStyle(stage.color)
            
            Text("\(count)")
                .font(.title3.bold())
            
            Text(stage.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview("Lifecycle Status Badge") {
    VStack(spacing: 12) {
        ForEach(FileLifecycleStage.allCases, id: \.self) { stage in
            HStack {
                LifecycleStatusBadge(stage: stage, size: .small)
                LifecycleStatusBadge(stage: stage)
                LifecycleStatusBadge(stage: stage, size: .large)
            }
        }
    }
    .padding()
}

#Preview("Transition Reason Badges") {
    VStack(spacing: 8) {
        ForEach(TransitionReason.allCases.prefix(6), id: \.self) { reason in
            TransitionReasonBadge(reason: reason)
        }
    }
    .padding()
}
