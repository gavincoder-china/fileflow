//
//  CategoryView.swift
//  FileFlow
//
//  Created by Auto-Agent
//

import SwiftUI

struct CategoryView: View {
    @EnvironmentObject var appState: AppState
    let category: PARACategory
    @State private var files: [ManagedFile] = []
    @State private var subcategories: [String] = []
    @State private var selectedSubcategory: String?
    @State private var isLoading = true
    
    // Folder Navigation State
    @State private var browsingPath: [String] = []  // Stack of folder names from subcategory root
    @State private var childFolders: [String] = []  // Subfolders at current browsing location
    @State private var filesAtPath: [URL] = []      // Files at current browsing location (from filesystem)
    
    // Eagle Layout State
    @State private var selectedFile: ManagedFile?
    @State private var folderSearchText: String = ""
    
    // Sorting State
    @State private var sortOption: FileSortOption = .date
    @State private var sortAscending: Bool = false
    
    // File Operations State
    @State private var showingRenameSubcategory = false
    @State private var showingDeleteSubcategory = false
    @State private var showingMergeSubcategory = false
    
    @State private var subcategoryToEdit: String?
    @State private var pendingRenameName = ""
    @State private var selectedMergeTarget: String = ""
    
    @State private var fileToRename: ManagedFile?
    @State private var fileToDelete: ManagedFile?
    @State private var fileToMove: ManagedFile?
    @State private var pendingFileName = ""
    @State private var showingMoveFileSheet = false
    
    @State private var moveTargetCategory: PARACategory = .resources
    @State private var moveTargetSubcategory: String = ""
    
    private let fileManager = FileFlowManager.shared
    private let database = DatabaseManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Pane: Folder Sidebar
            CategoryFolderSidebar(
                category: category,
                subcategories: subcategories,
                selectedSubcategory: $selectedSubcategory,
                searchText: $folderSearchText,
                onRename: { name in
                    subcategoryToEdit = name
                    pendingRenameName = name
                    showingRenameSubcategory = true
                },
                onDelete: { name in
                    subcategoryToEdit = name
                    showingDeleteSubcategory = true
                },
                onMerge: { name in
                    subcategoryToEdit = name
                    selectedMergeTarget = subcategories.first(where: { $0 != name }) ?? ""
                    showingMergeSubcategory = true
                },
                onFileDrop: { file, targetSubcategory in
                    Task {
                        try? await FileFlowManager.shared.moveFile(file, to: category, subcategory: targetSubcategory)
                        await loadData()
                    }
                }
            )
            .frame(width: 260)
            
            Divider()
            
            // MARK: - Middle Pane: File Content
            VStack(spacing: 0) {
                CategoryHeaderView(category: category)
                breadcrumbNavigationView
                sortingToolbarView
                fileListWithFoldersView
            }
            .frame(maxWidth: .infinity)
            
            // MARK: - Right Pane: Inspector
            if let file = selectedFile {
                Divider()
                
                FileInspectorPane(
                    file: file,
                    onClose: {
                        withAnimation {
                            selectedFile = nil
                        }
                    },
                    onUpdateTags: { tags in
                        Task {
                            await FileFlowManager.shared.updateFileTags(for: file, tags: tags)
                            await loadData()
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadData()
        }
        .onChange(of: category) { _, _ in
            Task {
                await loadData()
                selectedSubcategory = nil 
                selectedFile = nil
                browsingPath = []
            }
        }
        .onChange(of: selectedSubcategory) { _, _ in
            // Reset browsing path and reload when sidebar selection changes
            Task {
                browsingPath = []
                await loadData()
                selectedFile = nil
            }
        }
        .onChange(of: appState.lastUpdateID) { _, _ in
            Task {
                await loadData()
            }
        }
        // Apply Overlay for Alerts logic
        .background {
           fileOperationsOverlay(content: Color.clear)
        }
    }
    
    // MARK: - Extracted Views
    
    @ViewBuilder
    private var breadcrumbNavigationView: some View {
        if !browsingPath.isEmpty || selectedSubcategory != nil {
            HStack(spacing: 4) {
                Button {
                    browsingPath = []
                    selectedSubcategory = nil
                    Task { await loadData() }
                } label: {
                    Text(category.displayName)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                
                if let sub = selectedSubcategory {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        browsingPath = []
                        Task { await loadData() }
                    } label: {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(browsingPath.isEmpty ? Color.primary : Color.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                ForEach(Array(browsingPath.enumerated()), id: \.offset) { index, folder in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        browsingPath = Array(browsingPath.prefix(index + 1))
                        Task { await loadData() }
                    } label: {
                        Text(folder)
                            .font(.caption)
                            .foregroundStyle(index == browsingPath.count - 1 ? Color.primary : Color.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
        }
    }
    
    private var sortingToolbarView: some View {
        HStack(spacing: 12) {
            ForEach(FileSortOption.allCases, id: \.self) { option in
                Button {
                    if sortOption == option {
                        sortAscending.toggle()
                    } else {
                        sortOption = option
                        sortAscending = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.icon)
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(sortOption == option ? Color.blue.opacity(0.2) : Color.clear)
                    .foregroundStyle(sortOption == option ? .blue : .secondary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Text("\(childFolders.count) 个文件夹, \(filteredFiles.count) 个文件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
    
    private var fileListWithFoldersView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Debug: Show if no folders found
                if childFolders.isEmpty && !isLoading {
                    Text("当前目录无子文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                
                ForEach(childFolders, id: \.self) { folderName in
                    FolderNavigationRow(name: folderName)
                        .gesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    browsingPath.append(folderName)
                                    Task { await loadData() }
                                }
                        )
                        .gesture(
                            TapGesture(count: 1)
                                .onEnded {
                                    // Single tap: just visual feedback
                                    Logger.debug("Folder tapped: \(folderName)")
                                }
                        )
                }
                
                // When browsing into nested folders, show filesystem files
                if !browsingPath.isEmpty {
                    ForEach(filesAtPath, id: \.absoluteString) { fileURL in
                        FilesystemFileRow(url: fileURL)
                            .onTapGesture {
                                // Could open file with default app
                                NSWorkspace.shared.open(fileURL)
                            }
                    }
                } else {
                    // At root or subcategory level, show database files
                    ForEach(filteredFiles) { file in
                        FileListRow(file: file, isSelected: selectedFile?.id == file.id)
                            .onTapGesture {
                                selectedFile = file
                            }
                            .contextMenu {
                                fileContextMenu(for: file)
                            }
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 60)
        }
    }
    
    private var filteredFiles: [ManagedFile] {
        var result: [ManagedFile]
        
        // 1. Filter by subcategory
        if let subcategory = selectedSubcategory {
            result = files.filter { file in
                guard let fileSub = file.subcategory else { return false }
                return fileSub.localizedStandardCompare(subcategory) == .orderedSame ||
                       fileSub.trimmingCharacters(in: .whitespacesAndNewlines) == subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            result = files
        }
        
        // 1.5 Exclude items that are actually directories (not files)
        result = result.filter { file in
            var isDir: ObjCBool = false
            let exists = Foundation.FileManager.default.fileExists(atPath: file.newPath, isDirectory: &isDir)
            // Keep only actual files, not directories
            return exists && !isDir.boolValue
        }
        
        // 1.6 Exclude items that match folder names (already shown as folders)
        let folderNames = Set(childFolders)
        result = result.filter { file in
            let fileName = (file.newPath as NSString).lastPathComponent
            let baseName = (fileName as NSString).deletingPathExtension
            // Don't show if filename matches a child folder name
            return !folderNames.contains(fileName) && !folderNames.contains(baseName)
        }
        
        // 2. Filter by search text (file name, subcategory, tags)
        if !folderSearchText.isEmpty {
            let query = folderSearchText.lowercased()
            result = result.filter { file in
                // Match file name
                let nameMatch = file.displayName.lowercased().contains(query)
                // Match subcategory
                let subcategoryMatch = file.subcategory?.lowercased().contains(query) ?? false
                // Match any tag name
                let tagMatch = file.tags.contains { $0.name.lowercased().contains(query) }
                // Match file type/extension
                let typeMatch = file.fileExtension.lowercased().contains(query)
                // Match summary if available
                let summaryMatch = file.summary?.lowercased().contains(query) ?? false
                
                return nameMatch || subcategoryMatch || tagMatch || typeMatch || summaryMatch
            }
        }
        
        // 3. Apply sorting
        result.sort { a, b in
            let comparison: Bool
            switch sortOption {
            case .date:
                comparison = a.importedAt > b.importedAt
            case .name:
                comparison = a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            case .type:
                comparison = a.fileExtension.localizedStandardCompare(b.fileExtension) == .orderedAscending
            case .size:
                comparison = a.fileSize > b.fileSize
            }
            return sortAscending ? !comparison : comparison
        }
        
        return result
    }
    
    // Extracted view modifier logic reused
    @ViewBuilder
    private func fileOperationsOverlay<Content: View>(content: Content) -> some View {
        content
            // Subcategory Sheets
            .alert("重命名子文件夹", isPresented: $showingRenameSubcategory) {
                TextField("新名称", text: $pendingRenameName)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let oldName = subcategoryToEdit, !pendingRenameName.isEmpty {
                        Task {
                            try? FileFlowManager.shared.renameSubcategoryFolder(category: category, oldName: oldName, newName: pendingRenameName)
                            await loadData()
                            if selectedSubcategory == oldName {
                                selectedSubcategory = pendingRenameName
                            }
                        }
                    }
                }
            }
            .alert("删除子文件夹", isPresented: $showingDeleteSubcategory) {
                Button("取消", role: .cancel) { }
                Button("删除并保留文件", role: .destructive) {
                    if let name = subcategoryToEdit {
                        Task {
                            try? FileFlowManager.shared.deleteSubcategoryFolder(category: category, subcategory: name)
                            await loadData()
                            if selectedSubcategory == name {
                                selectedSubcategory = nil
                            }
                        }
                    }
                }
            } message: {
                Text("删除文件夹不会删除里面的文件，它们会被移动到分类根目录。")
            }
            .sheet(isPresented: $showingMergeSubcategory) {
                if let source = subcategoryToEdit {
                    MergeSubcategorySheet(
                        category: category,
                        sourceSubcategory: source,
                        isPresented: $showingMergeSubcategory,
                        onMerge: { target in
                            Task {
                                try? await FileFlowManager.shared.mergeSubcategoryFolders(category: category, from: source, to: target)
                                await loadData()
                                if selectedSubcategory == source {
                                    selectedSubcategory = target
                                }
                            }
                        }
                    )
                }
            }
            // File Alerts
            .alert("重命名文件", isPresented: Binding(
                get: { fileToRename != nil },
                set: { if !$0 { fileToRename = nil } }
            )) {
                TextField("新名称", text: $pendingFileName)
                Button("取消", role: .cancel) { fileToRename = nil }
                Button("确定") {
                    if let file = fileToRename, !pendingFileName.isEmpty {
                        Task {
                            let ext = (file.newName as NSString).pathExtension
                            var finalName = pendingFileName
                            if !finalName.hasSuffix("." + ext) && !ext.isEmpty {
                                finalName += "." + ext
                            }
                            
                            try? _ = FileFlowManager.shared.moveAndRenameFile(
                                from: URL(fileURLWithPath: file.newPath),
                                to: file.category,
                                subcategory: file.subcategory,
                                newName: finalName,
                                tags: file.tags
                            )
                            
                            var updatedFile = file
                            updatedFile.newName = finalName
                            let newPath = (file.newPath as NSString).deletingLastPathComponent.appending("/" + finalName)
                            updatedFile.newPath = newPath
                            await DatabaseManager.shared.saveFile(updatedFile, tags: file.tags)
                            
                            await loadData()
                            fileToRename = nil
                        }
                    }
                }
            }
            .alert("删除文件", isPresented: Binding(
                get: { fileToDelete != nil },
                set: { if !$0 { fileToDelete = nil } }
            )) {
                Button("取消", role: .cancel) { fileToDelete = nil }
                Button("删除", role: .destructive) {
                    if let file = fileToDelete {
                        Task {
                            try? FileManager.default.trashItem(at: URL(fileURLWithPath: file.newPath), resultingItemURL: nil)
                            await DatabaseManager.shared.deleteFile(file.id)
                            await loadData()
                            fileToDelete = nil
                            if selectedFile?.id == file.id {
                                selectedFile = nil
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingMoveFileSheet) {
                if let file = fileToMove {
                    MoveFileSheet(
                        file: file,
                        isPresented: $showingMoveFileSheet,
                        onMove: { targetCat, targetSub in
                            Task {
                                try? await FileFlowManager.shared.moveFile(file, to: targetCat, subcategory: targetSub)
                                await loadData()
                            }
                        }
                    )
                }
            }
    }
    
    private func loadData() async {
        isLoading = true
        subcategories = fileManager.getSubcategories(for: category)
        files = await database.getFilesForCategory(category)
        
        // Scan filesystem for child folders and files at current browsing location
        childFolders = await scanChildFolders()
        filesAtPath = await scanFilesAtPath()
        
        isLoading = false
    }
    
    private func scanChildFolders() async -> [String] {
        let categoryURL = fileManager.getCategoryURL(for: category)
        var currentURL = categoryURL
        
        // Navigate to subcategory if selected
        if let sub = selectedSubcategory {
            currentURL = currentURL.appendingPathComponent(sub)
        }
        
        // Navigate through browsing path
        for folder in browsingPath {
            currentURL = currentURL.appendingPathComponent(folder)
        }
        
        Logger.debug("Scanning for folders at: \(currentURL.path)")
        
        // Scan for subfolders
        do {
            let contents = try Foundation.FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            let folders = contents.compactMap { url -> String? in
                var isDir: ObjCBool = false
                if Foundation.FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                   isDir.boolValue {
                    return url.lastPathComponent
                }
                return nil
            }.sorted()
            
            Logger.debug("Found \(folders.count) folders: \(folders)")
            return folders
        } catch {
            Logger.error("Failed to scan folders: \(error)")
            return []
        }
    }
    
    private func scanFilesAtPath() async -> [URL] {
        let categoryURL = fileManager.getCategoryURL(for: category)
        var currentURL = categoryURL
        
        // Navigate to subcategory if selected
        if let sub = selectedSubcategory {
            currentURL = currentURL.appendingPathComponent(sub)
        }
        
        // Navigate through browsing path
        for folder in browsingPath {
            currentURL = currentURL.appendingPathComponent(folder)
        }
        
        // Scan for files (not directories)
        do {
            let contents = try Foundation.FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            let files = contents.filter { url -> Bool in
                var isDir: ObjCBool = false
                if Foundation.FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    return !isDir.boolValue // Keep only files, not directories
                }
                return false
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            Logger.debug("Found \(files.count) files at path")
            return files
        } catch {
            Logger.error("Failed to scan files: \(error)")
            return []
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for file: ManagedFile) -> some View {
        Button {
            FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
        } label: {
            Label("在 Finder 中显示", systemImage: "folder")
        }
        
        Button {
            fileToRename = file
            pendingFileName = file.newName.isEmpty ? file.originalName : file.newName
        } label: {
            Label("重命名", systemImage: "pencil")
        }
        
        Button {
            Task {
                try? await FileFlowManager.shared.duplicateFile(file)
                await loadData()
            }
        } label: {
            Label("创建副本", systemImage: "doc.on.doc")
        }
        
        Button {
            fileToMove = file
            moveTargetCategory = file.category
            moveTargetSubcategory = ""
            showingMoveFileSheet = true
        } label: {
            Label("移动到...", systemImage: "arrow.right.square")
        }
        
        Divider()
        
        Button(role: .destructive) {
            fileToDelete = file
        } label: {
            Label("移到废纸篓", systemImage: "trash")
        }
    }
}

// Retain Header
struct CategoryHeaderView: View {
    let category: PARACategory
    
    var body: some View {
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
                FileFlowManager.shared.revealInFinder(url: FileFlowManager.shared.getCategoryURL(for: category))
            } label: {
                Label("在 Finder 中打开", systemImage: "folder")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(24)
        .padding(.top, 16)
    }
}

// MARK: - File Sort Option
enum FileSortOption: String, CaseIterable {
    case date = "时间"
    case name = "文件名"
    case type = "类型"
    case size = "大小"
    
    var icon: String {
        switch self {
        case .date: return "calendar"
        case .name: return "textformat"
        case .type: return "doc"
        case .size: return "square.resize"
        }
    }
}

// MARK: - Folder Navigation Row
struct FolderNavigationRow: View {
    let name: String
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Folder icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text("文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Double-click hint
            if isHovering {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                    Text("双击打开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovering ? Color.blue.opacity(0.08) : Color.clear)
        )
        .glass(cornerRadius: 16, material: .ultraThin, shadowRadius: isHovering ? 4 : 0)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHovering ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Filesystem File Row
struct FilesystemFileRow: View {
    let url: URL
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // File icon
            RichFileIcon(path: url.path)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(fileExtension)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            if isHovering {
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .glass(cornerRadius: 16, material: .ultraThin, shadowRadius: isHovering ? 4 : 0)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(Rectangle())
    }
    
    private var fileSize: String {
        do {
            let attrs = try Foundation.FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {}
        return ""
    }
    
    private var fileExtension: String {
        url.pathExtension.uppercased()
    }
}
