//
//  CategoryView.swift
//  FileFlow
//
//  分类浏览视图
//

import SwiftUI

struct CategoryView: View {
    @EnvironmentObject var appState: AppState
    let category: PARACategory
    @State private var files: [ManagedFile] = []
    @State private var subcategories: [String] = []
    @State private var selectedSubcategory: String?
    @State private var isLoading = true
    
    private let fileManager = FileFlowManager.shared
    private let database = DatabaseManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: category.icon)
                            .font(.title)
                            .foregroundStyle(category.color)
                        Text(category.displayName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Text(category.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    fileManager.revealInFinder(url: fileManager.getCategoryURL(for: category))
                } label: {
                    Label("在 Finder 中打开", systemImage: "folder")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(24)
            .padding(.top, 16)
            
            // Subcategory Tabs
            if !subcategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SubcategoryTab(
                            name: "全部",
                            isSelected: selectedSubcategory == nil
                        ) {
                            selectedSubcategory = nil
                        }
                        
                        ForEach(subcategories, id: \.self) { subcategory in
                            SubcategoryTab(
                                name: subcategory,
                                isSelected: selectedSubcategory == subcategory
                            ) {
                                selectedSubcategory = subcategory
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 8)
            }
            
            // File List
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if files.isEmpty {
                ContentUnavailableView(
                    "暂无文件",
                    systemImage: "folder.badge.questionmark",
                    description: Text("此分类下还没有整理过的文件")
                )
                .glass(cornerRadius: 16)
                .padding(24)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFiles) { file in
                            FileListRow(file: file)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: category) { _, _ in
            Task {
                await loadData()
            }
        }
        .onChange(of: appState.lastUpdateID) { _, _ in
            Task {
                await loadData()
            }
        }
    }
    
    private var filteredFiles: [ManagedFile] {
        if let subcategory = selectedSubcategory {
            return files.filter { file in
                guard let fileSub = file.subcategory else { return false }
                // Handle potential whitespace or normalization differences
                return fileSub.localizedStandardCompare(subcategory) == .orderedSame ||
                       fileSub.trimmingCharacters(in: .whitespacesAndNewlines) == subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return files
    }
    
    private func loadData() async {
        isLoading = true
        subcategories = fileManager.getSubcategories(for: category)
        files = await database.getFilesForCategory(category)
        isLoading = false
    }
}

// MARK: - Subcategory Tab
struct SubcategoryTab: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.8))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    }
                }
                .foregroundStyle(isSelected ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - File List Row
struct FileListRow: View {
    let file: ManagedFile
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            RichFileIcon(path: file.newPath)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.newName.isEmpty ? file.originalName : file.newName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .allowsTightening(true)
                
                HStack(spacing: 8) {
                    if let subcategory = file.subcategory {
                        Label(subcategory, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(file.tags.prefix(3)) { tag in
                        Text("#\(tag.name)")
                            .font(.caption)
                            .foregroundStyle(tag.swiftUIColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tag.swiftUIColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Text(file.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Date
            VStack(alignment: .trailing, spacing: 2) {
                Text(file.importedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.importedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // Actions
            if isHovering {
                Button {
                    FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
                } label: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(12)
        .glass(cornerRadius: 16, material: .ultraThin, shadowRadius: isHovering ? 4 : 0)
        .scaleEffect(isHovering ? 1.005 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Tag Files View
struct TagFilesView: View {
    let tag: Tag
    @State private var files: [ManagedFile] = []
    @State private var isLoading = true
    
    private let database = DatabaseManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Circle()
                        .fill(tag.swiftUIColor)
                        .frame(width: 24, height: 24)
                        .shadow(color: tag.swiftUIColor.opacity(0.3), radius: 8)
                    
                    Text("#\(tag.name)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }
                
                Spacer()
                
                Text("\(files.count) 个文件")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glass()
            }
            .padding(24)
            .padding(.top, 16)
            
            // File List
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if files.isEmpty {
                ContentUnavailableView(
                    "暂无文件",
                    systemImage: "tag.slash",
                    description: Text("没有使用此标签的文件")
                )
                .glass(cornerRadius: 16)
                .padding(24)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(files) { file in
                            FileListRow(file: file)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .task(id: tag.id) {
            await loadFiles()
        }
    }
    
    private func loadFiles() async {
        isLoading = true
        files = await database.getFilesWithTag(tag)
        isLoading = false
    }
}

// MARK: - Search View
struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchResults: [ManagedFile] = []
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    
    private let database = DatabaseManager.shared
    
    var body: some View {
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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .glass(cornerRadius: 16, material: .regular)
            .padding(24)
            .padding(.top, 16)
            
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("找到 \(searchResults.count) 个结果")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(searchResults) { file in
                                FileListRow(file: file)
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .onAppear {
            isSearchFieldFocused = true
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
