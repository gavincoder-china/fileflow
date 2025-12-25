//
//  SpotlightIndexService.swift
//  FileFlow
//
//  CoreSpotlight 集成 - 让 macOS Spotlight 能搜索 FileFlow 的文件元数据
//

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

actor SpotlightIndexService {
    static let shared = SpotlightIndexService()
    
    private let domainIdentifier = "com.fileflow.files"
    
    private init() {}
    
    // MARK: - Index Single File
    
    /// 将单个文件添加到 Spotlight 索引
    func indexFile(_ file: ManagedFile) async {
        let attributeSet = CSSearchableItemAttributeSet(contentType: determineContentType(for: file))
        
        // 基本信息
        attributeSet.title = file.displayName
        attributeSet.displayName = file.displayName
        attributeSet.contentDescription = file.summary
        
        // 关键词 (标签)
        attributeSet.keywords = file.tags.map { $0.name }
        
        // 元数据
        attributeSet.contentCreationDate = file.importedAt
        attributeSet.contentModificationDate = file.modifiedAt
        attributeSet.kind = file.category.displayName
        
        // 文件路径 (用于打开)
        attributeSet.contentURL = URL(fileURLWithPath: file.newPath)
        attributeSet.relatedUniqueIdentifier = file.id.uuidString
        
        // 缩略图 (如果是图片或 PDF)
        if let thumbnailData = await generateThumbnail(for: file) {
            attributeSet.thumbnailData = thumbnailData
        }
        
        let item = CSSearchableItem(
            uniqueIdentifier: file.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        
        // 设置过期时间 (1年后过期，会自动重新索引)
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())
        
        do {
            try await CSSearchableIndex.default().indexSearchableItems([item])
            Logger.info("🔍 Spotlight: 已索引 \(file.displayName)")
        } catch {
            Logger.error("🔍 Spotlight 索引失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Batch Index
    
    /// 批量索引文件
    func indexFiles(_ files: [ManagedFile]) async {
        let items = await withTaskGroup(of: CSSearchableItem?.self) { group in
            for file in files {
                group.addTask {
                    await self.createSearchableItem(for: file)
                }
            }
            
            var results: [CSSearchableItem] = []
            for await item in group {
                if let item = item {
                    results.append(item)
                }
            }
            return results
        }
        
        guard !items.isEmpty else { return }
        
        do {
            try await CSSearchableIndex.default().indexSearchableItems(items)
            Logger.info("🔍 Spotlight: 批量索引 \(items.count) 个文件")
        } catch {
            Logger.error("🔍 Spotlight 批量索引失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Remove from Index
    
    /// 从索引中删除文件
    func removeFile(id: UUID) async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])
            Logger.info("🔍 Spotlight: 已移除索引 \(id)")
        } catch {
            Logger.error("🔍 Spotlight 移除失败: \(error.localizedDescription)")
        }
    }
    
    /// 清空所有索引
    func removeAllIndexes() async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
            Logger.info("🔍 Spotlight: 已清空所有索引")
        } catch {
            Logger.error("🔍 Spotlight 清空索引失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Rebuild Index
    
    /// 重建所有索引
    func rebuildIndex() async {
        // 先清空
        await removeAllIndexes()
        
        // 获取所有文件
        let files = await DatabaseManager.shared.getAllFiles()
        
        // 批量索引
        await indexFiles(files)
        
        Logger.success("🔍 Spotlight: 重建索引完成，共 \(files.count) 个文件")
    }
    
    // MARK: - Private Helpers
    
    private func createSearchableItem(for file: ManagedFile) async -> CSSearchableItem? {
        let attributeSet = CSSearchableItemAttributeSet(contentType: determineContentType(for: file))
        
        attributeSet.title = file.displayName
        attributeSet.displayName = file.displayName
        attributeSet.contentDescription = file.summary
        attributeSet.keywords = file.tags.map { $0.name }
        attributeSet.contentCreationDate = file.importedAt
        attributeSet.contentModificationDate = file.modifiedAt
        attributeSet.kind = file.category.displayName
        attributeSet.contentURL = URL(fileURLWithPath: file.newPath)
        
        let item = CSSearchableItem(
            uniqueIdentifier: file.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())
        
        return item
    }
    
    private func determineContentType(for file: ManagedFile) -> UTType {
        let ext = file.fileExtension.lowercased()
        
        switch ext {
        case "pdf": return .pdf
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "doc", "docx": return .content
        case "xls", "xlsx": return .spreadsheet
        case "ppt", "pptx": return .presentation
        case "md", "txt": return .plainText
        default: return .item
        }
    }
    
    private func generateThumbnail(for file: ManagedFile) async -> Data? {
        // 简化版缩略图生成 - 实际可用 QuickLookThumbnailing
        // 这里返回 nil，让系统使用文件图标
        return nil
    }
}

// MARK: - App Delegate Extension for Spotlight Continuation

extension SpotlightIndexService {
    
    /// 处理从 Spotlight 点击结果跳转回 App 的情况
    @MainActor
    static func handleSpotlightAction(userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let uuid = UUID(uuidString: identifier) else {
            return false
        }
        
        // 导航到对应文件
        Task {
            if let file = await DatabaseManager.shared.getFile(byId: uuid) {
                // 这里需要通过 AppState 导航
                // 可以发送通知或直接操作共享状态
                Logger.info("🔍 Spotlight: 用户点击了 \(file.displayName)")
            }
        }
        
        return true
    }
}
