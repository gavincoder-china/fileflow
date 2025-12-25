//
//  TagMergeService.swift
//  FileFlow
//
//  智能标签合并服务
//  检测相似标签并提供合并建议
//

import Foundation

// MARK: - Tag Similarity Result
struct TagSimilarityPair: Identifiable {
    let id = UUID()
    let tag1: Tag
    let tag2: Tag
    let similarity: Double
    let reason: SimilarityReason
    
    enum SimilarityReason: String {
        case editDistance = "拼写相似"
        case synonym = "同义词"
        case prefix = "前缀相同"
        case suffix = "后缀相同"
        case contains = "包含关系"
        case abbreviation = "缩写关系"
    }
    
    var displayReason: String {
        reason.rawValue
    }
    
    /// 推荐保留的标签 (使用频率更高的)
    var suggestedKeep: Tag {
        tag1.usageCount >= tag2.usageCount ? tag1 : tag2
    }
    
    /// 推荐合并的标签
    var suggestedMerge: Tag {
        tag1.usageCount >= tag2.usageCount ? tag2 : tag1
    }
}

// MARK: - Tag Merge Service
actor TagMergeService {
    static let shared = TagMergeService()
    
    // 常见同义词对照表 (可扩展)
    private let synonyms: [[String]] = [
        ["AI", "人工智能", "Artificial Intelligence"],
        ["ML", "机器学习", "Machine Learning"],
        ["UI", "用户界面", "User Interface"],
        ["UX", "用户体验", "User Experience"],
        ["文档", "文件", "Document", "Doc"],
        ["图片", "图像", "Image", "Picture"],
        ["视频", "Video", "影片"],
        ["代码", "Code", "源码", "源代码"],
        ["设计", "Design"],
        ["笔记", "Note", "Notes"],
        ["工具", "Tool", "Tools"],
        ["教程", "Tutorial", "指南", "Guide"],
        ["报告", "Report"],
        ["会议", "Meeting"],
        ["项目", "Project"],
        ["PDF", "pdf"],
        ["PPT", "演示", "Presentation"],
        ["Excel", "表格", "Spreadsheet"]
    ]
    
    private init() {}
    
    // MARK: - Find Similar Tags
    
    /// 检测所有相似标签对
    func findSimilarTags(minSimilarity: Double = 0.7) async -> [TagSimilarityPair] {
        let allTags = await DatabaseManager.shared.getAllTags()
        var pairs: [TagSimilarityPair] = []
        
        // 避免重复比较
        for i in 0..<allTags.count {
            for j in (i+1)..<allTags.count {
                let tag1 = allTags[i]
                let tag2 = allTags[j]
                
                if let pair = checkSimilarity(tag1: tag1, tag2: tag2, minSimilarity: minSimilarity) {
                    pairs.append(pair)
                }
            }
        }
        
        // 按相似度降序排序
        return pairs.sorted { $0.similarity > $1.similarity }
    }
    
    /// 检查两个标签的相似度
    private func checkSimilarity(tag1: Tag, tag2: Tag, minSimilarity: Double) -> TagSimilarityPair? {
        let name1 = tag1.name.lowercased()
        let name2 = tag2.name.lowercased()
        
        // 1. 完全相同 (大小写不同)
        if name1 == name2 && tag1.name != tag2.name {
            return TagSimilarityPair(tag1: tag1, tag2: tag2, similarity: 1.0, reason: .editDistance)
        }
        
        // 2. 同义词检测
        if areSynonyms(name1, name2) {
            return TagSimilarityPair(tag1: tag1, tag2: tag2, similarity: 0.95, reason: .synonym)
        }
        
        // 3. 包含关系
        if name1.contains(name2) || name2.contains(name1) {
            let longer = max(name1.count, name2.count)
            let shorter = min(name1.count, name2.count)
            let ratio = Double(shorter) / Double(longer)
            if ratio >= 0.5 {
                return TagSimilarityPair(tag1: tag1, tag2: tag2, similarity: 0.85, reason: .contains)
            }
        }
        
        // 4. 前缀/后缀相同 (至少 3 个字符)
        let commonPrefix = name1.commonPrefix(with: name2)
        if commonPrefix.count >= 3 {
            let similarity = Double(commonPrefix.count) / Double(max(name1.count, name2.count))
            if similarity >= 0.6 {
                return TagSimilarityPair(tag1: tag1, tag2: tag2, similarity: similarity, reason: .prefix)
            }
        }
        
        // 5. 编辑距离 (Levenshtein)
        let distance = levenshteinDistance(name1, name2)
        let maxLen = max(name1.count, name2.count)
        if maxLen > 0 {
            let similarity = 1.0 - Double(distance) / Double(maxLen)
            if similarity >= minSimilarity {
                return TagSimilarityPair(tag1: tag1, tag2: tag2, similarity: similarity, reason: .editDistance)
            }
        }
        
        return nil
    }
    
    /// 检查是否为同义词
    private func areSynonyms(_ word1: String, _ word2: String) -> Bool {
        for group in synonyms {
            let lowercaseGroup = group.map { $0.lowercased() }
            if lowercaseGroup.contains(word1) && lowercaseGroup.contains(word2) {
                return true
            }
        }
        return false
    }
    
    /// Levenshtein 编辑距离算法
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
                    dp[i-1][j] + 1,      // 删除
                    dp[i][j-1] + 1,      // 插入
                    dp[i-1][j-1] + cost  // 替换
                )
            }
        }
        
        return dp[m][n]
    }
    
    // MARK: - Merge Tags
    
    /// 合并标签 (将 fromTag 合并到 toTag)
    func mergeTags(from fromTag: Tag, to toTag: Tag) async -> Bool {
        let database = DatabaseManager.shared
        
        // 1. 获取使用 fromTag 的所有文件
        let files = await database.getFilesWithTag(fromTag)
        
        // 2. 为这些文件添加 toTag (如果还没有)
        for file in files {
            if !file.tags.contains(where: { $0.id == toTag.id }) {
                await database.addTagToFile(tagId: toTag.id, fileId: file.id)
            }
        }
        
        // 3. 从所有文件中移除 fromTag
        for file in files {
            await database.removeTagFromFile(tagId: fromTag.id, fileId: file.id)
        }
        
        // 4. 删除 fromTag
        await database.deleteTag(fromTag)
        
        Logger.success("标签合并完成: '\(fromTag.name)' → '\(toTag.name)', 影响 \(files.count) 个文件")
        
        return true
    }
    
    /// 批量合并标签
    func batchMergeTags(pairs: [TagSimilarityPair]) async -> (success: Int, failed: Int) {
        var successCount = 0
        var failedCount = 0
        
        for pair in pairs {
            let result = await mergeTags(from: pair.suggestedMerge, to: pair.suggestedKeep)
            if result {
                successCount += 1
            } else {
                failedCount += 1
            }
        }
        
        return (successCount, failedCount)
    }
}
