//
//  AIService.swift
//  FileFlow
//
//  AI 分析服务 - 支持 OpenAI API 和本地 Ollama
//

import Foundation

// MARK: - AI Service Protocol
protocol AIServiceProtocol {
    func analyzeFile(content: String, fileName: String) async throws -> AIAnalysisResult
    func testConnection() async throws -> Bool
    func analyzeMergeCandidates(items: [String], itemType: String, context: String?) async throws -> [AIMergeSuggestion]
}

// MARK: - AI Merge Suggestion Result
struct AIMergeSuggestion: Codable {
    let source: String
    let target: String
    let similarity: Double
    let reason: String
    let suggestedName: String?
    
    enum CodingKeys: String, CodingKey {
        case source, target, similarity, reason
        case suggestedName = "suggested_name"
    }
}

// MARK: - Default Implementation for Merge Analysis
extension AIServiceProtocol {
    func analyzeMergeCandidates(items: [String], itemType: String, context: String?) async throws -> [AIMergeSuggestion] {
        // 默认实现：返回空数组，子类可覆盖
        return []
    }
}

// MARK: - AI Service Factory
class AIServiceFactory {
    static func createService() -> AIServiceProtocol {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai"
        
        let baseService: AIServiceProtocol
        switch provider {
        case "openai":
            baseService = OpenAIService()
        case "ollama":
            baseService = OllamaService()
        default:
            baseService = MockAIService()
        }
        
        // 包装为可重试服务
        return RetryableAIService(wrapped: baseService)
    }
    
    /// 创建不带重试的原始服务（用于测试连接）
    static func createRawService() -> AIServiceProtocol {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai"
        
        switch provider {
        case "openai":
            return OpenAIService()
        case "ollama":
            return OllamaService()
        default:
            return MockAIService()
        }
    }
}

// MARK: - Retryable AI Service (Exponential Backoff)
/// 带指数退避重试的 AI 服务包装器
class RetryableAIService: AIServiceProtocol {
    private let wrapped: AIServiceProtocol
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    
    init(wrapped: AIServiceProtocol, maxRetries: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0) {
        self.wrapped = wrapped
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }
    
    func testConnection() async throws -> Bool {
        try await wrapped.testConnection()
    }
    
    func analyzeMergeCandidates(items: [String], itemType: String, context: String?) async throws -> [AIMergeSuggestion] {
        // Delegate to wrapped service (no retry for this method currently)
        try await wrapped.analyzeMergeCandidates(items: items, itemType: itemType, context: context)
    }
    
    func analyzeFile(content: String, fileName: String) async throws -> AIAnalysisResult {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                let result = try await wrapped.analyzeFile(content: content, fileName: fileName)
                if attempt > 0 {
                    Logger.success("AI 分析成功 (第 \(attempt + 1) 次尝试)")
                }
                return result
            } catch {
                lastError = error
                
                // 判断是否可重试的错误
                if !isRetryable(error) {
                    Logger.error("AI 分析失败 (不可重试): \(error.localizedDescription)")
                    throw error
                }
                
                // 最后一次不等待
                if attempt < maxRetries - 1 {
                    let delay = calculateDelay(attempt: attempt)
                    Logger.warning("AI 分析失败，\(String(format: "%.1f", delay))s 后重试 (第 \(attempt + 1)/\(maxRetries) 次): \(error.localizedDescription)")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        Logger.error("AI 分析失败，已达最大重试次数: \(lastError?.localizedDescription ?? "未知错误")")
        throw lastError ?? AIError.apiError("未知错误")
    }
    
    /// 计算指数退避延迟 (带抖动)
    private func calculateDelay(attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.3) * exponentialDelay
        return min(exponentialDelay + jitter, maxDelay)
    }
    
    /// 判断错误是否可重试
    private func isRetryable(_ error: Error) -> Bool {
        if let aiError = error as? AIError {
            switch aiError {
            case .missingApiKey:
                return false // 配置问题，不重试
            case .parseError:
                return true // 可能是临时问题
            case .apiError(let message):
                // 速率限制或服务器错误可重试
                let retryableKeywords = ["rate limit", "timeout", "500", "502", "503", "504", "overloaded"]
                return retryableKeywords.contains { message.lowercased().contains($0) }
            case .invalidURL, .extractionError:
                return false
            }
        }
        
        // URLError 通常可重试
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        return false
    }
}

// MARK: - OpenAI Service
class OpenAIService: AIServiceProtocol {
    private let apiKey: String
    private let model: String // Added model support
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        self.model = UserDefaults.standard.string(forKey: "openaiModel") ?? "gpt-4o-mini"
    }
    
    func testConnection() async throws -> Bool {
        guard !apiKey.isEmpty else { throw AIError.missingApiKey }
        
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return true
        } else {
            throw AIError.apiError("Connection failed")
        }
    }
    
    func analyzeFile(content: String, fileName: String) async throws -> AIAnalysisResult {
        guard !apiKey.isEmpty else {
            throw AIError.missingApiKey
        }
        
        let prompt = """
        分析以下文件内容，并提供：
        1. 一句话摘要（不超过50字）
        2. 3-5个相关标签
        3. 推荐的PARA分类（Projects/Areas/Resources/Archives）
        4. 推荐的子目录名称
        
        文件名: \(fileName)
        文件内容:
        \(content.prefix(3000))
        
        请用JSON格式回复：
        {
            "summary": "摘要",
            "tags": ["标签1", "标签2"],
            "category": "Resources",
            "subcategory": "子目录"
        }
        """
        
        let requestBody: [String: Any] = [
            "model": model, // Use configured model
            "messages": [
                ["role": "system", "content": "你是一个文件整理助手，帮助用户分析和分类文件。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.apiError("无效的响应")
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError(message)
            }
            throw AIError.apiError("API 请求失败: \(httpResponse.statusCode)")
        }
        
        return try parseOpenAIResponse(data)
    }
    
    private func parseOpenAIResponse(_ data: Data) throws -> AIAnalysisResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }
        
        // Parse the JSON content from the response
        // Clean up markdown code blocks if present
        var cleanContent = content
        if cleanContent.hasPrefix("```json") {
            cleanContent = cleanContent.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        
        guard let contentData = cleanContent.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            throw AIError.parseError
        }
        
        let summary = result["summary"] as? String ?? ""
        let tags = result["tags"] as? [String] ?? []
        let categoryStr = result["category"] as? String ?? "Resources"
        let subcategory = result["subcategory"] as? String
        
        let category = PARACategory(rawValue: categoryStr) ?? .resources
        
        return AIAnalysisResult(
            summary: summary,
            suggestedTags: tags,
            suggestedCategory: category,
            suggestedSubcategory: subcategory,
            confidence: 0.85
        )
    }
    
    // MARK: - Merge Analysis
    
    func analyzeMergeCandidates(items: [String], itemType: String, context: String?) async throws -> [AIMergeSuggestion] {
        guard !apiKey.isEmpty else {
            throw AIError.missingApiKey
        }
        
        guard items.count >= 2 else { return [] }
        
        var prompt = """
        你是一个基于 PARA 方法论的知识管理专家。请分析以下\(itemType)列表，识别语义相似或功能重叠的项目对，并给出合并建议。

        PARA 方法论简介：
        - Projects (项目): 有明确目标和截止日期的工作
        - Areas (领域): 需要持续关注的责任范围
        - Resources (资源): 可能有用的参考资料
        - Archives (归档): 已完成或不再活跃的内容

        """
        
        if let ctx = context {
            prompt += "上下文信息: \(ctx)\n\n"
        }
        
        prompt += "待分析的\(itemType)列表：\n"
        for (index, item) in items.enumerated() {
            prompt += "\(index + 1). \(item)\n"
        }
        
        prompt += """

        请识别所有语义相似的\(itemType)对。只返回相似度 >= 0.7 的配对。
        
        以 JSON 格式返回合并建议（如果没有相似项，返回空数组）：
        {
          "suggestions": [
            {
              "source": "被合并项名称",
              "target": "保留项名称",
              "similarity": 0.92,
              "reason": "合并理由（简短说明为什么这两个项目应该合并）",
              "suggested_name": "合并后建议使用的名称"
            }
          ]
        }
        """
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一个知识管理专家，擅长识别语义相似的概念和分类。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 1000
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIError.apiError(message)
            }
            throw AIError.apiError("API 请求失败")
        }
        
        return try parseMergeSuggestions(data)
    }
    
    private func parseMergeSuggestions(_ data: Data) throws -> [AIMergeSuggestion] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }
        
        // Clean up markdown code blocks
        var cleanContent = content
        if cleanContent.hasPrefix("```json") {
            cleanContent = cleanContent.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        cleanContent = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let contentData = cleanContent.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let suggestionsArray = result["suggestions"] as? [[String: Any]] else {
            // 如果解析失败，返回空数组而不是抛出错误
            return []
        }
        
        return suggestionsArray.compactMap { dict -> AIMergeSuggestion? in
            guard let source = dict["source"] as? String,
                  let target = dict["target"] as? String,
                  let similarity = dict["similarity"] as? Double,
                  let reason = dict["reason"] as? String else {
                return nil
            }
            
            return AIMergeSuggestion(
                source: source,
                target: target,
                similarity: similarity,
                reason: reason,
                suggestedName: dict["suggested_name"] as? String
            )
        }
    }
}

// MARK: - Ollama Service
class OllamaService: AIServiceProtocol {
    private let host: String
    private let model: String
    
    init() {
        self.host = UserDefaults.standard.string(forKey: "ollamaHost") ?? "http://localhost:11434"
        self.model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
    }
    
    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(host)/api/tags") else { throw AIError.invalidURL }
        
        let (_, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return true
        } else {
            throw AIError.apiError("Connection failed")
        }
    }
    
    func analyzeFile(content: String, fileName: String) async throws -> AIAnalysisResult {
        let prompt = """
        分析以下文件内容，并提供：
        1. 一句话摘要（不超过50字）
        2. 3-5个相关标签
        3. 推荐的PARA分类（Projects/Areas/Resources/Archives）
        4. 推荐的子目录名称
        
        文件名: \(fileName)
        文件内容:
        \(content.prefix(2000))
        
        请用JSON格式回复：
        {
            "summary": "摘要",
            "tags": ["标签1", "标签2"],
            "category": "Resources",
            "subcategory": "子目录"
        }
        """
        
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json" // Request JSON format from Ollama
        ]
        
        guard let url = URL(string: "\(host)/api/generate") else {
            throw AIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIError.apiError("Ollama 请求失败: \(response)")
        }
        
        return try parseOllamaResponse(data)
    }
    
    private func parseOllamaResponse(_ data: Data) throws -> AIAnalysisResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw AIError.parseError
        }
        
        // Extract JSON from response
        var jsonString = response
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            jsonString = String(response[jsonStart...jsonEnd])
        }
            
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIError.parseError
        }
        
        let summary = result["summary"] as? String ?? ""
        let tags = result["tags"] as? [String] ?? []
        let categoryStr = result["category"] as? String ?? "Resources"
        let subcategory = result["subcategory"] as? String
        
        let category = PARACategory(rawValue: categoryStr) ?? .resources
        
        return AIAnalysisResult(
            summary: summary,
            suggestedTags: tags,
            suggestedCategory: category,
            suggestedSubcategory: subcategory,
            confidence: 0.75
        )
    }
}

// MARK: - Mock AI Service
class MockAIService: AIServiceProtocol {
    func testConnection() async throws -> Bool {
        try await Task.sleep(nanoseconds: 500_000_000)
        return true
    }
    
    func analyzeFile(content: String, fileName: String) async throws -> AIAnalysisResult {
        // Simulate processing time
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        var tags: [String]
        var category: PARACategory
        var summary: String
        
        switch ext {
        case "pdf":
            tags = ["文档", "PDF", "待读"]
            category = .resources
            summary = "这是一个 PDF 文档"
        case "png", "jpg", "jpeg":
            tags = ["图片", "素材"]
            category = .resources
            summary = "这是一个图片文件"
        case "mp4", "mov":
            tags = ["视频", "媒体"]
            category = .resources
            summary = "这是一个视频文件"
        case "doc", "docx":
            tags = ["Word", "文档"]
            category = .resources
            summary = "这是一个 Word 文档"
        default:
            tags = ["文件"]
            category = .resources
            summary = "这是一个文件"
        }
        
        return AIAnalysisResult(
            summary: summary,
            suggestedTags: tags,
            suggestedCategory: category,
            suggestedSubcategory: nil,
            confidence: 0.5
        )
    }
    
    func analyzeMergeCandidates(items: [String], itemType: String, context: String?) async throws -> [AIMergeSuggestion] {
        try await Task.sleep(nanoseconds: 800_000_000) // Simulate network delay
        
        var suggestions: [AIMergeSuggestion] = []
        
        guard items.count >= 2 else { return [] }
        
        // Dynamic analysis based on actual items using Levenshtein distance
        for i in 0..<items.count {
            for j in (i+1)..<items.count {
                let item1 = items[i]
                let item2 = items[j]
                
                let name1 = item1.lowercased()
                let name2 = item2.lowercased()
                
                // Check similarity
                var similarity: Double = 0
                var reason: String = ""
                
                // 1. Exact match (different case)
                if name1 == name2 && item1 != item2 {
                    similarity = 1.0
                    reason = "大小写不同，建议统一。"
                }
                // 2. Contains relationship
                else if name1.contains(name2) || name2.contains(name1) {
                    let longer = max(name1.count, name2.count)
                    let shorter = min(name1.count, name2.count)
                    let ratio = Double(shorter) / Double(longer)
                    if ratio >= 0.5 {
                        similarity = 0.85
                        reason = "存在包含关系，可以考虑合并。"
                    }
                }
                // 3. Common prefix
                else {
                    let commonPrefix = name1.commonPrefix(with: name2)
                    if commonPrefix.count >= 3 {
                        let prefixSimilarity = Double(commonPrefix.count) / Double(max(name1.count, name2.count))
                        if prefixSimilarity >= 0.5 {
                            similarity = prefixSimilarity * 0.9
                            reason = "前缀相同，可能属于同一类别。"
                        }
                    }
                }
                // 4. Levenshtein distance
                if similarity == 0 {
                    let distance = levenshteinDistance(name1, name2)
                    let maxLen = max(name1.count, name2.count)
                    if maxLen > 0 {
                        let stringSimilarity = 1.0 - Double(distance) / Double(maxLen)
                        if stringSimilarity >= 0.6 {
                            similarity = stringSimilarity
                            reason = "命名相似，建议统一。"
                        }
                    }
                }
                
                if similarity >= 0.6 {
                    // Suggest keeping the shorter or more-used name
                    let (source, target) = item1.count > item2.count ? (item1, item2) : (item2, item1)
                    suggestions.append(AIMergeSuggestion(
                        source: source,
                        target: target,
                        similarity: similarity,
                        reason: reason,
                        suggestedName: target
                    ))
                }
            }
        }
        
        // Sort by similarity descending
        return suggestions.sorted { $0.similarity > $1.similarity }
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                dp[i][j] = min(
                    dp[i-1][j] + 1,
                    dp[i][j-1] + 1,
                    dp[i-1][j-1] + cost
                )
            }
        }
        
        return dp[m][n]
    }
}




// MARK: - AI Errors
enum AIError: LocalizedError {
    case missingApiKey
    case invalidURL
    case apiError(String)
    case parseError
    case extractionError
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "缺少 API Key，请在设置中配置"
        case .invalidURL:
            return "无效的服务地址"
        case .apiError(let message):
            return message
        case .parseError:
            return "解析 AI 响应失败"
        case .extractionError:
            return "无法提取文件内容"
        }
    }
}
