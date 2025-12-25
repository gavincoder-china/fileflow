//
//  IncrementalIndexService.swift
//  FileFlow
//
//  增量索引服务
//  仅更新变更的文件，而非全量扫描
//

import Foundation
import CryptoKit

// MARK: - File Change Type
enum FileChangeType {
    case added
    case modified
    case deleted
    case unchanged
}

// MARK: - File Change Info
struct FileChangeInfo: Identifiable {
    let id = UUID()
    let path: String
    let changeType: FileChangeType
    let oldModificationDate: Date?
    let newModificationDate: Date?
    let fileSize: Int64
}

// MARK: - Incremental Index Service
actor IncrementalIndexService {
    static let shared = IncrementalIndexService()
    
    /// 上次扫描时间
    private var lastScanTime: Date?
    
    /// 文件状态缓存 (path -> modificationDate)
    private var fileStateCache: [String: Date] = [:]
    
    /// 扫描锁，防止并发扫描
    private var isScanning = false
    
    private init() {}
    
    // MARK: - Public API
    
    /// 执行增量扫描
    /// - Returns: 变更的文件列表
    func performIncrementalScan() async -> [FileChangeInfo] {
        guard !isScanning else {
            Logger.warning("增量扫描正在进行中，跳过本次请求")
            return []
        }
        
        isScanning = true
        defer { isScanning = false }
        
        let startTime = Date()
        Logger.info("开始增量扫描...")
        
        // 获取根目录
        guard let rootPath = UserDefaults.standard.string(forKey: "rootDirectoryPath") else {
            Logger.error("未配置根目录")
            return []
        }
        
        // 加载数据库中的已知文件
        let knownFiles = await loadKnownFiles()
        
        // 扫描当前文件系统状态
        let currentFiles = scanFileSystem(rootPath: rootPath)
        
        // 检测变更
        let changes = detectChanges(known: knownFiles, current: currentFiles)
        
        // 更新缓存
        for (path, date) in currentFiles {
            fileStateCache[path] = date
        }
        
        lastScanTime = Date()
        
        let elapsed = Date().timeIntervalSince(startTime)
        Logger.success("增量扫描完成: \(changes.count) 个变更, 耗时 \(String(format: "%.2f", elapsed))s")
        
        return changes
    }
    
    /// 同步变更到数据库
    func syncChanges(_ changes: [FileChangeInfo]) async -> (added: Int, modified: Int, deleted: Int) {
        var addedCount = 0
        var modifiedCount = 0
        var deletedCount = 0
        
        for change in changes {
            switch change.changeType {
            case .added:
                if await processAddedFile(path: change.path) {
                    addedCount += 1
                }
            case .modified:
                if await processModifiedFile(path: change.path) {
                    modifiedCount += 1
                }
            case .deleted:
                if await processDeletedFile(path: change.path) {
                    deletedCount += 1
                }
            case .unchanged:
                break
            }
        }
        
        Logger.success("同步完成: 新增 \(addedCount), 修改 \(modifiedCount), 删除 \(deletedCount)")
        
        return (addedCount, modifiedCount, deletedCount)
    }
    
    /// 快速检查是否有变更（不进行完整扫描）
    func hasChanges() async -> Bool {
        guard let rootPath = UserDefaults.standard.string(forKey: "rootDirectoryPath") else {
            return false
        }
        
        // 快速检查：比较目录修改时间
        let fileManager = FileManager.default
        
        for category in PARACategory.allCases {
            let categoryPath = (rootPath as NSString).appendingPathComponent(category.rawValue)
            
            if let attrs = try? fileManager.attributesOfItem(atPath: categoryPath),
               let modDate = attrs[.modificationDate] as? Date {
                if let lastScan = lastScanTime, modDate > lastScan {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// 获取上次扫描时间
    func getLastScanTime() -> Date? {
        lastScanTime
    }
    
    /// 清除缓存
    func clearCache() {
        fileStateCache.removeAll()
        lastScanTime = nil
        Logger.info("增量索引缓存已清除")
    }
    
    // MARK: - Private Methods
    
    /// 加载数据库中已知的文件
    private func loadKnownFiles() async -> [String: Date] {
        let files = await DatabaseManager.shared.getRecentFiles(limit: 10000)
        var result: [String: Date] = [:]
        
        for file in files {
            result[file.newPath] = file.modifiedAt
        }
        
        return result
    }
    
    /// 扫描文件系统
    private func scanFileSystem(rootPath: String) -> [String: Date] {
        var result: [String: Date] = [:]
        let fileManager = FileManager.default
        
        for category in PARACategory.allCases {
            let categoryPath = (rootPath as NSString).appendingPathComponent(category.rawValue)
            
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: categoryPath),
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            while let url = enumerator.nextObject() as? URL {
                guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      resourceValues.isRegularFile == true,
                      let modDate = resourceValues.contentModificationDate else {
                    continue
                }
                
                result[url.path] = modDate
            }
        }
        
        return result
    }
    
    /// 检测变更
    private func detectChanges(known: [String: Date], current: [String: Date]) -> [FileChangeInfo] {
        var changes: [FileChangeInfo] = []
        
        // 检测新增和修改
        for (path, currentDate) in current {
            if let knownDate = known[path] {
                // 文件存在于数据库
                if currentDate > knownDate {
                    // 文件被修改
                    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                    changes.append(FileChangeInfo(
                        path: path,
                        changeType: .modified,
                        oldModificationDate: knownDate,
                        newModificationDate: currentDate,
                        fileSize: size
                    ))
                }
            } else {
                // 新文件
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                changes.append(FileChangeInfo(
                    path: path,
                    changeType: .added,
                    oldModificationDate: nil,
                    newModificationDate: currentDate,
                    fileSize: size
                ))
            }
        }
        
        // 检测删除
        for (path, knownDate) in known {
            if current[path] == nil {
                changes.append(FileChangeInfo(
                    path: path,
                    changeType: .deleted,
                    oldModificationDate: knownDate,
                    newModificationDate: nil,
                    fileSize: 0
                ))
            }
        }
        
        return changes
    }
    
    /// 处理新增文件
    private func processAddedFile(path: String) async -> Bool {
        // 新文件需要用户导入，这里只记录日志
        Logger.info("检测到新文件: \(path)")
        return true
    }
    
    /// 处理修改的文件
    private func processModifiedFile(path: String) async -> Bool {
        // 更新数据库中的修改时间
        guard let file = await DatabaseManager.shared.getFile(byPath: path) else {
            return false
        }
        
        var updatedFile = file
        updatedFile.modifiedAt = Date()
        
        // 重新计算内容哈希
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let hash = SHA256.hash(data: data)
            updatedFile.contentHash = hash.compactMap { String(format: "%02x", $0) }.joined()
        }
        
        await DatabaseManager.shared.updateFile(updatedFile)
        Logger.info("文件已更新: \(path)")
        
        return true
    }
    
    /// 处理删除的文件
    private func processDeletedFile(path: String) async -> Bool {
        guard let file = await DatabaseManager.shared.getFile(byPath: path) else {
            return false
        }
        
        await DatabaseManager.shared.deleteFile(file.id)
        Logger.info("文件记录已删除: \(path)")
        
        return true
    }
    
    // MARK: - File Hash Calculation
    
    /// 计算文件哈希
    func calculateFileHash(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
