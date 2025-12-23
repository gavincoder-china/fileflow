//
//  DeduplicationService.swift
//  FileFlow
//
//  智能去重服务 - 使用 SimHash 和 MD5 检测相似/重复文件
//

import Foundation
import CryptoKit

// MARK: - Duplicate Detection Result

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let hash: String
    let similarity: DuplicateType
    let files: [URL]
    
    var totalSize: Int64 {
        files.compactMap { url -> Int64? in
            try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        }.reduce(0, +)
    }
    
    var savableSize: Int64 {
        // All except one can be deleted
        let sizes = files.compactMap { url -> Int64? in
            try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        }.sorted(by: >)
        return sizes.dropFirst().reduce(0, +)
    }
}

enum DuplicateType {
    case exact       // 完全相同 (MD5)
    case similar     // 内容相似 (SimHash)
    
    var displayName: String {
        switch self {
        case .exact: return "完全相同"
        case .similar: return "内容相似"
        }
    }
}

// MARK: - Deduplication Service

class DeduplicationService {
    static let shared = DeduplicationService()
    
    private init() {}
    
    /// Find all duplicate files in the library
    /// - Returns: Groups of duplicate files
    func findDuplicates() async -> [DuplicateGroup] {
        guard FileFlowManager.shared.rootURL != nil else { return [] }
        
        var exactDuplicates: [String: [URL]] = [:]  // MD5 -> URLs
        var sizeBuckets: [Int64: [URL]] = [:]        // Size -> URLs (pre-filter)
        
        // 1. Group files by size (quick pre-filter)
        let allFiles = FileFlowManager.shared.scanAllFiles()
        
        for url in allFiles {
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                sizeBuckets[size, default: []].append(url)
            }
        }
        
        // 2. Only check files with same size
        for (_, urls) in sizeBuckets where urls.count > 1 {
            for url in urls {
                if let hash = md5(file: url) {
                    exactDuplicates[hash, default: []].append(url)
                }
            }
        }
        
        // 3. Create duplicate groups
        var groups: [DuplicateGroup] = []
        
        for (hash, urls) in exactDuplicates where urls.count > 1 {
            groups.append(DuplicateGroup(
                hash: hash,
                similarity: .exact,
                files: urls
            ))
        }
        
        // Sort by savable size (most space to save first)
        return groups.sorted { $0.savableSize > $1.savableSize }
    }
    
    /// Find similar files using SimHash
    func findSimilarFiles() async -> [DuplicateGroup] {
        guard FileFlowManager.shared.rootURL != nil else { return [] }
        
        var contentHashes: [(url: URL, simhash: UInt64)] = []
        let allFiles = FileFlowManager.shared.scanAllFiles()
        
        // Calculate SimHash for text-based files
        for url in allFiles {
            let ext = url.pathExtension.lowercased()
            let textExtensions = ["txt", "md", "swift", "py", "js", "html", "css", "json", "xml"]
            
            if textExtensions.contains(ext) {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    let hash = simhash(text: content)
                    contentHashes.append((url, hash))
                }
            }
        }
        
        // Find similar pairs (Hamming distance <= 3)
        var similarGroups: [String: [URL]] = [:]
        let processed = Set<URL>()
        
        for i in 0..<contentHashes.count {
            if processed.contains(contentHashes[i].url) { continue }
            
            var group: [URL] = [contentHashes[i].url]
            
            for j in (i+1)..<contentHashes.count {
                if processed.contains(contentHashes[j].url) { continue }
                
                let distance = hammingDistance(contentHashes[i].simhash, contentHashes[j].simhash)
                if distance <= 3 {
                    group.append(contentHashes[j].url)
                }
            }
            
            if group.count > 1 {
                let key = String(contentHashes[i].simhash)
                similarGroups[key] = group
            }
        }
        
        return similarGroups.map { key, urls in
            DuplicateGroup(hash: key, similarity: .similar, files: urls)
        }
    }
    
    // MARK: - MD5 Hash
    
    private func md5(file url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // MARK: - SimHash (Locality Sensitive Hashing)
    
    /// Calculate SimHash for text content
    private func simhash(text: String) -> UInt64 {
        var v = [Int](repeating: 0, count: 64)
        
        // Tokenize and hash each feature
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        for word in words {
            let featureHash = word.hashValue  // Swift's built-in hash
            
            for i in 0..<64 {
                let bit = (featureHash >> i) & 1
                if bit == 1 {
                    v[i] += 1
                } else {
                    v[i] -= 1
                }
            }
        }
        
        // Build final hash
        var result: UInt64 = 0
        for i in 0..<64 {
            if v[i] > 0 {
                result |= (1 << i)
            }
        }
        
        return result
    }
    
    /// Calculate Hamming distance between two hashes
    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        var xor = a ^ b
        var count = 0
        while xor != 0 {
            count += 1
            xor &= xor - 1
        }
        return count
    }
    
    // MARK: - Actions
    
    /// Delete a file from duplicate group
    func deleteFile(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
    
    /// Keep one file, delete all others in group
    func keepOnly(_ url: URL, in group: DuplicateGroup) throws {
        for fileURL in group.files where fileURL != url {
            try deleteFile(fileURL)
        }
    }
}
