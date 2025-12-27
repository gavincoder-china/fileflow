//
//  FolderMergeSuggestionView.swift
//  FileFlow
//
//  文件夹智能合并建议视图
//

import SwiftUI

struct FolderMergeSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FolderMergeSuggestionViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Content
            if !viewModel.hasStarted {
                startView
            } else if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(message: error)
            } else if viewModel.suggestions.isEmpty {
                emptyView
            } else {
                suggestionsList
            }
            
            // Footer
            if !viewModel.suggestions.isEmpty {
                footerView
            }
        }
        .frame(width: 700, height: 550)
        .background(.ultraThinMaterial)
        .frame(width: 700, height: 550)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("智能文件夹合并")
                    .font(.title2.bold())
                Text("检测到 \(viewModel.suggestions.count) 对相似文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("AI 正在分析文件夹结构...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Start View
    
    private var startView: some View {
        VStack(spacing: 24) {
             Image(systemName: "sparkles.rectangle.stack")
                 .font(.system(size: 64))
                 .foregroundStyle(.purple.gradient)
             
             VStack(spacing: 8) {
                 Text("AI 智能文件夹整理")
                     .font(.title2.bold())
                 Text("AI 将分析文件夹名称与结构，基于 PARA 理念提供合并建议")
                     .font(.body)
                     .foregroundStyle(.secondary)
                     .multilineTextAlignment(.center)
                     .frame(maxWidth: 400)
             }
             
             Button {
                 Task { await viewModel.loadSuggestions() }
             } label: {
                 HStack {
                     Image(systemName: "sparkles")
                     Text("开始 AI 分析")
                 }
                 .font(.headline)
                 .padding(.horizontal, 24)
                 .padding(.vertical, 12)
             }
             .buttonStyle(.borderedProminent)
             .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("分析过程中出错")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                Task { await viewModel.loadSuggestions() }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Emtpy
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("没有发现相似文件夹")
                .font(.headline)
            Text("您的文件夹结构非常整洁！")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Debug button for Demo
            /*
            Button("加载演示数据") {
                // Implementation requires calling specific mock method or setting mock provider
            }
            .font(.caption)
            */
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Suggestions List
    
    private var suggestionsList: some View {
        List {
            ForEach(viewModel.suggestions) { suggestion in
                FolderMergeSuggestionRow(
                    suggestion: suggestion,
                    isSelected: viewModel.selectedSuggestions.contains(suggestion.id),
                    onToggle: { viewModel.toggleSelection(suggestion) },
                    onMerge: { Task { await viewModel.mergeSingle(suggestion) } }
                )
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button {
                viewModel.selectAll()
            } label: {
                Text(viewModel.allSelected ? "取消全选" : "全选")
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("\(viewModel.selectedSuggestions.count) 项已选择")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                Task { await viewModel.mergeSelected() }
            } label: {
                if viewModel.isMerging {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("合并选中")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedSuggestions.isEmpty || viewModel.isMerging)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Suggestion Row

struct FolderMergeSuggestionRow: View {
    let suggestion: MergeSuggestion
    let isSelected: Bool
    let onToggle: () -> Void
    let onMerge: () -> Void
    
    private var sourceInfo: (category: PARACategory?, name: String)? {
        if case .folder(let cat, let name) = suggestion.source {
            return (cat, name)
        }
        return nil
    }
    
    private var targetInfo: (category: PARACategory?, name: String)? {
        if case .folder(let cat, let name) = suggestion.target {
            return (cat, name)
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            
            // Source Folder
            if let source = sourceInfo {
                folderBadge(name: source.name, category: source.category, highlight: false)
            }
            
            // Arrow
            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.similarityPercent)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(similarityColor.opacity(0.15))
                    .foregroundStyle(similarityColor)
                    .cornerRadius(4)
            }
            
            // Target Folder
            if let target = targetInfo {
                folderBadge(name: target.name, category: target.category, highlight: true)
            }
            
            Spacer()
            
            // Reason
            VStack(alignment: .trailing, spacing: 2) {
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                
                if let suggestedName = suggestion.suggestedName {
                    Text("建议名称: \(suggestedName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 180)
            
            // Merge Button
            Button {
                onMerge()
            } label: {
                Image(systemName: "arrow.triangle.merge")
            }
            .buttonStyle(.borderless)
            .help("合并这对文件夹")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }
    
    private func folderBadge(name: String, category: PARACategory?, highlight: Bool) -> some View {
        let color = category?.color ?? .secondary
        
        return VStack(spacing: 4) {
            Image(systemName: highlight ? "folder.fill" : "folder")
                .font(.title2)
                .foregroundStyle(color)
            
            Text(name)
                .font(.caption)
                .fontWeight(highlight ? .medium : .regular)
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlight ? color.opacity(0.1) : Color.clear)
        )
    }
    
    private var similarityColor: Color {
        switch suggestion.similarityLevel {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

// MARK: - ViewModel

@MainActor
class FolderMergeSuggestionViewModel: ObservableObject {
    @Published var suggestions: [MergeSuggestion] = []
    @Published var selectedSuggestions: Set<UUID> = []
    @Published var isLoading = false
    @Published var isMerging = false
    @Published var errorMessage: String?
    @Published var hasStarted = false
    
    var allSelected: Bool {
        !suggestions.isEmpty && selectedSuggestions.count == suggestions.count
    }
    
    func loadSuggestions() async {
        hasStarted = true
        isLoading = true
        errorMessage = nil
        do {
            suggestions = try await SmartMergeService.shared.analyzeAllFoldersForMerge()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func toggleSelection(_ suggestion: MergeSuggestion) {
        if selectedSuggestions.contains(suggestion.id) {
            selectedSuggestions.remove(suggestion.id)
        } else {
            selectedSuggestions.insert(suggestion.id)
        }
    }
    
    func selectAll() {
        if allSelected {
            selectedSuggestions.removeAll()
        } else {
            selectedSuggestions = Set(suggestions.map { $0.id })
        }
    }
    
    func mergeSingle(_ suggestion: MergeSuggestion) async {
        isMerging = true
        _ = await SmartMergeService.shared.executeFolderMerge(suggestion: suggestion)
        suggestions.removeAll { $0.id == suggestion.id }
        selectedSuggestions.remove(suggestion.id)
        isMerging = false
    }
    
    func mergeSelected() async {
        isMerging = true
        let toMerge = suggestions.filter { selectedSuggestions.contains($0.id) }
        
        for suggestion in toMerge {
            _ = await SmartMergeService.shared.executeFolderMerge(suggestion: suggestion)
        }
        
        suggestions.removeAll { selectedSuggestions.contains($0.id) }
        selectedSuggestions.removeAll()
        isMerging = false
    }
}
