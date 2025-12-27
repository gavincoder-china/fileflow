//
//  VectorStorageManager.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import Foundation
import SwiftUI
import Combine

/// 向量存储管理器
/// 管理内存缓存、磁盘存储和向量索引
@MainActor
public class VectorStorageManager: ObservableObject {
    public static let shared = VectorStorageManager()

    // MARK: - Published Properties

    @Published public var isIndexing: Bool = false
    @Published public var indexProgress: Double = 0.0
    @Published public var indexStatus: String = "就绪"

    // MARK: - Private Properties

    private var index: VectorIndex
    private var memoryCache: [UUID: VectorDocument] = [:]
    private var mmapCache: MMapCache?
    private var memoryCacheLimit: Int = 10000 // 内存缓存文档数量限制

    private let cacheDirectory: URL
    private let indexFileURL: URL
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // 创建缓存目录
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("VectorCache", isDirectory: true)

        // 创建索引文件路径
        indexFileURL = urls[0].appendingPathComponent("vector_index.json")

        // 初始化索引
        self.index = HNSWIndex()

        // 初始化内存映射缓存
        mmapCache = MMapCache(directory: cacheDirectory)

        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 加载现有索引
        Task {
            await loadIndex()
        }

        // 监控内存警告
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("VectorStorageMemoryWarning"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await self.spillToDisk()
            }
        }
    }

    // MARK: - Public Methods

    /// 索引文档
    public func indexDocuments(_ documents: [VectorDocument]) async throws {
        guard !documents.isEmpty else { return }

        isIndexing = true
        indexStatus = "正在索引..."
        indexProgress = 0.0

        defer {
            isIndexing = false
            indexStatus = "索引完成"
            indexProgress = 1.0
        }

        // 分批处理以避免内存峰值
        let batchSize = 100
        let totalBatches = Int(ceil(Double(documents.count) / Double(batchSize)))

        for batchIndex in 0..<totalBatches {
            let startIndex = batchIndex * batchSize
            let endIndex = min(startIndex + batchSize, documents.count)
            let batch = Array(documents[startIndex..<endIndex])

            // 添加到内存缓存
            for document in batch {
                memoryCache[document.id] = document

                // 检查内存缓存限制
                if memoryCache.count > memoryCacheLimit {
                    await spillToDisk()
                }
            }

            // 添加到索引
            try index.add(batch)

            // 更新进度
            indexProgress = Double(batchIndex + 1) / Double(totalBatches)

            // 让出控制权以保持 UI 响应
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // 保存索引
        try await saveIndex()
    }

    /// 搜索相似文档
    public func searchSimilar(query: Vector, limit: Int = 10) async throws -> [VectorSearchResult] {
        return try index.search(query: query, limit: limit)
    }

    /// 移除文档
    public func removeDocument(id: UUID) async throws {
        memoryCache.removeValue(forKey: id)
        try mmapCache?.remove(id: id)
        try index.remove(id: id)
        try await saveIndex()
    }

    /// 清空索引
    public func clearIndex() async {
        memoryCache.removeAll()
        mmapCache?.clearAll()
        index = HNSWIndex()
        try? await saveIndex()
    }

    /// 获取索引统计信息
    public func getStats() -> VectorIndexStats {
        return index.stats
    }

    /// 搜索多个向量
    public func batchSearch(queries: [(Vector, Int)], limit: Int = 10) async throws -> [[VectorSearchResult]] {
        var results: [[VectorSearchResult]] = []

        for (query, queryLimit) in queries {
            let queryResults = try await searchSimilar(query: query, limit: min(limit, queryLimit))
            results.append(queryResults)
        }

        return results
    }

    /// 预热索引（加载常用数据到内存）
    public func warmUpIndex() async {
        indexStatus = "正在预热索引..."

        // 加载最近使用的文档到内存
        let recentDocs = getRecentDocuments(limit: 1000)
        for doc in recentDocs {
            if memoryCache[doc.id] == nil {
                memoryCache[doc.id] = doc
            }
        }

        indexStatus = "预热完成"
        try? await Task.sleep(nanoseconds: 100_000_000)
        indexStatus = "就绪"
    }

    // MARK: - Private Methods

    private func loadIndex() async {
        do {
            try index.load(from: indexFileURL)
            indexStatus = "索引已加载"
        } catch {
            indexStatus = "加载索引失败: \(error.localizedDescription)"
            print("Failed to load index: \(error)")
        }
    }

    private func saveIndex() async throws {
        try index.save(to: indexFileURL)
    }

    private func spillToDisk() async {
        guard memoryCache.count > memoryCacheLimit / 2 else { return }

        let spillCount = memoryCache.count / 3
        let keysToSpill = Array(memoryCache.keys.prefix(spillCount))

        for id in keysToSpill {
            if let document = memoryCache[id] {
                try? mmapCache?.store(document)
            }
        }

        for id in keysToSpill {
            memoryCache.removeValue(forKey: id)
        }

        print("Spilled \(keysToSpill.count) documents to disk")
    }

    private func getRecentDocuments(limit: Int) -> [VectorDocument] {
        // 这里应该从数据库获取最近使用的文档
        // 为了简化，我们返回空数组
        return []
    }
}

/// 内存映射缓存实现
class MMapCache {
    private let directory: URL
    private let maxFileSize: Int = 1024 * 1024 * 1024 // 1GB

    init(directory: URL) {
        self.directory = directory
    }

    func store(_ document: VectorDocument) throws {
        let fileURL = directory.appendingPathComponent("\(document.id).vec")
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL)
    }

    func load(id: UUID) throws -> VectorDocument? {
        let fileURL = directory.appendingPathComponent("\(id).vec")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(VectorDocument.self, from: data)
    }

    func remove(id: UUID) throws {
        let fileURL = directory.appendingPathComponent("\(id).vec")
        try FileManager.default.removeItem(at: fileURL)
    }

    func clearAll() {
        let fileManager = FileManager.default
        let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in contents ?? [] {
            try? fileManager.removeItem(at: url)
        }
    }
}

// MARK: - 内存警告扩展

extension Notification.Name {
    static let VectorStorageMemoryWarning = Notification.Name("VectorStorageMemoryWarning")
}

// MARK: - 使用示例

extension VectorStorageManager {
    /// 示例：索引文档
    public func indexExampleDocuments() async {
        let documents = [
            VectorDocument(
                fileId: UUID(),
                vector: [0.1, 0.2, 0.3, 0.4, 0.5],
                metadata: ["type": "example", "title": "示例文档"]
            ),
            VectorDocument(
                fileId: UUID(),
                vector: [0.2, 0.3, 0.4, 0.5, 0.6],
                metadata: ["type": "example", "title": "示例文档2"]
            )
        ]

        do {
            try await indexDocuments(documents)
            print("Documents indexed successfully")
        } catch {
            print("Indexing failed: \(error)")
        }
    }

    /// 示例：搜索相似文档
    public func searchExample(query: Vector) async {
        do {
            let results = try await searchSimilar(query: query, limit: 5)
            for result in results {
                print("Found similar document with similarity: \(result.similarity)")
            }
        } catch {
            print("Search failed: \(error)")
        }
    }
}
