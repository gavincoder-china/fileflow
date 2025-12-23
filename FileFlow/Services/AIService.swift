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
}

// MARK: - AI Service Factory
class AIServiceFactory {
    static func createService() -> AIServiceProtocol {
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
