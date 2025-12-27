//
//  SmartOrganizeView.swift
//  FileFlow
//
//  智能整理助手 - 统一入口
//  包含标签合并和文件夹合并功能
//

import SwiftUI

struct SmartOrganizeView: View {
    @EnvironmentObject var appState: AppState
    
    // Use persisted ViewModel from AppState
    private var viewModel: SmartOrganizeViewModel {
        appState.smartOrganizeViewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ZStack {
                if !viewModel.hasStarted {
                    startView
                } else if viewModel.isLoading {
                    loadingView
                } else if viewModel.folderSuggestions.isEmpty && viewModel.tagSuggestions.isEmpty {
                    emptyView
                } else {
                    resultsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Leading: Title
                Label("智能整理助手", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                
                if !viewModel.isLoading {
                    Text("AI 驱动的知识库优化")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                // Stats (Only show if results available)
                if viewModel.hasStarted && !viewModel.isLoading {
                    HStack(spacing: 16) {
                        if !viewModel.folderSuggestions.isEmpty {
                            Label("\(viewModel.folderSuggestions.count) 个文件夹建议", systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !viewModel.tagSuggestions.isEmpty {
                            Label("\(viewModel.tagSuggestions.count) 个标签建议", systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(.regularMaterial)
    }
    
    // MARK: - Start View
    
    private var startView: some View {
        VStack(spacing: 32) {
            HStack(spacing: 40) {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.gear")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)
                    Text("文件夹整理")
                        .font(.headline)
                }
                
                Image(systemName: "plus")
                    .font(.title)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 12) {
                    Image(systemName: "tag.square.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange.gradient)
                    Text("标签优化")
                        .font(.headline)
                }
            }
            
            VStack(spacing: 8) {
                Text("一键分析您的知识库")
                    .font(.title2.bold())
                Text("AI 将深度分析所有文件夹结构与标签体系，\n检测并整合语义重复项，让您的知识库井井有条。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            
            Button {
                Task { await viewModel.startAnalysis() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("开始全面分析")
                }
                .font(.headline)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            VStack(spacing: 8) {
                Text("AI 正在分析知识库...")
                    .font(.headline)
                Text(viewModel.loadingStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green.gradient)
            
            VStack(spacing: 8) {
                Text("知识库非常整洁")
                    .font(.title3.bold())
                Text("没有发现需要合并的文件夹或标签")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            Button("重新分析") {
                Task { await viewModel.startAnalysis() }
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Folders Section
                if !viewModel.folderSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "文件夹合并建议", icon: "folder", count: viewModel.folderSuggestions.count, color: .blue)
                        
                        ForEach(viewModel.folderSuggestions) { suggestion in
                            FolderMergeSuggestionRow(
                                suggestion: suggestion,
                                isSelected: false, // Unified view currently handles single merges
                                onToggle: {},
                                onMerge: {
                                    Task {
                                        await viewModel.mergeFolder(suggestion)
                                        appState.refreshData()
                                    }
                                }
                            )
                        }
                    }
                }
                
                // Tags Section
                if !viewModel.tagSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "标签合并建议", icon: "tag", count: viewModel.tagSuggestions.count, color: .orange)
                        
                        ForEach(viewModel.tagSuggestions) { suggestion in
                            TagMergeSuggestionRow(
                                suggestion: suggestion,
                                onMerge: {
                                    Task {
                                        await viewModel.mergeTag(suggestion)
                                        appState.refreshData()
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count) 项")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(color.opacity(0.1))
                .foregroundStyle(color)
                .cornerRadius(4)
        }
        .padding(.top, 8)
    }
}

// MARK: - Tag Merge Suggestion Row
struct TagMergeSuggestionRow: View {
    let suggestion: MergeSuggestion
    let onMerge: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Source Tag
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.orange)
                Text(suggestion.source.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            // Similarity Badge
            Text(suggestion.similarityPercent)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(suggestion.similarityLevel == .high ? Color.green : suggestion.similarityLevel == .medium ? Color.orange : Color.gray)
                .cornerRadius(4)
            
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            
            // Target Tag
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.green)
                Text(suggestion.target.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Reason
            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 200, alignment: .trailing)
            
            // Merge Button
            Button(action: onMerge) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - ViewModel

@MainActor
class SmartOrganizeViewModel: ObservableObject {
    @Published var folderSuggestions: [MergeSuggestion] = []
    @Published var tagSuggestions: [MergeSuggestion] = []  // Now using AI-powered MergeSuggestion
    @Published var isLoading = false
    @Published var hasStarted = false
    @Published var loadingStatus = "准备中..."
    
    func startAnalysis() async {
        Logger.info("🔍 SmartOrganize: 开始分析...")
        hasStarted = true
        isLoading = true
        loadingStatus = "正在扫描文件夹结构..."
        
        var folders: [MergeSuggestion] = []
        var tags: [MergeSuggestion] = []
        
        // 分析文件夹
        do {
            loadingStatus = "正在分析文件夹..."
            folders = try await SmartMergeService.shared.analyzeAllFoldersForMerge()
            Logger.info("🔍 SmartOrganize: 文件夹分析完成，找到 \(folders.count) 条建议")
        } catch {
            Logger.error("🔍 SmartOrganize: 文件夹分析失败 - \(error.localizedDescription)")
        }
        
        // 分析标签
        loadingStatus = "正在分析标签..."
        tags = await SmartMergeService.shared.analyzeTagsForMerge()
        Logger.info("🔍 SmartOrganize: 标签分析完成，找到 \(tags.count) 条建议")
        
        withAnimation {
            self.folderSuggestions = folders
            self.tagSuggestions = tags
        }
        
        isLoading = false
        Logger.success("🔍 SmartOrganize: 分析完成！")
    }
    
    func mergeFolder(_ suggestion: MergeSuggestion) async {
        let success = await SmartMergeService.shared.executeFolderMerge(suggestion: suggestion)
        if success {
            withAnimation {
                folderSuggestions.removeAll { $0.id == suggestion.id }
            }
        }
    }
    
    func mergeTag(_ suggestion: MergeSuggestion) async {
        let success = await SmartMergeService.shared.executeTagMerge(suggestion: suggestion)
        if success {
            withAnimation {
                tagSuggestions.removeAll { $0.id == suggestion.id }
            }
        }
    }
}
