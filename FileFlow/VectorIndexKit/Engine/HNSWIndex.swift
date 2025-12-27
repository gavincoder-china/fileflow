//
//  HNSWIndex.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import Foundation
import simd

/// HNSW (Hierarchical Navigable Small World) 向量索引实现
/// 这是一个简化版实现，优化了易读性和性能平衡
public class HNSWIndex: VectorIndex {
    private var nodes: [HNSWNode] = []
    private var maxLevel: Int = 16
    private var m: Int = 16
    private var mMax: Int = 32
    private var levelFactor: Float = 1 / log(2.0)
    private let efConstruction: Int = 200
    private let efSearch: Int = 100
    private var vectorDimension: Int = 0
    private var buildStartTime: Date = Date()

    /// HNSW 节点
    private struct HNSWNode {
        let id: UUID
        let documentId: UUID
        let fileId: UUID
        var vector: Vector
        var neighbors: [[UUID]] = [] // 每层邻居列表
        var metadata: [String: String]

        init(id: UUID, documentId: UUID, fileId: UUID, vector: Vector, metadata: [String: String]) {
            self.id = id
            self.documentId = documentId
            self.fileId = fileId
            self.vector = vector
            self.neighbors = Array(repeating: [], count: 17) // 0-16层
            self.metadata = metadata
        }
    }

    public init() {}

    public var stats: VectorIndexStats {
        let memoryUsage = estimateMemoryUsage()
        return VectorIndexStats(
            documentCount: nodes.count,
            vectorDimension: vectorDimension,
            memoryUsage: memoryUsage,
            buildTime: Date().timeIntervalSince(buildStartTime)
        )
    }

    public func add(_ documents: [VectorDocument]) throws {
        guard !documents.isEmpty else { return }

        // 验证向量维度一致性
        if vectorDimension == 0 {
            vectorDimension = documents.first?.vector.count ?? 0
        }

        for document in documents {
            if document.vector.count != vectorDimension {
                throw VectorIndexError.dimensionMismatch
            }

            let node = HNSWNode(
                id: document.id,
                documentId: document.id,
                fileId: document.fileId,
                vector: document.vector,
                metadata: document.metadata
            )

            // 计算随机层级
            let level = generateRandomLevel()
            insertNode(node, atLevel: level)
        }
    }

    public func remove(id: UUID) throws {
        nodes.removeAll { $0.id == id }
    }

    public func search(query: Vector, limit: Int) throws -> [VectorSearchResult] {
        guard !nodes.isEmpty else { return [] }
        guard query.count == vectorDimension else { throw VectorIndexError.dimensionMismatch }

        let results = searchKNN(query: query, k: limit)
        return results
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(nodes)
        try data.write(to: url)
    }

    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        nodes = try decoder.decode([HNSWNode].self, from: data)

        if !nodes.isEmpty {
            vectorDimension = nodes.first?.vector.count ?? 0
        }
    }

    // MARK: - Private Methods

    private func generateRandomLevel() -> Int {
        let randomLevel = Int(floor(-log(Float.random(in: 0...1)) * levelFactor))
        return min(randomLevel, maxLevel)
    }

    private func insertNode(_ node: HNSWNode, atLevel level: Int) {
        var newNode = node
        newNode.neighbors = Array(repeating: [], count: level + 1)

        // 从最高层开始搜索插入位置
        var visited = Set<UUID>()
        var currentLevel = min(level, maxLevel)

        var enterPoint: UUID?
        if !nodes.isEmpty {
            enterPoint = findEnterPoint(query: newNode.vector, level: currentLevel, visited: &visited)
        }

        // 在每一层插入连接
        for l in (0...level).reversed() {
            var neighbors: [UUID] = []
            if let enterPoint = enterPoint {
                neighbors = searchAtLevel(query: newNode.vector, level: l, enterPoint: enterPoint, limit: m)
            }

            // 更新邻居的连接
            for neighborId in neighbors {
                if let neighborIndex = nodes.firstIndex(where: { $0.id == neighborId }) {
                    // 确保双向连接
                    if !nodes[neighborIndex].neighbors[l].contains(newNode.id) {
                        nodes[neighborIndex].neighbors[l].append(newNode.id)
                    }

                    // 限制连接数量
                    if nodes[neighborIndex].neighbors[l].count > mMax {
                        nodes[neighborIndex].neighbors[l] = Array(nodes[neighborIndex].neighbors[l].prefix(mMax))
                    }
                }
            }

            newNode.neighbors[l] = neighbors
            enterPoint = neighbors.first
        }

        nodes.append(newNode)
    }

    private func findEnterPoint(query: Vector, level: Int, visited: inout Set<UUID>) -> UUID? {
        guard !nodes.isEmpty else { return nil }

        var currentNode = nodes.randomElement()!
        visited.insert(currentNode.id)

        for l in (0...level).reversed() {
            var improved = true
            while improved {
                improved = false
                let neighbors = searchAtLevel(query: query, level: l, enterPoint: currentNode.id, limit: m)

                for neighborId in neighbors {
                    if visited.contains(neighborId) { continue }

                    let neighborIndex = nodes.firstIndex { $0.id == neighborId }!
                    let neighbor = nodes[neighborIndex]

                    if distance(query, neighbor.vector) < distance(query, currentNode.vector) {
                        currentNode = neighbor
                        visited.insert(currentNode.id)
                        improved = true
                    }
                }
            }
        }

        return currentNode.id
    }

    private func searchAtLevel(query: Vector, level: Int, enterPoint: UUID, limit: Int) -> [UUID] {
        var visited = Set<UUID>()
        var currentNode = nodes.first { $0.id == enterPoint }!
        visited.insert(currentNode.id)

        var candidates: [HNSWNode] = [currentNode]
        var result: [HNSWNode] = [currentNode]

        while !candidates.isEmpty {
            candidates.sort { distance(query, $0.vector) < distance(query, $1.vector) }
            let current = candidates.removeFirst()

            if distance(query, result.last!.vector) <= distance(query, current.vector) {
                continue
            }

            // 检查邻居
            for neighborId in current.neighbors[level] {
                if visited.contains(neighborId) { continue }

                if let neighborIndex = nodes.firstIndex(where: { $0.id == neighborId }) {
                    let neighbor = nodes[neighborIndex]
                    candidates.append(neighbor)
                    result.append(neighbor)
                    visited.insert(neighborId)

                    // 保持结果大小
                    if result.count > limit {
                        result.sort { distance(query, $0.vector) < distance(query, $1.vector) }
                        _ = result.popLast()
                    }
                }
            }
        }

        result.sort { distance(query, $0.vector) < distance(query, $1.vector) }
        return Array(result.prefix(limit).map { $0.id })
    }

    private func searchKNN(query: Vector, k: Int) -> [VectorSearchResult] {
        guard !nodes.isEmpty else { return [] }

        var visited = Set<UUID>()
        var currentNode = nodes.randomElement()!
        visited.insert(currentNode.id)

        var candidates: [HNSWNode] = [currentNode]
        var result: [HNSWNode] = [currentNode]

        let maxSearchLevel = nodes.reduce(Int.max) { min($0, $1.neighbors.count - 1) }

        for l in (0...maxSearchLevel).reversed() {
            var improved = true
            while improved {
                improved = false
                let neighbors = searchAtLevel(query: query, level: l, enterPoint: currentNode.id, limit: efSearch)

                for neighborId in neighbors {
                    if visited.contains(neighborId) { continue }

                    if let neighborIndex = nodes.firstIndex(where: { $0.id == neighborId }) {
                        let neighbor = nodes[neighborIndex]
                        candidates.append(neighbor)

                        if distance(query, neighbor.vector) < distance(query, result.last!.vector) {
                            currentNode = neighbor
                            result.append(neighbor)
                            visited.insert(currentNode.id)
                            improved = true
                        }

                        // 保持候选队列大小
                        if candidates.count > efSearch {
                            candidates.sort { distance(query, $0.vector) < distance(query, $1.vector) }
                            _ = candidates.popLast()
                        }
                    }
                }
            }
        }

        result.sort { distance(query, $0.vector) < distance(query, $1.vector) }
        let topResults = Array(result.prefix(k))

        return topResults.compactMap { node in
            let dist = distance(query, node.vector)
            let similarity = 1.0 / (1.0 + dist) // 转换距离为相似度

            return VectorSearchResult(
                id: UUID(),
                documentId: node.documentId,
                fileId: node.fileId,
                similarity: similarity,
                distance: dist,
                metadata: node.metadata
            )
        }
    }

    private func distance(_ v1: Vector, _ v2: Vector) -> Double {
        var sum: Float = 0
        for i in 0..<min(v1.count, v2.count) {
            let diff = v1[i] - v2[i]
            sum += diff * diff
        }
        return Double(sum)
    }

    private func cosineSimilarity(_ v1: Vector, _ v2: Vector) -> Double {
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0

        for i in 0..<min(v1.count, v2.count) {
            dotProduct += v1[i] * v2[i]
            norm1 += v1[i] * v1[i]
            norm2 += v2[i] * v2[i]
        }

        let denominator = sqrt(norm1) * sqrt(norm2)
        return denominator == 0 ? 0 : Double(dotProduct / denominator)
    }

    private func estimateMemoryUsage() -> Int64 {
        var totalBytes: Int64 = 0

        // 估算每个节点的内存占用
        for node in nodes {
            totalBytes += Int64(MemoryLayout<HNSWNode>.size)

            // 向量内存
            totalBytes += Int64(node.vector.count * MemoryLayout<Float>.size)

            // 邻居列表内存
            for neighborLevel in node.neighbors {
                totalBytes += Int64(neighborLevel.count * MemoryLayout<UUID>.size)
            }
        }

        return totalBytes
    }
}

/// 向量索引错误类型
public enum VectorIndexError: Error, LocalizedError {
    case dimensionMismatch
    case emptyIndex
    case invalidParameter(String)

    public var errorDescription: String? {
        switch self {
        case .dimensionMismatch:
            return "向量维度不匹配"
        case .emptyIndex:
            return "索引为空"
        case .invalidParameter(let message):
            return "无效参数: \(message)"
        }
    }
}
