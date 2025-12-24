//
//  EmbeddingService.swift
//  FileFlow
//
//  语义搜索服务 - 支持本地和 OpenAI Embedding 双模式
//
//  设计理念：
//  1. 优先使用本地 NaturalLanguage 框架（无需网络）
//  2. 可选切换到 OpenAI text-embedding-3-small（更精准）
//  3. 向量存储在 SQLite BLOB 中，支持余弦相似度搜索
//

import Foundation
import NaturalLanguage

// MARK: - Embedding Provider Protocol

protocol EmbeddingProvider {
    func embed(text: String) async throws -> [Float]
    var dimensions: Int { get }
}

// MARK: - Provider Selection

enum EmbeddingProviderType: String, CaseIterable {
    case local = "local"          // NaturalLanguage (macOS built-in)
    case openai = "openai"        // OpenAI text-embedding-3-small
    
    var displayName: String {
        switch self {
        case .local: return "本地 (NaturalLanguage)"
        case .openai: return "OpenAI Embedding"
        }
    }
}

// MARK: - Embedding Service

class EmbeddingService {
    static let shared = EmbeddingService()
    
    private var currentProvider: EmbeddingProvider
    private var providerType: EmbeddingProviderType
    
    private init() {
        // Default to local provider
        let savedType = UserDefaults.standard.string(forKey: "embeddingProvider") ?? "local"
        self.providerType = EmbeddingProviderType(rawValue: savedType) ?? .local
        self.currentProvider = Self.createProvider(for: self.providerType)
    }
    
    // MARK: - Provider Management
    
    var currentProviderType: EmbeddingProviderType {
        return providerType
    }
    
    func switchProvider(to type: EmbeddingProviderType) {
        guard type != providerType else { return }
        providerType = type
        currentProvider = Self.createProvider(for: type)
        UserDefaults.standard.set(type.rawValue, forKey: "embeddingProvider")
        Logger.info("Switched embedding provider to: \(type.displayName)")
    }
    
    private static func createProvider(for type: EmbeddingProviderType) -> EmbeddingProvider {
        switch type {
        case .local:
            return LocalEmbeddingProvider()
        case .openai:
            return OpenAIEmbeddingProvider()
        }
    }
    
    // MARK: - Embedding Operations
    
    /// Generate embedding for text
    func embed(text: String) async throws -> [Float] {
        return try await currentProvider.embed(text: text)
    }
    
    /// Compute cosine similarity between two embeddings
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
    
    /// Find similar files by embedding
    func findSimilar(query: String, limit: Int = 10) async throws -> [(fileId: UUID, similarity: Float)] {
        let queryEmbedding = try await embed(text: query)
        let allEmbeddings = await DatabaseManager.shared.getAllFileEmbeddings()
        
        var results: [(fileId: UUID, similarity: Float)] = []
        
        for (fileId, embedding) in allEmbeddings {
            let similarity = cosineSimilarity(queryEmbedding, embedding)
            if similarity > 0.5 { // Threshold
                results.append((fileId, similarity))
            }
        }
        
        return results.sorted { $0.similarity > $1.similarity }.prefix(limit).map { $0 }
    }
}

// MARK: - Local Embedding Provider (NaturalLanguage)

class LocalEmbeddingProvider: EmbeddingProvider {
    private let embedding: NLEmbedding?
    
    let dimensions: Int = 512 // NLEmbedding default dimension
    
    init() {
        // Use sentence embedding for better semantic understanding
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
        
        if embedding == nil {
            Logger.warning("NLEmbedding not available, falling back to word embedding")
        }
    }
    
    func embed(text: String) async throws -> [Float] {
        // NLEmbedding returns Double vectors, convert to Float
        if let embedding = embedding,
           let vector = embedding.vector(for: text) {
            return vector.map { Float($0) }
        }
        
        // Fallback: Use word embeddings and average
        guard let wordEmbedding = NLEmbedding.wordEmbedding(for: .english) else {
            throw EmbeddingError.modelNotAvailable
        }
        
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var sum = [Float](repeating: 0, count: dimensions)
        var count = 0
        
        for word in words {
            if let vector = wordEmbedding.vector(for: word.lowercased()) {
                for (i, val) in vector.enumerated() where i < dimensions {
                    sum[i] += Float(val)
                }
                count += 1
            }
        }
        
        if count > 0 {
            return sum.map { $0 / Float(count) }
        }
        
        // Return zero vector if no words matched
        return [Float](repeating: 0, count: dimensions)
    }
}

// MARK: - OpenAI Embedding Provider

class OpenAIEmbeddingProvider: EmbeddingProvider {
    let dimensions: Int = 1536 // text-embedding-3-small
    
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
    }
    
    func embed(text: String) async throws -> [Float] {
        guard !apiKey.isEmpty else {
            throw EmbeddingError.apiKeyMissing
        }
        
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "text-embedding-3-small",
            "input": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.apiError
        }
        
        struct EmbeddingResponse: Codable {
            struct EmbeddingData: Codable {
                let embedding: [Float]
            }
            let data: [EmbeddingData]
        }
        
        let result = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        
        guard let embedding = result.data.first?.embedding else {
            throw EmbeddingError.invalidResponse
        }
        
        return embedding
    }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case modelNotAvailable
    case apiKeyMissing
    case apiError
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "本地 Embedding 模型不可用"
        case .apiKeyMissing:
            return "OpenAI API Key 未配置"
        case .apiError:
            return "API 请求失败"
        case .invalidResponse:
            return "API 返回无效数据"
        }
    }
}
