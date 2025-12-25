//
//  SemanticSearchService.swift
//  FileFlow
//
//  语义搜索服务
//  基于 Embedding 的文件内容相似度搜索
//

import Foundation
import NaturalLanguage

// MARK: - Search Result
struct SemanticSearchResult: Identifiable {
    let id: UUID
    let file: ManagedFile
    let similarity: Double
    let matchedContent: String?
    
    var similarityPercent: String {
        String(format: "%.1f%%", similarity * 100)
    }
}

// MARK: - Semantic Search Service
actor SemanticSearchService {
    static let shared = SemanticSearchService()
    
    private let embeddingModel: NLEmbedding?
    private var fileEmbeddings: [UUID: [Double]] = [:]
    private let cacheKey = "file_embeddings_cache"
    
    private init() {
        // 使用 Apple 内置的词向量模型
        self.embeddingModel = NLEmbedding.wordEmbedding(for: .simplifiedChinese) ??
                             NLEmbedding.wordEmbedding(for: .english)
        
        Task { await loadCache() }
    }
    
    // MARK: - Public API
    
    /// 语义搜索文件
    func search(query: String, limit: Int = 20) async -> [SemanticSearchResult] {
        guard !query.isEmpty else { return [] }
        
        let queryEmbedding = generateEmbedding(for: query)
        guard !queryEmbedding.isEmpty else { return [] }
        
        var results: [(file: ManagedFile, similarity: Double)] = []
        
        // 获取所有文件
        let allFiles = await DatabaseManager.shared.getRecentFiles(limit: 1000)
        
        for file in allFiles {
            // 获取或生成文件嵌入
            let fileEmbed = await getOrGenerateEmbedding(for: file)
            guard !fileEmbed.isEmpty else { continue }
            
            // 计算余弦相似度
            let similarity = cosineSimilarity(queryEmbedding, fileEmbed)
            
            if similarity > 0.3 {  // 最低相似度阈值
                results.append((file, similarity))
            }
        }
        
        // 按相似度排序
        results.sort { $0.similarity > $1.similarity }
        
        return results.prefix(limit).map { result in
            SemanticSearchResult(
                id: result.file.id,
                file: result.file,
                similarity: result.similarity,
                matchedContent: nil
            )
        }
    }
    
    /// 查找相似文件
    func findSimilarFiles(to file: ManagedFile, limit: Int = 10) async -> [SemanticSearchResult] {
        let fileEmbed = await getOrGenerateEmbedding(for: file)
        guard !fileEmbed.isEmpty else { return [] }
        
        var results: [(file: ManagedFile, similarity: Double)] = []
        let allFiles = await DatabaseManager.shared.getRecentFiles(limit: 500)
        
        for otherFile in allFiles where otherFile.id != file.id {
            let otherEmbed = await getOrGenerateEmbedding(for: otherFile)
            guard !otherEmbed.isEmpty else { continue }
            
            let similarity = cosineSimilarity(fileEmbed, otherEmbed)
            
            if similarity > 0.5 {
                results.append((otherFile, similarity))
            }
        }
        
        results.sort { $0.similarity > $1.similarity }
        
        return results.prefix(limit).map { result in
            SemanticSearchResult(
                id: result.file.id,
                file: result.file,
                similarity: result.similarity,
                matchedContent: nil
            )
        }
    }
    
    /// 为文件生成嵌入向量
    func indexFile(_ file: ManagedFile) async {
        let embedding = generateEmbedding(for: file)
        if !embedding.isEmpty {
            fileEmbeddings[file.id] = embedding
            await saveCache()
        }
    }
    
    /// 批量索引文件
    func indexFiles(_ files: [ManagedFile]) async -> Int {
        var indexed = 0
        
        for file in files {
            let embedding = generateEmbedding(for: file)
            if !embedding.isEmpty {
                fileEmbeddings[file.id] = embedding
                indexed += 1
            }
        }
        
        await saveCache()
        Logger.success("语义索引完成: \(indexed)/\(files.count) 个文件")
        
        return indexed
    }
    
    // MARK: - Embedding Generation
    
    private func getOrGenerateEmbedding(for file: ManagedFile) async -> [Double] {
        if let cached = fileEmbeddings[file.id] {
            return cached
        }
        
        let embedding = generateEmbedding(for: file)
        if !embedding.isEmpty {
            fileEmbeddings[file.id] = embedding
        }
        
        return embedding
    }
    
    private func generateEmbedding(for file: ManagedFile) -> [Double] {
        // 组合文件信息生成文本
        var textParts: [String] = []
        
        textParts.append(file.displayName)
        
        if let summary = file.summary {
            textParts.append(summary)
        }
        
        if let notes = file.notes {
            textParts.append(notes)
        }
        
        for tag in file.tags {
            textParts.append(tag.name)
        }
        
        let combinedText = textParts.joined(separator: " ")
        return generateEmbedding(for: combinedText)
    }
    
    private func generateEmbedding(for text: String) -> [Double] {
        guard let model = embeddingModel else { return [] }
        
        // 分词并计算平均词向量
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var wordVectors: [[Double]] = []
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if let vector = model.vector(for: word) {
                wordVectors.append(vector.map { Double($0) })
            }
            return true
        }
        
        guard !wordVectors.isEmpty else { return [] }
        
        // 计算平均向量
        let dim = wordVectors[0].count
        var avgVector = [Double](repeating: 0, count: dim)
        
        for vector in wordVectors {
            for i in 0..<min(dim, vector.count) {
                avgVector[i] += vector[i]
            }
        }
        
        for i in 0..<dim {
            avgVector[i] /= Double(wordVectors.count)
        }
        
        return avgVector
    }
    
    // MARK: - Similarity Calculation
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
    
    // MARK: - Cache Management
    
    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            fileEmbeddings = decoded.reduce(into: [:]) { result, pair in
                if let uuid = UUID(uuidString: pair.key) {
                    result[uuid] = pair.value
                }
            }
            Logger.info("加载语义缓存: \(fileEmbeddings.count) 个文件")
        }
    }
    
    private func saveCache() async {
        let stringKeyDict = fileEmbeddings.reduce(into: [String: [Double]]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        
        if let data = try? JSONEncoder().encode(stringKeyDict) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    /// 清除缓存
    func clearCache() async {
        fileEmbeddings.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        Logger.info("语义搜索缓存已清除")
    }
    
    /// 获取索引状态
    func getIndexStats() -> (indexed: Int, total: Int) {
        return (fileEmbeddings.count, 0)  // total 需要从数据库获取
    }
}
