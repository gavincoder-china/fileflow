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
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    
    // For Eagle-style layout reuse
    @State private var selectedFile: ManagedFile?
    
    private let database = DatabaseManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Search Content
            VStack(spacing: 0) {
                // Search Field
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    
                    TextField("搜索文件、标签、备注...", text: $appState.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            Task {
                                await performSearch()
                            }
                        }
                    
                    if !appState.searchQuery.isEmpty {
                        Button {
                            appState.searchQuery = ""
                            searchResults = []
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
                    ProgressView("搜索中...")
                    Spacer()
                } else if appState.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "搜索文件",
                        systemImage: "magnifyingglass",
                        description: Text("输入关键词搜索文件名、标签或备注")
                    )
                    .opacity(0.6)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "无结果",
                        systemImage: "doc.questionmark",
                        description: Text("未找到匹配「\(appState.searchQuery)」的文件")
                    )
                    .opacity(0.6)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("找到 \(searchResults.count) 个结果")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                        
                        // Reuse CategoryFileListView for consistent looking results
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
                            onDelete: { _ in }
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
                            await performSearch() // Refresh results to show new tags? Optional.
                        }
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
                Task {
                    await performSearch()
                }
            } else {
                searchResults = []
            }
        }
    }
    
    private func performSearch() async {
        guard !appState.searchQuery.isEmpty else { return }
        
        isSearching = true
        searchResults = await database.searchFiles(query: appState.searchQuery)
        isSearching = false
    }
}
