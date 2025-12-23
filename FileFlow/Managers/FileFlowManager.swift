//
//  FileFlowManager.swift
//  FileFlow
//
//  文件操作管理器 - 负责文件移动、重命名和 PARA 文件夹管理
//  
//  设计理念：
//  1. 以文件系统为根基（类似 Obsidian Vault）
//  2. 文件是移动而非复制，只保留一份
//  3. SQLite 仅作为索引和元数据辅助
//

import Foundation
import AppKit
import Combine

class FileFlowManager {
    static let shared = FileFlowManager()
    
    private let fileManager = FileManager.default
    
    // MARK: - Root Directory (Vault)
    
    /// 用户选择的根目录路径，存储在 UserDefaults
    private let rootPathKey = "FileFlowRootPath"
    
    /// 根目录 URL
    var rootURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: rootPathKey) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.path, forKey: rootPathKey)
                // 设置根目录后，创建 PARA 文件夹结构
                setupPARAFolders()
            } else {
                UserDefaults.standard.removeObject(forKey: rootPathKey)
            }
        }
    }
    
    /// 是否已配置根目录
    var isRootConfigured: Bool {
        guard let url = rootURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// 兼容旧接口，返回根目录（如果未设置则返回默认路径）
    var baseURL: URL {
        if let url = rootURL {
            return url
        }
        // 默认路径（仅用于首次启动前的兼容）
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("FileFlow")
    }
    
    private init() {
        // 如果已配置根目录，确保 PARA 结构存在
        if isRootConfigured {
            setupPARAFolders()
        }
    }
    
    // MARK: - Root Directory Selection
    
    /// 让用户选择根目录
    func selectRootDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 FileFlow 根目录"
        panel.message = "选择一个文件夹作为 FileFlow 的数据存储位置。所有整理的文件都将移动到此目录中。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            return url
        }
        return nil
    }
    
    // MARK: - PARA Folder Setup
    
    func setupPARAFolders() {
        guard let root = rootURL else { return }
        
        // Create PARA category folders
        for category in PARACategory.allCases {
            let categoryURL = root.appendingPathComponent(category.folderName)
            createDirectoryIfNeeded(at: categoryURL)
        }
        
        // Create .fileflow folder for database and metadata
        let metadataFolder = root.appendingPathComponent(".fileflow")
        createDirectoryIfNeeded(at: metadataFolder)
    }
    
    func createDirectoryIfNeeded(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating directory: \(error)")
            }
        }
    }
    
    // MARK: - Get Category Folder
    
    func getCategoryURL(for category: PARACategory) -> URL {
        return baseURL.appendingPathComponent(category.folderName)
    }
    
    func getSubcategoryURL(for category: PARACategory, subcategory: String) -> URL {
        let categoryURL = getCategoryURL(for: category)
        let subcategoryURL = categoryURL.appendingPathComponent(subcategory)
        createDirectoryIfNeeded(at: subcategoryURL)
        return subcategoryURL
    }
    
    // MARK: - List Subcategories
    
    func getSubcategories(for category: PARACategory) -> [String] {
        let categoryURL = getCategoryURL(for: category)
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: categoryURL, includingPropertiesForKeys: [.isDirectoryKey])
            return contents.compactMap { url -> String? in
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    // 排除隐藏文件夹
                    if !url.lastPathComponent.hasPrefix(".") {
                        return url.lastPathComponent
                    }
                }
                return nil
            }.sorted()
        } catch {
            print("Error listing subcategories: \(error)")
            return []
        }
    }
    
    // MARK: - Generate New File Name
    
    func generateNewFileName(for file: ManagedFile, tags: [Tag]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        // Get the file extension
        let ext = (file.originalName as NSString).pathExtension
        let baseName = (file.originalName as NSString).deletingPathExtension
        
        // Create a sanitized short name from original or summary
        var shortName = file.summary?.prefix(30).description ?? baseName
        shortName = sanitizeFileName(shortName)
        
        // Add tags to filename (max 3)
        let tagString = tags.prefix(3).map { "#\($0.name)" }.joined(separator: "_")
        
        // Construct the new name
        var newName = "\(dateString)_\(file.category.rawValue)_\(shortName)"
        if !tagString.isEmpty {
            newName += "_\(tagString)"
        }
        newName += ".\(ext)"
        
        return newName
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        // Remove invalid characters for file names
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "")
        
        // Replace spaces with underscores
        sanitized = sanitized.replacingOccurrences(of: " ", with: "_")
        
        // Limit length
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }
        
        return sanitized
    }
    
    // MARK: - Move and Rename File (核心：移动而非复制)
    
    /// 将文件移动到对应分类目录
    /// - Important: 这是移动操作，原文件会被删除，只保留目标位置的一份文件
    /// - Note: 包含事务回滚机制，失败时自动恢复原文件
    func moveAndRenameFile(
        from sourceURL: URL,
        to category: PARACategory,
        subcategory: String?,
        newName: String,
        tags: [Tag]
    ) throws -> URL {
        // 检查根目录是否已配置
        guard isRootConfigured else {
            throw FileFlowError.rootNotConfigured
        }
        
        // 1. Create backup in temp directory
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension)
        
        do {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
        } catch {
            throw FileFlowError.moveError("无法创建备份: \(error.localizedDescription)")
        }
        
        // 2. Determine destination folder
        var destinationFolder: URL
        if let subcategory = subcategory, !subcategory.isEmpty {
            destinationFolder = getSubcategoryURL(for: category, subcategory: subcategory)
        } else {
            destinationFolder = getCategoryURL(for: category)
        }
        
        // 3. Create destination URL and resolve conflicts
        var destinationURL = destinationFolder.appendingPathComponent(newName)
        destinationURL = resolveNameConflict(for: destinationURL)
        
        // 4. Attempt the move with rollback on failure
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            
            // 5. Apply Finder tags
            applyFinderTags(to: destinationURL, tags: tags)
            
            // 6. Success - clean up backup
            try? fileManager.removeItem(at: backupURL)
            
            return destinationURL
        } catch {
            // ROLLBACK: Restore from backup
            print("⚠️ Move failed, attempting rollback...")
            
            // Only restore if source was actually removed
            if !fileManager.fileExists(atPath: sourceURL.path) {
                do {
                    try fileManager.moveItem(at: backupURL, to: sourceURL)
                    print("✅ Rollback successful - file restored")
                } catch {
                    print("❌ CRITICAL: Rollback failed! Backup at: \(backupURL.path)")
                }
            } else {
                // Source still exists, just clean up backup
                try? fileManager.removeItem(at: backupURL)
            }
            
            throw FileFlowError.moveError("移动失败: \(error.localizedDescription)")
        }
    }

    
    /// 仅重命名/移动已在库内的文件
    func relocateFile(
        from currentURL: URL,
        to category: PARACategory,
        subcategory: String?,
        newName: String
    ) throws -> URL {
        guard isRootConfigured else {
            throw FileFlowError.rootNotConfigured
        }
        
        var destinationFolder: URL
        if let subcategory = subcategory, !subcategory.isEmpty {
            destinationFolder = getSubcategoryURL(for: category, subcategory: subcategory)
        } else {
            destinationFolder = getCategoryURL(for: category)
        }
        
        var destinationURL = destinationFolder.appendingPathComponent(newName)
        destinationURL = resolveNameConflict(for: destinationURL)
        
        try fileManager.moveItem(at: currentURL, to: destinationURL)
        
        return destinationURL
    }
    
    private func resolveNameConflict(for url: URL) -> URL {
        var resultURL = url
        var counter = 1
        let ext = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        let parentDir = url.deletingLastPathComponent()
        
        while fileManager.fileExists(atPath: resultURL.path) {
            let newName = "\(baseName)_\(counter).\(ext)"
            resultURL = parentDir.appendingPathComponent(newName)
            counter += 1
        }
        
        return resultURL
    }
    
    // MARK: - Check if file is inside root
    
    func isFileInsideRoot(_ url: URL) -> Bool {
        guard let root = rootURL else { return false }
        return url.path.hasPrefix(root.path)
    }
    
    // MARK: - Finder Tags
    
    func applyFinderTags(to url: URL, tags: [Tag]) {
        let tagNames = tags.map { $0.name }
        
        do {
            try (url as NSURL).setResourceValue(tagNames, forKey: .tagNamesKey)
        } catch {
            print("Error applying Finder tags: \(error)")
        }
    }
    
    func getFinderTags(from url: URL) -> [String] {
        do {
            var tags: AnyObject?
            try (url as NSURL).getResourceValue(&tags, forKey: .tagNamesKey)
            return tags as? [String] ?? []
        } catch {
            print("Error getting Finder tags: \(error)")
            return []
        }
    }
    
    // MARK: - File Info
    
    func getFileInfo(at url: URL) -> (size: Int64, type: String, created: Date, modified: Date)? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int64 ?? 0
            let type = attributes[.type] as? String ?? ""
            let created = attributes[.creationDate] as? Date ?? Date()
            let modified = attributes[.modificationDate] as? Date ?? Date()
            return (size, type, created, modified)
        } catch {
            print("Error getting file info: \(error)")
            return nil
        }
    }
    
    // MARK: - Create Subcategory
    
    func createSubcategory(name: String, in category: PARACategory) -> URL {
        let subcategoryURL = getSubcategoryURL(for: category, subcategory: name)
        createDirectoryIfNeeded(at: subcategoryURL)
        return subcategoryURL
    }
    
    // MARK: - Open in Finder
    
    func revealInFinder(url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    func openRootInFinder() {
        if let root = rootURL {
            NSWorkspace.shared.open(root)
        }
    }
    
    // MARK: - Scan Root Directory
    
    /// 扫描根目录中的所有文件（用于重建索引）
    func scanAllFiles() -> [URL] {
        guard let root = rootURL else { return [] }
        
        var files: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    files.append(fileURL)
                }
            } catch {
                continue
            }
        }
        
        return files
    }
    
    // MARK: - Incremental Scan
    private let lastScanDateKey = "FileFlowLastScanDate"
    
    /// 增量扫描：仅返回自上次扫描以来修改的文件
    func incrementalScan() -> [URL] {
        guard let root = rootURL else { return [] }
        
        let lastScan = UserDefaults.standard.object(forKey: lastScanDateKey) as? Date ?? .distantPast
        var modifiedFiles: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                if resourceValues.isRegularFile == true,
                   let modDate = resourceValues.contentModificationDate,
                   modDate > lastScan {
                    modifiedFiles.append(fileURL)
                }
            } catch {
                continue
            }
        }
        
        return modifiedFiles
    }
    
    /// 更新上次扫描时间戳
    func updateLastScanDate() {
        UserDefaults.standard.set(Date(), forKey: lastScanDateKey)
    }

    
    // MARK: - Get Statistics
    
    func getStatistics() -> (totalFiles: Int, totalSize: Int64, byCategory: [PARACategory: Int]) {
        var totalFiles = 0
        var totalSize: Int64 = 0
        var byCategory: [PARACategory: Int] = [:]
        
        for category in PARACategory.allCases {
            let categoryURL = getCategoryURL(for: category)
            var count = 0
            
            if let enumerator = fileManager.enumerator(
                at: categoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        if resourceValues.isRegularFile == true {
                            count += 1
                            totalFiles += 1
                            totalSize += Int64(resourceValues.fileSize ?? 0)
                        }
                    } catch {
                        continue
                    }
                }
            }
            
            byCategory[category] = count
        }
        
        return (totalFiles, totalSize, byCategory)
    }
    
    // MARK: - Database Rebuild
    func rebuildIndex() async throws -> Int {
        guard let root = rootURL else { throw FileFlowError.rootNotConfigured }
        
        let database = DatabaseManager.shared
        var count = 0
        
        // 1. Deep Clean: Truncate all tables to remove potentially corrupted data
        database.truncateAllTables()
        
        // 2. Scan all files
        let files = scanAllFiles()
        
        // 3. Iterate and process
        for fileURL in files {
            // Determine category from path
            let pathComponents = fileURL.pathComponents
            
            var category: PARACategory = .resources
            var subcategory: String?
            
            // Check if file is inside a PARA folder
            for para in PARACategory.allCases {
                if pathComponents.contains(para.folderName) {
                    category = para
                    
                    // Try to find subcategory
                    if let index = pathComponents.firstIndex(of: para.folderName),
                       index + 1 < pathComponents.count - 1 { // -1 to exclude filename
                        subcategory = pathComponents[index + 1]
                    }
                    break
                }
            }
            
            // Initialize New ManagedFile (Directly, since DB is empty)
            var file = ManagedFile(
                originalName: fileURL.lastPathComponent,
                originalPath: fileURL.path,
                category: category,
                subcategory: subcategory
            )
            file.newPath = fileURL.path
            file.newName = fileURL.lastPathComponent
            file.importedAt = Date()
            
            // Get latest file info
            if let info = getFileInfo(at: fileURL) {
                file.fileSize = info.size
                file.fileType = info.type
                file.createdAt = info.created
                file.modifiedAt = info.modified
            }
            
            // Parse tags from filename (if any)
            // Format: Date_Category_Summary_#Tag1#Tag2.ext
            let nameWithoutExt = fileURL.deletingPathExtension().lastPathComponent
            if let tagStartIndex = nameWithoutExt.firstIndex(of: "#") {
                let tagsPart = String(nameWithoutExt[tagStartIndex...])
                let tagNames = tagsPart.split(separator: "#").map { String($0) }
                
                var tags: [Tag] = []
                for tagName in tagNames {
                    // Check if tag exists or create new
                    // Ideally we should query DB but for bulk rebuild we can simplify
                    // saveTag acts as INSERT OR REPLACE/IGNORE usually
                    let tag = Tag(name: tagName, color: TagColors.random())
                    tags.append(tag)
                    await database.saveTag(tag)
                }
                // Append parsed tags to existing ones (avoiding duplicates is handled by logic/set if needed, but here simple append)
                // For now, let's just use the parsed tags as the current set for this operation
                // Note: This might overwrite manual tags if we are strictly binding. verify saveFile logic.
                // DatabaseManager.saveFile appends tags. It validates relationships.
                file.tags = tags
            }
            
            // Save to DB
            await database.saveFile(file, tags: file.tags)
            count += 1
        }
        
        return count
    }
}

// MARK: - Errors

enum FileFlowError: LocalizedError {
    case rootNotConfigured
    case fileNotFound
    case moveError(String)
    
    var errorDescription: String? {
        switch self {
        case .rootNotConfigured:
            return "请先选择 FileFlow 根目录"
        case .fileNotFound:
            return "文件不存在"
        case .moveError(let message):
            return "文件移动失败: \(message)"
        }
    }
}

// MARK: - Directory Monitor Service
class DirectoryMonitorService: ObservableObject {
    static let shared = DirectoryMonitorService()
    
    @Published var monitoredURL: URL?
    @Published var isMonitoring = false
    @Published var newFiles: [URL] = []
    
    private var monitorSource: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let monitoringQueue = DispatchQueue(label: "com.fileflow.directorymonitor", attributes: .concurrent)
    
    // 忽略的文件前缀
    private let ignoredPrefixes = [".", "~", "$"]
    // 忽略的文件扩展名
    private let ignoredExtensions = ["tmp", "crdownload", "download", "plist", "ds_store"]
    
    // 保存上次扫描的文件列表，用于对比新文件
    private var knownFiles: Set<String> = []
    
    private init() {}
    
    func startMonitoring(url: URL) {
        stopMonitoring()
        
        // 确保有安全访问权限
        guard url.startAccessingSecurityScopedResource() else {
            print("❌ 无法访问目录: \(url.path)")
            return
        }
        
        self.monitoredURL = url
        self.isMonitoring = true
        
        // 初始扫描
        updateKnownFiles(at: url)
        
        // 创建文件描述符
        descriptor = open(url.path, O_EVTONLY)
        if descriptor == -1 {
            print("❌无法打开目录描述符")
            url.stopAccessingSecurityScopedResource()
            return
        }
        
        // 创建 DispatchSource
        monitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .link],
            queue: monitoringQueue
        )
        
        monitorSource?.setEventHandler { [weak self] in
            guard let self = self, let monitoredURL = self.monitoredURL else { return }
            
            // 延迟一点时间，等待文件写入完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkForNewFiles(in: monitoredURL)
            }
        }
        
        monitorSource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.descriptor)
            self.descriptor = -1
            url.stopAccessingSecurityScopedResource()
        }
        
        monitorSource?.resume()
        print("✅ 开始监控目录: \(url.path)")
    }
    
    func stopMonitoring() {
        if let source = monitorSource {
            source.cancel()
            monitorSource = nil
        }
        
        if let url = monitoredURL {
            url.stopAccessingSecurityScopedResource()
        }
        
        monitoredURL = nil
        isMonitoring = false
        knownFiles.removeAll()
        print("🛑 停止监控")
    }
    
    private func updateKnownFiles(at url: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            knownFiles = Set(files.map { $0.lastPathComponent })
        } catch {
            print("更新已知文件列表失败: \(error)")
        }
    }
    
    private func checkForNewFiles(in url: URL) {
        do {
            let currentFiles = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            let currentFileNames = Set(currentFiles.map { $0.lastPathComponent })
            
            // 找出新增的文件
            let newFileNames = currentFileNames.subtracting(knownFiles)
            
            var addedURLs: [URL] = []
            
            for fileName in newFileNames {
                // 过滤
                if shouldIgnore(fileName: fileName) { continue }
                
                let fileURL = url.appendingPathComponent(fileName)
                addedURLs.append(fileURL)
                print("🆕 检测到新文件: \(fileName)")
            }
            
            // 更新已知列表
            knownFiles = currentFileNames
            
            // 发布通知
            if !addedURLs.isEmpty {
                DispatchQueue.main.async {
                    self.newFiles.append(contentsOf: addedURLs)
                }
            }
            
        } catch {
            print("检查新文件失败: \(error)")
        }
    }
    
    private func shouldIgnore(fileName: String) -> Bool {
        // 检查前缀
        for prefix in ignoredPrefixes {
            if fileName.hasPrefix(prefix) { return true }
        }
        
        // 检查扩展名
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ignoredExtensions.contains(ext) { return true }
        
        return false
    }
}

    // MARK: - Rule Integration
    
    /// Apply rules to a specific file
    func applyRules(to file: ManagedFile) async {
        // Reload file to get latest state/path
        guard let currentFile = await DatabaseManager.shared.getFile(byPath: file.newPath) else { return }
        
        let allRules = await DatabaseManager.shared.getAllRules()
        let matched = RuleEngine.shared.evaluate(file: currentFile, rules: allRules)
        
        if !matched.isEmpty {
            print("🤖 Applying \(matched.count) rules to \(currentFile.displayName)")
            await RuleEngine.shared.execute(rules: matched, on: currentFile)
        }
    }
    
    /// Simplified move wrapper for RuleEngine
    func moveFile(_ file: ManagedFile, to category: PARACategory, subcategory: String?) async throws {
        let sourceURL = URL(fileURLWithPath: file.newPath)
        // Keep current name and tags
        let tags = await DatabaseManager.shared.getTagsForFile(fileId: file.id)
        
        let _ = try moveAndRenameFile(from: sourceURL, to: category, subcategory: subcategory, newName: file.newName, tags: tags)
    }
    
    // MARK: - Tag Management
    
    /// Update tags for a file and propagate to related files
    func updateFileTags(for file: ManagedFile, tags: [Tag]) async {
        // 1. Update DB
        await DatabaseManager.shared.updateTags(fileId: file.id, tags: tags)
        
        // 2. Propagate
        await TagPropagationService.shared.propagateTags(from: file, tags: tags)
        
        // 3. Apply to Finder
        let url = URL(fileURLWithPath: file.newPath)
        applyFinderTags(to: url, tags: tags)
    }
}
