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
    
    // Reader State - using item binding for reliability
    @State private var fileForReader: ManagedFile?
    
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
                CategoryHeaderView(category: category, subcategory: selectedSubcategory, browsingPath: browsingPath)
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
                    },
                    onOpenReader: {
                        fileForReader = file
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
        .onChange(of: appState.navigationTarget) { _, target in
            guard let target = target, target.category == category else { return }
            
            Task {
                // 1. Set Subcategory
                // If subcategory is explicitly provided, use it.
                // Otherwise, try to infer from file if present.
                var newSub = target.subcategory
                if newSub == nil, let file = target.file {
                     newSub = file.subcategory
                }
                
                selectedSubcategory = newSub
                
                // 2. Set Browsing Path
                // If we have a file, we need to calculate the path relative to Category/Subcategory
                if let file = target.file {
                    // Try to deduce folders from file path
                    // Path: /Root/Category/Subcategory/FolderA/FolderB/File.ext
                    // We want browsingPath = ["FolderA", "FolderB"]
                    
                    let rootURL = fileManager.getCategoryURL(for: category)
                    var baseURL = rootURL
                    if let sub = newSub {
                        baseURL = baseURL.appendingPathComponent(sub)
                    }
                    
                    let filePath = file.newPath
                    if filePath.hasPrefix(baseURL.path) {
                        let relativePath = String(filePath.dropFirst(baseURL.path.count))
                        // Remove leading slash if present
                        let cleanRelative = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                        
                        let components = cleanRelative.components(separatedBy: "/")
                        // Drop the last component (filename)
                        if components.count > 1 {
                             browsingPath = Array(components.dropLast())
                        } else {
                             browsingPath = []
                        }
                    } else {
                        // Fallback: file might be in different location or flat structure
                        browsingPath = []
                    }
                    
                    // 3. Highlight/Select file
                    await loadData() // Reload to fetch files at new path
                    
                    // Wait for reload then select
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    selectedFile = file
                    // Scroll to file? (Requires ScrollViewProxy, maybe later)
                } else {
                    // Just navigating to folder root
                    browsingPath = []
                    await loadData()
                }
                
                // Clear the target after handling so it doesn't re-trigger
                // But we actally want it to persist until next action? 
                // No, we should probably clear it in AppState or just let it be.
                // If we set it to nil, it triggers onChange again (nil), which guards out.
                // MainActor.run { appState.navigationTarget = nil } 
                // Actually safer to leave it or clear it. If we clear it, ContentView updates?
                // ContentView only reacts to .category, doesn't unset.
            }
        }
        .background {
           fileOperationsOverlay(content: Color.clear)
        }
        .sheet(item: $fileForReader) { file in
            UniversalReaderView(file: file)
                .frame(minWidth: 900, minHeight: 700)
        }
    }
    

    
    // View Mode State
    @State private var viewMode: FileViewMode = .list

    private var sortingToolbarView: some View {
        HStack(spacing: 12) {
            // View Mode Toggle
            Picker("View Mode", selection: $viewMode) {
                ForEach(FileViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .labelsHidden()
            
            Divider().frame(height: 16)
            
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
                    .background(sortOption == option ? Color.blue.opacity(0.1) : Color.clear)
                    .foregroundStyle(sortOption == option ? .blue : .secondary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Breadcrumbs (Right aligned)
            if !browsingPath.isEmpty || selectedSubcategory != nil {
                HStack(spacing: 2) {
                    // Home / Category Root
                    Button {
                        browsingPath = []
                        selectedSubcategory = nil
                        Task { await loadData() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(category.color)
                            Text(category.displayName)
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    // Subcategory
                    if let sub = selectedSubcategory {
                        Text(">")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        Button {
                            browsingPath = []
                            Task { await loadData() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.cyan)
                                Text(sub)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Nested folder path
                    ForEach(Array(browsingPath.enumerated()), id: \.offset) { index, folder in
                        Text(">")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        Button {
                            browsingPath = Array(browsingPath.prefix(index + 1))
                            Task { await loadData() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.cyan)
                                Text(folder)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 12)
            }
            
            Text("\(childFolders.count) 个文件夹, \(filteredFiles.count) 个文件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background {
            if appState.useBingWallpaper {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            }
        }
    }
    
    private var fileListWithFoldersView: some View {
        ScrollView {
            if viewMode == .list {
                LazyVStack(spacing: 8) {
                    folderListContent
                    fileListContent
                }
                .padding(24)
                .padding(.bottom, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 16)], spacing: 16) {
                    folderGridContent
                    fileGridContent
                }
                .padding(24)
                .padding(.bottom, 60)
            }
        }
    }
    
    // Extracted content for reuse and clarity
    @ViewBuilder
    private var folderListContent: some View {
        // Debug: Show if no folders found
        if childFolders.isEmpty && !isLoading && viewMode == .list {
            // Only show empty folder hint in list mode or handled generally? 
            // Actually let's hide it to be cleaner, or show only if total empty
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
                    TapGesture(count: 1).onEnded { } // Eat single taps to prevent other gestures
                )
        }
    }
    
    @ViewBuilder
    private var fileListContent: some View {
        // When browsing into nested folders, show filesystem files
        if !browsingPath.isEmpty {
            ForEach(filesAtPath, id: \.absoluteString) { fileURL in
                FilesystemFileRow(url: fileURL)
                    .onTapGesture {
                        NSWorkspace.shared.open(fileURL)
                    }
            }
        } else {
            // At root or subcategory level, show database files
            ForEach(filteredFiles) { file in
                FileListRow(file: file, isSelected: selectedFile?.id == file.id)
                    .onTapGesture(count: 2) {
                        fileForReader = file
                    }
                    .onTapGesture {
                        selectedFile = file
                    }
                    .contextMenu {
                        fileContextMenu(for: file)
                    }
            }
        }
    }
    
    @ViewBuilder
    private var folderGridContent: some View {
        ForEach(childFolders, id: \.self) { folderName in
            GridFolderItem(name: folderName)
                .onTapGesture(count: 2) {
                    browsingPath.append(folderName)
                    Task { await loadData() }
                }
        }
    }
    
    @ViewBuilder
    private var fileGridContent: some View {
         if !browsingPath.isEmpty {
             ForEach(filesAtPath, id: \.absoluteString) { fileURL in
                 // Need a transient ManagedFile wrapper or a specific GridFilesystemItem?
                 // For now, let's use a simplified grid item or existing one if we can map it.
                 // Since GridFileItem takes ManagedFile, we might needs a generic one or separate.
                 // Let's use a quick view here since FilesystemFileRow is for list.
                 
                 VStack {
                     RichFileIcon(path: fileURL.path)
                         .frame(width: 64, height: 64)
                     Text(fileURL.lastPathComponent)
                         .font(.caption)
                         .lineLimit(2)
                 }
                 .frame(width: 100, height: 120)
                 .onTapGesture(count: 2) {
                     NSWorkspace.shared.open(fileURL)
                 }
             }
         } else {
             ForEach(filteredFiles) { file in
                 GridFileItem(file: file, isSelected: selectedFile?.id == file.id)
                     .onTapGesture(count: 2) {
                         fileForReader = file
                     }
                     .onTapGesture {
                         selectedFile = file
                     }
                     .contextMenu {
                         fileContextMenu(for: file)
                     }
             }
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
    var subcategory: String? = nil
    var browsingPath: [String] = []
    
    private var currentFolderURL: URL {
        var url = FileFlowManager.shared.getCategoryURL(for: category)
        if let sub = subcategory {
            url = url.appendingPathComponent(sub)
        }
        for folder in browsingPath {
            url = url.appendingPathComponent(folder)
        }
        return url
    }
    
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
                FileFlowManager.shared.revealInFinder(url: currentFolderURL)
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
        HStack(spacing: 12) {
            // Folder icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.regular)
                    .foregroundStyle(.primary)
                
                // Optional subtitle if needed, or remove for compactness
            }
            
            Spacer()
            
            // Double-click hint
            if isHovering {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                    Text("双击打开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Filesystem File Row
struct FilesystemFileRow: View {
    let url: URL
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // File icon
            RichFileIcon(path: url.path)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            HStack(spacing: 8) {
                Text(url.lastPathComponent)
                    .font(.body)
                    .fontWeight(.regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 120, alignment: .leading)
                
                Text(fileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(fileExtension)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
            
            Spacer()
            
            if isHovering {
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中显示")
                    
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("打开")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var fileSize: String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    private var fileExtension: String {
        return url.pathExtension.uppercased()
    }
}

