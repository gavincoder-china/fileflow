//
//  ContentExtractor.swift
//  FileFlow
//
//  多模态内容提取器 - 支持 PDF、图片 OCR、Word 文档等
//

import Foundation
import Vision
import PDFKit
import AppKit

enum DocumentContentExtractor {
    
    /// 从文件中提取文本内容
    /// - Parameter url: 文件 URL
    /// - Returns: 提取的文本内容
    static func extractText(from url: URL) async throws -> String {
        // Run on background thread to prevent UI freeze
        return try await Task.detached(priority: .userInitiated) {
            let ext = url.pathExtension.lowercased()
            
            switch ext {
            case "pdf":
                return try extractPDF(url)
            case "png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif":
                return try await extractImageOCR(url)
            case "txt", "md", "markdown", "json", "xml", "html", "css", "js", "swift", "py":
                return try String(contentsOf: url, encoding: .utf8)
            case "rtf":
                return try extractRTF(url)
            case "doc", "docx":
                return try extractDocx(url)
            default:
                // Try to read as plain text, return empty if fails
                return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
        }.value
    }
    
    // MARK: - PDF Extraction
    
    private static func extractPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpenFile
        }
        
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let pageText = page.string {
                text += pageText + "\n"
            }
        }
        
        // Limit to reasonable length for AI processing
        if text.count > 50000 {
            text = String(text.prefix(50000)) + "\n...[truncated]"
        }
        
        return text
    }
    
    // MARK: - Image OCR
    
    private static func extractImageOCR(_ url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExtractionError.cannotOpenFile
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: text)
            }
            
            // Configure for better accuracy
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
    
    // MARK: - RTF Extraction
    
    private static func extractRTF(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let attributedString = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return attributedString.string
    }
    
    // MARK: - DOCX Extraction (Basic)
    
    private static func extractDocx(_ url: URL) throws -> String {
        // DOCX is a ZIP file containing XML
        // We'll extract the main document.xml content
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Unzip the docx
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", tempDir.path]
        
        try process.run()
        process.waitUntilExit()
        
        // Read document.xml
        let documentXML = tempDir.appendingPathComponent("word/document.xml")
        
        guard fileManager.fileExists(atPath: documentXML.path) else {
            throw ExtractionError.cannotOpenFile
        }
        
        let xmlData = try Data(contentsOf: documentXML)
        let xmlString = String(data: xmlData, encoding: .utf8) ?? ""
        
        // Simple extraction: remove all XML tags
        let text = xmlString.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum ExtractionError: LocalizedError {
    case cannotOpenFile
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenFile:
            return "无法打开或读取文件"
        case .unsupportedFormat:
            return "不支持的文件格式"
        }
    }
}
