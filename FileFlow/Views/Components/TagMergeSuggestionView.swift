//
//  TagMergeSuggestionView.swift
//  FileFlow
//
//  智能标签合并建议视图
//  显示相似标签并提供合并操作
//

import SwiftUI

// MARK: - Tag Merge Suggestion View
struct TagMergeSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TagMergeSuggestionViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                loadingView
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
        .frame(width: 650, height: 500)
        .background(.ultraThinMaterial)
        .task {
            await viewModel.loadSuggestions()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("智能标签合并")
                    .font(.title2.bold())
                Text("检测到 \(viewModel.suggestions.count) 对相似标签")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Threshold Slider
            HStack(spacing: 8) {
                Text("相似度阈值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(value: $viewModel.minSimilarity, in: 0.5...0.95)
                    .frame(width: 100)
                    .onChange(of: viewModel.minSimilarity) { _, _ in
                        Task { await viewModel.loadSuggestions() }
                    }
                
                Text("\(Int(viewModel.minSimilarity * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 35)
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
    
    // MARK: - Suggestions List
    private var suggestionsList: some View {
        List {
            ForEach(viewModel.suggestions) { pair in
                TagPairRow(
                    pair: pair,
                    isSelected: viewModel.selectedPairs.contains(pair.id),
                    onToggle: { viewModel.toggleSelection(pair) },
                    onMerge: { Task { await viewModel.mergeSinglePair(pair) } }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在分析标签...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty View
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("没有发现相似标签")
                .font(.headline)
            Text("您的标签系统非常整洁！")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button {
                viewModel.selectAll()
            } label: {
                Text(viewModel.allSelected ? "取消全选" : "全选")
            }
            .buttonStyle(.bordered)
            
            Text("\(viewModel.selectedPairs.count) 对已选")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("取消") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button {
                Task {
                    await viewModel.mergeSelected()
                    if viewModel.suggestions.isEmpty {
                        dismiss()
                    }
                }
            } label: {
                Label("合并选中", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedPairs.isEmpty || viewModel.isMerging)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Tag Pair Row
struct TagPairRow: View {
    let pair: TagSimilarityPair
    let isSelected: Bool
    let onToggle: () -> Void
    let onMerge: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            
            // Tag 1
            tagBadge(pair.tag1, highlight: pair.tag1.id == pair.suggestedKeep.id)
            
            // Arrow
            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pair.displayReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // Tag 2
            tagBadge(pair.tag2, highlight: pair.tag2.id == pair.suggestedKeep.id)
            
            Spacer()
            
            // Similarity
            Text("\(Int(pair.similarity * 100))%")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(similarityColor.opacity(0.1))
                .foregroundStyle(similarityColor)
                .cornerRadius(4)
            
            // Single Merge Button
            Button {
                onMerge()
            } label: {
                Image(systemName: "arrow.triangle.merge")
            }
            .buttonStyle(.borderless)
            .help("合并这对标签")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }
    
    private func tagBadge(_ tag: Tag, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text(tag.name)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(highlight ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(highlight ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            
            Text("\(tag.usageCount) 文件")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private var similarityColor: Color {
        if pair.similarity >= 0.9 { return .red }
        if pair.similarity >= 0.8 { return .orange }
        return .yellow
    }
}

// MARK: - ViewModel
@MainActor
class TagMergeSuggestionViewModel: ObservableObject {
    @Published var suggestions: [TagSimilarityPair] = []
    @Published var selectedPairs: Set<UUID> = []
    @Published var isLoading = false
    @Published var isMerging = false
    @Published var minSimilarity: Double = 0.7
    
    var allSelected: Bool {
        !suggestions.isEmpty && selectedPairs.count == suggestions.count
    }
    
    func loadSuggestions() async {
        isLoading = true
        suggestions = await TagMergeService.shared.findSimilarTags(minSimilarity: minSimilarity)
        selectedPairs.removeAll()
        isLoading = false
    }
    
    func toggleSelection(_ pair: TagSimilarityPair) {
        if selectedPairs.contains(pair.id) {
            selectedPairs.remove(pair.id)
        } else {
            selectedPairs.insert(pair.id)
        }
    }
    
    func selectAll() {
        if allSelected {
            selectedPairs.removeAll()
        } else {
            selectedPairs = Set(suggestions.map { $0.id })
        }
    }
    
    func mergeSinglePair(_ pair: TagSimilarityPair) async {
        isMerging = true
        _ = await TagMergeService.shared.mergeTags(from: pair.suggestedMerge, to: pair.suggestedKeep)
        suggestions.removeAll { $0.id == pair.id }
        selectedPairs.remove(pair.id)
        isMerging = false
    }
    
    func mergeSelected() async {
        isMerging = true
        let pairsToMerge = suggestions.filter { selectedPairs.contains($0.id) }
        _ = await TagMergeService.shared.batchMergeTags(pairs: pairsToMerge)
        
        // Remove merged pairs
        suggestions.removeAll { selectedPairs.contains($0.id) }
        selectedPairs.removeAll()
        isMerging = false
    }
}
