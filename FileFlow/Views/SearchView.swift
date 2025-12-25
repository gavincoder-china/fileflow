//
//  SearchView.swift
//  FileFlow
//
//  Created by Auto-Agent
//

import SwiftUI

// MARK: - Search View
struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchResults: [ManagedFile] = []
    @State private var semanticResults: [SemanticSearchResult] = []
    @State private var isSearching = false
    @State private var useSemanticSearch = false
    @FocusState private var isSearchFieldFocused: Bool
    
    @State private var selectedFile: ManagedFile?
    
    // Reader State - using item binding
    @State private var fileForReader: ManagedFile?
    
    private let database = DatabaseManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Search Content
            VStack(spacing: 0) {
                // Search Field
                HStack(spacing: 16) {
                    Image(systemName: useSemanticSearch ? "brain" : "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(useSemanticSearch ? .purple : .secondary)
                    
                    TextField(useSemanticSearch ? "语义搜索..." : "搜索文件、标签、备注...", text: $appState.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            Task { await performSearch() }
                        }
                    
                    // Semantic Search Toggle
                    Button {
                        useSemanticSearch.toggle()
                        if !appState.searchQuery.isEmpty {
                            Task { await performSearch() }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                            Text("语义")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(useSemanticSearch ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundStyle(useSemanticSearch ? .purple : .secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("语义搜索基于内容相似度匹配")
                    
                    if !appState.searchQuery.isEmpty {
                        Button {
                            appState.searchQuery = ""
                            searchResults = []
                            semanticResults = []
                            selectedFile = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .glass(cornerRadius: 32, material: .regular)
                .padding(24)
                .padding(.top, 16)
                .frame(maxWidth: 800)
                
                // Results
                if isSearching {
                    Spacer()
                    ProgressView(useSemanticSearch ? "语义分析中..." : "搜索中...")
                    Spacer()
                } else if appState.searchQuery.isEmpty {
                    ContentUnavailableView(
                        useSemanticSearch ? "语义搜索" : "搜索文件",
                        systemImage: useSemanticSearch ? "brain" : "magnifyingglass",
                        description: Text(useSemanticSearch ? "基于内容相似度查找相关文件" : "输入关键词搜索文件名、标签或备注")
                    )
                    .opacity(0.6)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else if searchResults.isEmpty && semanticResults.isEmpty {
                    ContentUnavailableView(
                        "无结果",
                        systemImage: "doc.questionmark",
                        description: Text("未找到匹配「\(appState.searchQuery)」的文件")
                    )
                    .opacity(0.6)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else if useSemanticSearch {
                    // Semantic Results
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("找到 \(semanticResults.count) 个相关文件")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("按相似度排序")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        
                        List {
                            ForEach(semanticResults) { result in
                                Button {
                                    selectedFile = result.file
                                } label: {
                                    HStack {
                                        Image(systemName: result.file.category.icon)
                                            .foregroundStyle(result.file.category.color)
                                            .frame(width: 24)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.file.displayName)
                                                .font(.body)
                                            Text(result.file.category.displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(result.similarityPercent)
                                            .font(.caption.monospacedDigit())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(similarityColor(result.similarity).opacity(0.1))
                                            .foregroundStyle(similarityColor(result.similarity))
                                            .cornerRadius(4)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    // Regular Results
                    VStack(alignment: .leading, spacing: 0) {
                        Text("找到 \(searchResults.count) 个结果")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                        
                        CategoryFileListView(
                            isLoading: false,
                            files: searchResults,
                            selectedFile: $selectedFile,
                            onReveal: { file in
                                FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
                            },
                            onRename: { _ in },
                            onDuplicate: { _ in },
                            onMove: { _ in },
                            onDelete: { _ in },
                            onOpenReader: { file in
                                fileForReader = file
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Inspector
            if let file = selectedFile {
                Divider()
                FileInspectorPane(
                    file: file,
                    onClose: { selectedFile = nil },
                    onUpdateTags: { tags in
                        Task {
                            await FileFlowManager.shared.updateFileTags(for: file, tags: tags)
                            await performSearch()
                        }
                    },
                    onOpenReader: {
                        fileForReader = file
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isSearchFieldFocused = true
            if !appState.searchQuery.isEmpty {
                Task { await performSearch() }
            }
        }
        .onChange(of: appState.searchQuery) { _, newValue in
            if newValue.count >= 2 {
                Task { await performSearch() }
            } else {
                searchResults = []
                semanticResults = []
            }
        }
        .sheet(item: $fileForReader) { file in
            UniversalReaderView(file: file)
                .frame(minWidth: 900, minHeight: 700)
        }
    }
    
    @State private var parsedQueryDescription: String = ""
    
    private func performSearch() async {
        guard !appState.searchQuery.isEmpty else { return }
        
        isSearching = true
        
        if useSemanticSearch {
            semanticResults = await SemanticSearchService.shared.search(query: appState.searchQuery)
            searchResults = []
            parsedQueryDescription = ""
        } else {
            // 使用自然语言解析
            let parsed = NaturalLanguageQueryService.shared.parse(appState.searchQuery)
            parsedQueryDescription = NaturalLanguageQueryService.shared.describeQuery(parsed)
            
            if parsed.isEmpty {
                // 如果解析结果为空，使用普通关键词搜索
                searchResults = await database.searchFiles(query: appState.searchQuery)
            } else {
                // 使用结构化查询
                searchResults = await database.searchFilesWithFilters(parsed: parsed)
            }
            semanticResults = []
        }
        
        isSearching = false
    }
    
    private func similarityColor(_ similarity: Double) -> Color {
        if similarity >= 0.7 { return .green }
        if similarity >= 0.5 { return .orange }
        return .secondary
    }
}
