//
//  VectorDocument.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import Foundation
import CoreGraphics

/// 向量类型别名
public typealias Vector = [Float]

/// 向量文档结构
/// 包含文件的向量表示、元数据和唯一标识
public struct VectorDocument: Codable, Identifiable {
    public let id: UUID
    public let fileId: UUID
    public let vector: Vector
    public let metadata: [String: String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fileId: UUID,
        vector: Vector,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileId = fileId
        self.vector = vector
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

/// 向量搜索结果
public struct VectorSearchResult: Identifiable, Equatable {
    public let id: UUID
    public let documentId: UUID
    public let fileId: UUID
    public let similarity: Double // 0-1 范围
    public let distance: Double // 欧氏距离
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        documentId: UUID,
        fileId: UUID,
        similarity: Double,
        distance: Double,
        metadata: [String: String]
    ) {
        self.id = id
        self.documentId = documentId
        self.fileId = fileId
        self.similarity = similarity
        self.distance = distance
        self.metadata = metadata
    }

    public static func == (lhs: VectorSearchResult, rhs: VectorSearchResult) -> Bool {
        return lhs.id == rhs.id
    }
}

/// 向量索引协议
public protocol VectorIndex {
    /// 添加文档到索引
    func add(_ documents: [VectorDocument]) throws

    /// 从索引中移除文档
    func remove(id: UUID) throws

    /// 搜索相似向量
    /// - Parameters:
    ///   - query: 查询向量
    ///   - limit: 返回结果数量限制
    /// - Returns: 按相似度排序的搜索结果
    func search(query: Vector, limit: Int) throws -> [VectorSearchResult]

    /// 保存索引到文件
    func save(to url: URL) throws

    /// 从文件加载索引
    func load(from url: URL) throws

    /// 获取索引统计信息
    var stats: VectorIndexStats { get }
}

/// 向量索引统计信息
public struct VectorIndexStats {
    public let documentCount: Int
    public let vectorDimension: Int
    public let memoryUsage: Int64 // 字节
    public let buildTime: TimeInterval

    public init(documentCount: Int, vectorDimension: Int, memoryUsage: Int64, buildTime: TimeInterval) {
        self.documentCount = documentCount
        self.vectorDimension = vectorDimension
        self.memoryUsage = memoryUsage
        self.buildTime = buildTime
    }
}
