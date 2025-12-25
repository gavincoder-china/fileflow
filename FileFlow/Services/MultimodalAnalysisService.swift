//
//  MultimodalAnalysisService.swift
//  FileFlow
//
//  多模态分析服务
//  支持 PDF 文本提取、图片 OCR、音频转文字
//

import Foundation
import Vision
import PDFKit
import Speech
import NaturalLanguage

// MARK: - Multimodal Analysis Result
struct MultimodalAnalysisResult {
    let extractedText: String
    let keywords: [String]
    let language: String?
    let confidence: Double
    let analysisType: AnalysisType
    
    enum AnalysisType: String {
        case pdf = "PDF 文本"
        case ocr = "图片识别"
        case audio = "音频转写"
        case unknown = "未知"
    }
}

// MARK: - Multimodal Analysis Service
actor MultimodalAnalysisService {
    static let shared = MultimodalAnalysisService()
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    
    private init() {}
    
    // MARK: - Public API
    
    /// 分析文件内容
    func analyzeFile(at url: URL) async throws -> MultimodalAnalysisResult? {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf":
            return try await analyzePDF(at: url)
        case "png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif":
            return try await analyzeImage(at: url)
        case "mp3", "m4a", "wav", "aac", "aiff":
            return try await analyzeAudio(at: url)
        default:
            return nil
        }
    }
    
    // MARK: - PDF Analysis
    
    /// 从 PDF 提取文本
    func analyzePDF(at url: URL) async throws -> MultimodalAnalysisResult {
        guard let pdf = PDFDocument(url: url) else {
            throw AnalysisError.invalidFile
        }
        
        var fullText = ""
        
        for i in 0..<min(pdf.pageCount, 50) {  // 限制页数
            if let page = pdf.page(at: i),
               let text = page.string {
                fullText += text + "\n"
            }
        }
        
        let keywords = extractKeywords(from: fullText)
        let language = detectLanguage(fullText)
        
        Logger.success("PDF 分析完成: \(pdf.pageCount) 页, \(fullText.count) 字符")
        
        return MultimodalAnalysisResult(
            extractedText: fullText,
            keywords: keywords,
            language: language,
            confidence: 0.95,
            analysisType: .pdf
        )
    }
    
    // MARK: - Image OCR
    
    /// 图片文字识别
    func analyzeImage(at url: URL) async throws -> MultimodalAnalysisResult {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AnalysisError.invalidFile
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: AnalysisError.noResults)
                    return
                }
                
                var extractedText = ""
                var totalConfidence: Float = 0
                
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        extractedText += candidate.string + "\n"
                        totalConfidence += candidate.confidence
                    }
                }
                
                let avgConfidence = observations.isEmpty ? 0 : Double(totalConfidence / Float(observations.count))
                let keywords = self.extractKeywordsSync(from: extractedText)
                let language = self.detectLanguageSync(extractedText)
                
                Logger.success("OCR 完成: \(observations.count) 个文本块, 置信度 \(String(format: "%.1f%%", avgConfidence * 100))")
                
                let result = MultimodalAnalysisResult(
                    extractedText: extractedText,
                    keywords: keywords,
                    language: language,
                    confidence: avgConfidence,
                    analysisType: .ocr
                )
                
                continuation.resume(returning: result)
            }
            
            // 配置识别选项
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Audio Transcription
    
    /// 音频转文字
    func analyzeAudio(at url: URL) async throws -> MultimodalAnalysisResult {
        // 检查并请求权限
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            
            guard status == .authorized else {
                throw AnalysisError.permissionDenied
            }
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AnalysisError.serviceUnavailable
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result, result.isFinal else { return }
                
                let text = result.bestTranscription.formattedString
                let keywords = self.extractKeywordsSync(from: text)
                let confidence = Double(result.bestTranscription.segments.map { $0.confidence }.reduce(0, +)) / 
                               Double(max(result.bestTranscription.segments.count, 1))
                
                Logger.success("音频转写完成: \(text.count) 字符")
                
                let analysisResult = MultimodalAnalysisResult(
                    extractedText: text,
                    keywords: keywords,
                    language: "zh-CN",
                    confidence: confidence,
                    analysisType: .audio
                )
                
                continuation.resume(returning: analysisResult)
            }
        }
    }
    
    // MARK: - Keyword Extraction
    
    private func extractKeywords(from text: String) -> [String] {
        extractKeywordsSync(from: text)
    }
    
    private nonisolated func extractKeywordsSync(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var keywords: [String: Int] = [:]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag = tag, [.noun, .verb, .adjective].contains(tag) {
                let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if word.count >= 2 {
                    keywords[word, default: 0] += 1
                }
            }
            return true
        }
        
        return keywords
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { $0.key }
    }
    
    // MARK: - Language Detection
    
    private func detectLanguage(_ text: String) -> String? {
        detectLanguageSync(text)
    }
    
    private nonisolated func detectLanguageSync(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
    
    // MARK: - Errors
    
    enum AnalysisError: Error, LocalizedError {
        case invalidFile
        case noResults
        case permissionDenied
        case serviceUnavailable
        
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "无法读取文件"
            case .noResults: return "未识别到内容"
            case .permissionDenied: return "需要语音识别权限"
            case .serviceUnavailable: return "服务不可用"
            }
        }
    }
}
