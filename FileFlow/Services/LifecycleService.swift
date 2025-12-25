//
//  LifecycleService.swift
//  FileFlow
//
//  文件生命周期管理服务
//  负责管理文件在 PARA 分类间的流转和生命周期状态追踪
//

import Foundation

/// 文件生命周期管理服务
/// 提供文件状态追踪、流转记录和清理建议等功能
actor LifecycleService {
    static let shared = LifecycleService()
    
    // MARK: - Performance Cache
    
    /// 缓存过期时间（秒）
    private let cacheTTL: TimeInterval = 60
    
    /// 统计数据缓存
    private var statsCache: [FileLifecycleStage: Int]?
    private var statsCacheTime: Date?
    
    /// 清理建议缓存
    private var suggestionsCache: [LifecycleCleanupSuggestion]?
    private var suggestionsCacheTime: Date?
    
    private init() {}
    
    // MARK: - File Transition
    
    /// 记录文件分类流转
    /// - Parameters:
    ///   - file: 被移动的文件
    ///   - from: 原分类
    ///   - to: 目标分类
    ///   - reason: 流转原因
    ///   - notes: 可选备注
    ///   - isAutomatic: 是否为自动触发
    func recordTransition(
        file: ManagedFile,
        from: PARACategory,
        to: PARACategory,
        fromSub: String? = nil,
        toSub: String? = nil,
        reason: TransitionReason,
        notes: String? = nil,
        isAutomatic: Bool = false
    ) async {
        let transition = FileTransition(
            fileId: file.id,
            fileName: file.displayName,
            from: from,
            to: to,
            fromSub: fromSub,
            toSub: toSub,
            reason: reason,
            notes: notes,
            isAutomatic: isAutomatic
        )
        
        await DatabaseManager.shared.saveTransition(transition)
        
        // Update lifecycle stage based on target category
        let newStage: FileLifecycleStage = to == .archives ? .archived : .active
        await DatabaseManager.shared.updateLifecycleStage(fileId: file.id, stage: newStage)
        
        Logger.success("Recorded transition: \(file.displayName) \(from.displayName) → \(to.displayName)")
    }
    
    /// 获取文件的流转历史
    func getTransitionHistory(for fileId: UUID) async -> [FileTransition] {
        await DatabaseManager.shared.getTransitions(forFileId: fileId)
    }
    
    /// 获取最近的流转记录
    func getRecentTransitions(limit: Int = 50) async -> [FileTransition] {
        await DatabaseManager.shared.getRecentTransitions(limit: limit)
    }
    
    /// 撤销流转操作 (将文件移回原位置)
    func undoTransition(_ transition: FileTransition) async -> Bool {
        // 获取文件当前状态
        guard let file = await DatabaseManager.shared.getFile(byId: transition.fileId) else {
            Logger.warning("撤销失败: 文件不存在")
            return false
        }
        
        // 检查文件当前是否在目标分类
        guard file.category == transition.toCategory else {
            Logger.warning("撤销失败: 文件已不在目标分类")
            return false
        }
        
        // 执行反向流转
        do {
            try await FileFlowManager.shared.moveFile(
                file,
                to: transition.fromCategory,
                subcategory: transition.fromSubcategory
            )
            
            // 记录撤销操作
            await recordTransition(
                file: file,
                from: transition.toCategory,
                to: transition.fromCategory,
                fromSub: transition.toSubcategory,
                toSub: transition.fromSubcategory,
                reason: .userManual,
                notes: "撤销操作: 恢复到 \(transition.fromCategory.displayName)",
                isAutomatic: false
            )
            
            Logger.success("✅ 撤销成功: \(file.displayName) 恢复到 \(transition.fromCategory.displayName)")
            return true
        } catch {
            Logger.error("撤销失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 获取可撤销的最近流转 (仅限近24小时内)
    func getUndoableTransitions() async -> [FileTransition] {
        let recent = await getRecentTransitions(limit: 20)
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return recent.filter { $0.triggeredAt > cutoff && $0.confirmedByUser }
    }
    // MARK: - Lifecycle Stage Management
    
    /// 刷新所有文件的生命周期状态
    /// 基于最后访问时间更新状态
    func refreshAllLifecycleStages() async {
        await DatabaseManager.shared.refreshAllLifecycleStages()
        // Invalidate cache after refresh
        invalidateCache()
    }
    
    /// 标记文件为已访问
    func markFileAccessed(_ fileId: UUID) async {
        await DatabaseManager.shared.updateLastAccessedAt(fileId: fileId)
    }
    
    /// 获取生命周期统计数据（带缓存）
    func getLifecycleStats() async -> [FileLifecycleStage: Int] {
        // Check cache validity
        if let cached = statsCache,
           let cacheTime = statsCacheTime,
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }
        
        // Fetch from database and cache
        let stats = await DatabaseManager.shared.getLifecycleStats()
        statsCache = stats
        statsCacheTime = Date()
        return stats
    }
    
    // MARK: - Cleanup Suggestions
    
    /// 获取需要清理的文件建议（带缓存）
    func getCleanupSuggestions() async -> [LifecycleCleanupSuggestion] {
        // Check cache validity
        if let cached = suggestionsCache,
           let cacheTime = suggestionsCacheTime,
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }
        
        // Get files that are dormant or stale
        let dormantFiles = await DatabaseManager.shared.getFiles(byLifecycleStage: .dormant)
        let staleFiles = await DatabaseManager.shared.getFiles(byLifecycleStage: .stale)
        
        var suggestions: [LifecycleCleanupSuggestion] = []
        
        for file in dormantFiles {
            suggestions.append(LifecycleCleanupSuggestion(file: file, lastAccessedAt: file.lastAccessedAt))
        }
        
        for file in staleFiles {
            suggestions.append(LifecycleCleanupSuggestion(file: file, lastAccessedAt: file.lastAccessedAt))
        }
        
        // Sort by days since access (most stale first)
        let sorted = suggestions.sorted { $0.daysSinceAccess > $1.daysSinceAccess }
        
        // Cache results
        suggestionsCache = sorted
        suggestionsCacheTime = Date()
        
        return sorted
    }
    
    /// 清除所有缓存
    func invalidateCache() {
        statsCache = nil
        statsCacheTime = nil
        suggestionsCache = nil
        suggestionsCacheTime = nil
    }
    
    /// 获取指定分类中的过期文件
    func getStaleFiles(in category: PARACategory) async -> [ManagedFile] {
        let allStale = await DatabaseManager.shared.getFiles(byLifecycleStage: .stale)
        return allStale.filter { $0.category == category }
    }
    
    /// 获取指定天数未访问的文件
    func getInactiveFiles(daysThreshold: Int) async -> [ManagedFile] {
        await DatabaseManager.shared.getInactiveFiles(daysThreshold: daysThreshold)
    }
    
    // MARK: - Project Archiving
    
    /// 归档整个项目（子目录中的所有文件）
    func archiveProject(
        subcategory: String,
        strategy: ProjectArchiveStrategy,
        reason: TransitionReason = .projectCompleted,
        notes: String? = nil
    ) async -> [ManagedFile] {
        // Get all files in the project subcategory
        let files = await DatabaseManager.shared.getFiles(category: .projects, subcategory: subcategory)
        
        guard !files.isEmpty else { return [] }
        
        var archivedFiles: [ManagedFile] = []
        
        switch strategy {
        case .archiveAll:
            // Move all files to Archives
            for file in files {
                await recordTransition(
                    file: file,
                    from: .projects,
                    to: .archives,
                    fromSub: subcategory,
                    toSub: subcategory, // Keep same subcategory name in Archives
                    reason: reason,
                    notes: notes
                )
                archivedFiles.append(file)
            }
            
        case .smartArchive:
            // Detect and extract reusable assets, archive the rest
            for file in files {
                if let detectedAsset = detectReusableAsset(file) {
                    // Move reusable assets to Resources
                    await recordTransition(
                        file: file,
                        from: .projects,
                        to: .resources,
                        fromSub: subcategory,
                        toSub: detectedAsset.assetType.suggestedSubcategory,
                        reason: .projectOutputReuse,
                        notes: "检测到可复用\(detectedAsset.assetType.rawValue)"
                    )
                } else {
                    // Archive non-reusable files
                    await recordTransition(
                        file: file,
                        from: .projects,
                        to: .archives,
                        fromSub: subcategory,
                        toSub: subcategory,
                        reason: reason,
                        notes: notes
                    )
                    archivedFiles.append(file)
                }
            }
            
        case .markComplete:
            // Just update lifecycle stage, don't move files
            for file in files {
                await DatabaseManager.shared.updateLifecycleStage(fileId: file.id, stage: .archived)
            }
        }
        
        return archivedFiles
    }
    
    // MARK: - Reusable Asset Detection
    
    /// 检测文件是否为可复用资产 (增强版)
    private func detectReusableAsset(_ file: ManagedFile) -> ReusableAssetDetection? {
        let ext = file.fileExtension.lowercased()
        let name = file.displayName.lowercased()
        let tagNames = file.tags.map { $0.name.lowercased() }
        
        // 1. 基于标签的高优先级检测
        let reusableTags = ["模板", "可复用", "通用", "template", "reusable", "共享", "shared"]
        if tagNames.contains(where: { tag in reusableTags.contains(where: { tag.contains($0) }) }) {
            return ReusableAssetDetection(file: file, assetType: .template, confidence: 0.95)
        }
        
        // 2. Template detection - 模板文件
        let templatePatterns = ["模板", "template", "样板", "范本", "boilerplate", "starter"]
        let templateExtensions = ["docx", "xlsx", "pptx", "doc", "xls", "ppt", "md", "txt", "rtf"]
        
        if templatePatterns.contains(where: { name.contains($0) }) && templateExtensions.contains(ext) {
            return ReusableAssetDetection(file: file, assetType: .template, confidence: 0.9)
        }
        
        // 3. Code/Script detection - 代码脚本
        let codeExtensions = ["py", "js", "ts", "swift", "sh", "bash", "zsh", "sql", "rb", "go", "java", "kt", "rs", "c", "cpp", "h"]
        let scriptPatterns = ["脚本", "script", "工具", "tool", "util", "helper", "common", "lib", "snippet"]
        
        if codeExtensions.contains(ext) || scriptPatterns.contains(where: { name.contains($0) }) {
            return ReusableAssetDetection(file: file, assetType: .code, confidence: 0.85)
        }
        
        // 4. Design asset detection - 设计资产
        let designExtensions = ["fig", "sketch", "xd", "psd", "ai", "svg", "eps", "indd"]
        let designPatterns = ["规范", "design", "设计", "组件", "component", "icon", "图标", "ui", "ux", "mockup", "原型"]
        
        if designExtensions.contains(ext) || designPatterns.contains(where: { name.contains($0) }) {
            return ReusableAssetDetection(file: file, assetType: .design, confidence: 0.8)
        }
        
        // 5. Configuration detection - 配置文件
        let configExtensions = ["json", "yaml", "yml", "xml", "ini", "conf", "toml", "env"]
        let configPatterns = ["config", "配置", "setting", "设置", "preference"]
        
        if configExtensions.contains(ext) && configPatterns.contains(where: { name.contains($0) }) {
            return ReusableAssetDetection(file: file, assetType: .template, confidence: 0.75)
        }
        
        // 6. Research/Reference detection - 研究报告
        let researchPatterns = ["报告", "report", "分析", "analysis", "研究", "research", "白皮书", "whitepaper", "调研", "survey"]
        
        if researchPatterns.contains(where: { name.contains($0) }) {
            return ReusableAssetDetection(file: file, assetType: .research, confidence: 0.75)
        }
        
        // 7. 基于文件大小的启发式 (小文件更可能是可复用组件)
        if file.fileSize < 50_000 && codeExtensions.contains(ext) {
            return ReusableAssetDetection(file: file, assetType: .code, confidence: 0.6)
        }
        
        return nil
    }
    
    // MARK: - Batch Operations
    
    /// 批量归档过期文件
    func batchArchiveStaleFiles(files: [ManagedFile], reason: TransitionReason = .inactivityTimeout) async {
        for file in files {
            guard file.category != .archives else { continue }
            
            await recordTransition(
                file: file,
                from: file.category,
                to: .archives,
                fromSub: file.subcategory,
                toSub: file.subcategory,
                reason: reason,
                isAutomatic: true
            )
        }
    }
}
