//
//  BatchImportService.swift
//  FileFlow
//
//  批量导入服务
//  提供重复检测、AI 分析队列、撤销回滚等功能
//

import Foundation
import CryptoKit

// MARK: - Batch Import Service
/// 批量导入核心服务
actor BatchImportService {
    static let shared = BatchImportService()
    
    private let fileManager = FileManager.default
    private let database = DatabaseManager.shared
    
    // 导入会话历史 (支持撤销)
    private var sessionHistory: [BatchImportSession] = []
    private let maxSessionHistory = 10
    
    private init() {}
    
    // MARK: - Content Hash (SHA256)
    
    /// 计算文件内容哈希
    func calculateContentHash(for url: URL) async throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// 批量计算哈希 - 返回更新后的数组
    func calculateHashes(for items: [ImportFileItem], progress: @escaping (Int, Int) -> Void) async -> [ImportFileItem] {
        var result = items
        for i in 0..<result.count {
            progress(i + 1, result.count)
            do {
                result[i].contentHash = try await calculateContentHash(for: result[i].sourceURL)
            } catch {
                Logger.error("Failed to hash file: \(result[i].fileName)")
            }
        }
        return result
    }
    
    // MARK: - Duplicate Detection
    
    /// 检测重复文件 - 返回更新后的数组
    func detectDuplicates(items: [ImportFileItem]) async -> [ImportFileItem] {
        var result = items
        
        // 获取现有文件的哈希
        let existingFiles = await database.getRecentFiles(limit: 10000)
        
        // 建立哈希索引
        var hashToFile: [String: ManagedFile] = [:]
        for file in existingFiles {
            if let hash = file.contentHash {
                hashToFile[hash] = file
            }
        }
        
        // 检测重复
        for i in 0..<result.count {
            if let hash = result[i].contentHash,
               let existingFile = hashToFile[hash] {
                result[i].status = .duplicate(existingId: existingFile.id)
            }
        }
        return result
    }
    
    /// 检测文件名冲突 - 返回更新后的数组
    func detectConflicts(items: [ImportFileItem], targetCategory: PARACategory, subcategory: String?) async -> [ImportFileItem] {
        var result = items
        guard let root = FileFlowManager.shared.rootURL else { return result }
        
        var targetFolder = root.appendingPathComponent(targetCategory.folderName)
        if let sub = subcategory {
            targetFolder = targetFolder.appendingPathComponent(sub)
        }
        
        for i in 0..<result.count {
            let targetPath = targetFolder.appendingPathComponent(result[i].finalName)
            if fileManager.fileExists(atPath: targetPath.path) {
                result[i].status = .conflict(existingPath: targetPath.path)
            }
        }
        return result
    }
    
    // MARK: - Batch AI Analysis
    
    /// 批量 AI 分析队列 - 返回更新后的数组
    func analyzeFiles(items: [ImportFileItem], progress: @escaping (Int, Int, String) -> Void) async -> [ImportFileItem] {
        var result = items
        let aiService = AIServiceFactory.createService()
        
        for i in 0..<result.count {
            guard result[i].isSelected else { continue }
            
            result[i].status = .analyzing
            progress(i + 1, result.count, result[i].fileName)
            
            // 调用 AI 分析
            do {
                // 读取文件内容
                let content = try String(contentsOf: result[i].sourceURL, encoding: .utf8)
                let aiResult = try await aiService.analyzeFile(content: content, fileName: result[i].fileName)
                result[i].suggestedCategory = aiResult.suggestedCategory
                result[i].suggestedSubcategory = aiResult.suggestedSubcategory
                result[i].suggestedName = nil
                result[i].suggestedTags = aiResult.suggestedTags
                result[i].selectedCategory = aiResult.suggestedCategory
                result[i].selectedSubcategory = aiResult.suggestedSubcategory
                result[i].status = .ready
            } catch {
                // AI 分析失败时使用默认值
                result[i].status = .ready
                Logger.error("AI analysis failed for \(result[i].fileName): \(error)")
            }
        }
        return result
    }
    
    // MARK: - Import Execution
    
    /// 执行批量导入
    func executeImport(
        items: [ImportFileItem],
        options: ImportOptions,
        progress: @escaping (Int, Int, String) -> Void
    ) async -> (session: BatchImportSession, results: [ImportResult]) {
        
        var session = BatchImportSession()
        session.totalCount = items.filter { $0.isSelected }.count
        session.appliedTags = options.applyBatchTags
        
        var results: [ImportResult] = []
        var processedCount = 0
        
        for item in items {
            guard item.isSelected else { continue }
            
            processedCount += 1
            progress(processedCount, session.totalCount, item.fileName)
            
            // 处理重复
            if case .duplicate = item.status {
                switch options.duplicateHandling {
                case .skip:
                    results.append(ImportResult(
                        id: item.id,
                        sourceURL: item.sourceURL,
                        destinationURL: nil,
                        fileId: nil,
                        status: .skipped(reason: "重复文件"),
                        timestamp: Date()
                    ))
                    session.skippedCount += 1
                    continue
                case .keepBoth:
                    break // 继续导入
                case .replaceExisting:
                    // TODO: 删除现有文件
                    break
                case .ask:
                    break // 预览模式应已处理
                }
            }
            
            // 处理冲突
            if case .conflict = item.status {
                switch options.conflictResolution {
                case .skip:
                    results.append(ImportResult(
                        id: item.id,
                        sourceURL: item.sourceURL,
                        destinationURL: nil,
                        fileId: nil,
                        status: .skipped(reason: "名称冲突"),
                        timestamp: Date()
                    ))
                    session.skippedCount += 1
                    continue
                case .autoRename, .overwrite, .ask:
                    break // 由 FileFlowManager 处理
                }
            }
            
            // 执行导入
            do {
                // 准备标签
                var tags: [Tag] = []
                let allTags = await database.getAllTags()
                let tagNames = Set(item.suggestedTags + options.applyBatchTags)
                
                for tagName in tagNames {
                    if let existing = allTags.first(where: { $0.name == tagName }) {
                        tags.append(existing)
                    } else {
                        // 创建新标签
                        let newTag = Tag(name: tagName)
                        await database.saveTag(newTag)
                        tags.append(newTag)
                    }
                }
                
                // 移动文件
                let destinationURL = try FileFlowManager.shared.moveAndRenameFile(
                    from: item.sourceURL,
                    to: item.selectedCategory,
                    subcategory: item.selectedSubcategory,
                    newName: item.finalName,
                    tags: tags
                )
                
                // 保存到数据库
                var managedFile = ManagedFile(
                    originalName: item.fileName,
                    originalPath: item.sourceURL.path,
                    category: item.selectedCategory,
                    subcategory: item.selectedSubcategory,
                    tags: tags,
                    contentHash: item.contentHash
                )
                managedFile.newName = item.finalName
                managedFile.newPath = destinationURL.path
                
                await database.saveFile(managedFile, tags: tags)
                
                session.importedFileIds.append(managedFile.id)
                session.successCount += 1
                
                results.append(ImportResult(
                    id: item.id,
                    sourceURL: item.sourceURL,
                    destinationURL: destinationURL,
                    fileId: managedFile.id,
                    status: .success,
                    timestamp: Date()
                ))
                
            } catch {
                session.failedCount += 1
                results.append(ImportResult(
                    id: item.id,
                    sourceURL: item.sourceURL,
                    destinationURL: nil,
                    fileId: nil,
                    status: .failed(error: error.localizedDescription),
                    timestamp: Date()
                ))
            }
        }
        
        session.completedAt = Date()
        
        // 保存会话历史
        sessionHistory.insert(session, at: 0)
        if sessionHistory.count > maxSessionHistory {
            sessionHistory.removeLast()
        }
        
        return (session, results)
    }
    
    // MARK: - Undo / Rollback
    
    /// 获取最近的导入会话
    func getRecentSessions() -> [BatchImportSession] {
        sessionHistory
    }
    
    /// 撤销导入会话
    func undoSession(_ session: BatchImportSession) async -> (success: Int, failed: Int) {
        var successCount = 0
        var failedCount = 0
        
        for fileId in session.importedFileIds {
            do {
                // 通过 ID 查找文件
                let files = await database.getRecentFiles(limit: 10000)
                if let file = files.first(where: { $0.id == fileId }) {
                    // 删除文件 (移到废纸篓)
                    let url = URL(fileURLWithPath: file.newPath)
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                    
                    // 从数据库删除
                    await database.deleteFile(fileId)
                    
                    successCount += 1
                }
            } catch {
                Logger.error("Failed to undo file: \(error)")
                failedCount += 1
            }
        }
        
        // 从历史中移除
        sessionHistory.removeAll { $0.id == session.id }
        
        return (successCount, failedCount)
    }
    
    /// 清除会话历史
    func clearSessionHistory() {
        sessionHistory.removeAll()
    }
}
