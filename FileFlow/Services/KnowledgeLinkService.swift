//
//  KnowledgeLinkService.swift
//  FileFlow
//
//  知识关联服务
//  双向链接、反向搜索、知识卡片、摘要链、上下文推荐
//

import Foundation
import NaturalLanguage

// MARK: - Knowledge Link
struct KnowledgeLink: Codable, Identifiable {
    let id: UUID
    let sourceFileId: UUID
    let targetFileId: UUID
    let linkType: LinkType
    let context: String?       // 链接上下文/引用文本
    let createdAt: Date
    var strength: Double       // 链接强度 0-1
    
    enum LinkType: String, Codable {
        case reference = "引用"       // 主动引用
        case related = "相关"         // 内容相关
        case derived = "衍生"         // 派生文件
        case parent = "父级"          // 父子关系
        case sibling = "同类"         // 同类文件
    }
    
    init(sourceId: UUID, targetId: UUID, type: LinkType, context: String? = nil, strength: Double = 0.5) {
        self.id = UUID()
        self.sourceFileId = sourceId
        self.targetFileId = targetId
        self.linkType = type
        self.context = context
        self.createdAt = Date()
        self.strength = strength
    }
}

// MARK: - Review Quality (SM-2 Style)
enum ReviewQuality: String, Codable, CaseIterable {
    case hard = "困难"
    case good = "一般"
    case easy = "简单"
    
    var intervalMultiplier: Double {
        switch self {
        case .hard: return 0.5
        case .good: return 1.0
        case .easy: return 1.5
        }
    }
    
    var icon: String {
        switch self {
        case .hard: return "tortoise.fill"
        case .good: return "checkmark.circle.fill"
        case .easy: return "hare.fill"
        }
    }
    
    var color: String {
        switch self {
        case .hard: return "red"
        case .good: return "blue"
        case .easy: return "green"
        }
    }
}

// MARK: - Knowledge Card
struct KnowledgeCard: Codable, Identifiable {
    let id: UUID
    let fileId: UUID
    let title: String
    let keyPoints: [String]
    let summary: String
    let keywords: [String]
    let createdAt: Date
    var reviewCount: Int
    var lastReviewedAt: Date?
    var easeFactor: Double  // SM-2 ease factor (默认 2.5)
    
    init(fileId: UUID, title: String, keyPoints: [String], summary: String, keywords: [String]) {
        self.id = UUID()
        self.fileId = fileId
        self.title = title
        self.keyPoints = keyPoints
        self.summary = summary
        self.keywords = keywords
        self.createdAt = Date()
        self.reviewCount = 0
        self.lastReviewedAt = nil
        self.easeFactor = 2.5
    }
    
    /// 下次复习时间 (基于艾宾浩斯曲线 + easeFactor)
    var nextReviewDate: Date {
        let baseIntervals = [1, 2, 4, 7, 15, 30, 60] // 天数
        let index = min(reviewCount, baseIntervals.count - 1)
        let baseDays = Double(baseIntervals[index])
        let adjustedDays = Int(baseDays * (easeFactor / 2.5))
        return Calendar.current.date(byAdding: .day, value: max(1, adjustedDays), to: lastReviewedAt ?? createdAt) ?? Date()
    }
    
    var needsReview: Bool {
        Date() >= nextReviewDate
    }
    
    /// 计算下次复习的预估天数
    var daysUntilReview: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: nextReviewDate).day ?? 0
        return max(0, days)
    }
}

// MARK: - Context Recommendation
struct ContextRecommendation: Identifiable {
    let id = UUID()
    let file: ManagedFile
    let reason: RecommendationReason
    let score: Double
    
    enum RecommendationReason: String {
        case sameTag = "相同标签"
        case sameCategory = "相同分类"
        case contentSimilar = "内容相似"
        case recentlyViewed = "最近查看"
        case linkedFile = "关联文件"
        case sameProject = "同一项目"
    }
}

// MARK: - Knowledge Link Service
actor KnowledgeLinkService {
    static let shared = KnowledgeLinkService()
    
    private let linksKey = "knowledge_links"
    private let cardsKey = "knowledge_cards"
    
    private var links: [KnowledgeLink] = []
    private var cards: [UUID: KnowledgeCard] = [:]  // fileId -> card
    
    private init() {
        Task { await loadData() }
    }
    
    // MARK: - 双向链接
    
    /// 创建文件之间的链接
    func createLink(from sourceId: UUID, to targetId: UUID, type: KnowledgeLink.LinkType, context: String? = nil) async -> KnowledgeLink {
        let link = KnowledgeLink(sourceId: sourceId, targetId: targetId, type: type, context: context)
        links.append(link)
        await saveData()
        
        Logger.info("创建知识链接: \(type.rawValue)")
        return link
    }
    
    /// 获取文件的所有链接 (包括出链和入链)
    func getLinks(for fileId: UUID) -> [KnowledgeLink] {
        links.filter { $0.sourceFileId == fileId || $0.targetFileId == fileId }
    }
    
    /// 获取文件的出链 (从此文件指向其他文件)
    func getOutgoingLinks(from fileId: UUID) -> [KnowledgeLink] {
        links.filter { $0.sourceFileId == fileId }
    }
    
    /// 获取文件的入链 (从其他文件指向此文件)
    func getIncomingLinks(to fileId: UUID) -> [KnowledgeLink] {
        links.filter { $0.targetFileId == fileId }
    }
    
    /// 删除链接
    func deleteLink(_ linkId: UUID) async {
        links.removeAll { $0.id == linkId }
        await saveData()
    }
    
    // MARK: - 反向搜索
    
    /// 查找提到某个关键词/主题的所有文件
    func reverseSearch(keyword: String) async -> [(file: ManagedFile, context: String)] {
        var results: [(ManagedFile, String)] = []
        
        let allFiles = await DatabaseManager.shared.getRecentFiles(limit: 1000)
        let lowerKeyword = keyword.lowercased()
        
        for file in allFiles {
            var matchContext: String? = nil
            
            // 检查文件名
            if file.displayName.lowercased().contains(lowerKeyword) {
                matchContext = "文件名包含: \(file.displayName)"
            }
            // 检查摘要
            else if let summary = file.summary?.lowercased(), summary.contains(lowerKeyword) {
                matchContext = "摘要提及"
            }
            // 检查备注
            else if let notes = file.notes?.lowercased(), notes.contains(lowerKeyword) {
                matchContext = "备注提及"
            }
            // 检查标签
            else if file.tags.contains(where: { $0.name.lowercased().contains(lowerKeyword) }) {
                matchContext = "标签匹配"
            }
            
            if let context = matchContext {
                results.append((file, context))
            }
        }
        
        Logger.info("反向搜索 '\(keyword)': 找到 \(results.count) 个结果")
        return results
    }
    
    /// 查找引用了某文件的所有文件
    func findReferencingFiles(for fileId: UUID) async -> [ManagedFile] {
        let incomingLinks = getIncomingLinks(to: fileId)
        var files: [ManagedFile] = []
        
        for link in incomingLinks {
            if let file = await getFile(by: link.sourceFileId) {
                files.append(file)
            }
        }
        
        return files
    }
    
    // MARK: - 知识卡片
    
    /// 为文件生成知识卡片
    func generateCard(for file: ManagedFile) async -> KnowledgeCard {
        // 提取关键点
        var keyPoints: [String] = []
        var keywords: [String] = []
        
        // 从标签提取关键词
        keywords.append(contentsOf: file.tags.map { $0.name })
        
        // 从摘要提取关键点
        if let summary = file.summary {
            let sentences = summary.components(separatedBy: CharacterSet(charactersIn: "。.!！?？"))
                .filter { $0.count > 5 }
                .prefix(5)
            keyPoints.append(contentsOf: sentences.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            
            // 提取关键词
            keywords.append(contentsOf: extractKeywords(from: summary))
        }
        
        let card = KnowledgeCard(
            fileId: file.id,
            title: file.displayName,
            keyPoints: keyPoints,
            summary: file.summary ?? "无摘要",
            keywords: Array(Set(keywords)).prefix(10).map { $0 }
        )
        
        cards[file.id] = card
        await saveData()
        
        Logger.info("生成知识卡片: \(file.displayName)")
        return card
    }
    
    /// 使用 AI 为文件生成知识卡片
    /// 如果文件没有摘要，会先调用 AI 分析文件内容
    /// forceRegenerate: 如果为 true，即使已有卡片也会重新生成
    func generateCardWithAI(for file: ManagedFile, forceRegenerate: Bool = false) async -> KnowledgeCard? {
        // 如果卡片已存在且不强制重新生成，直接返回
        if !forceRegenerate, let existingCard = cards[file.id] {
            return existingCard
        }
        
        var summary = forceRegenerate ? nil : file.summary  // 强制重新生成时忽略已有摘要
        var keyPoints: [String] = []
        var keywords: [String] = file.tags.map { $0.name }
        
        // 如果没有摘要或强制重新生成，使用 AI 分析文件内容
        if summary == nil || summary?.isEmpty == true {
            do {
                // 正确创建文件 URL (使用 fileURLWithPath，不是 URL(string:))
                let fileURL = URL(fileURLWithPath: file.newPath)
                
                guard FileManager.default.fileExists(atPath: file.newPath) else {
                    Logger.warning("文件不存在: \(file.newPath)")
                    return nil
                }
                
                var extractedContent: String? = nil
                
                // 尝试多模态分析 (PDF文本/图片OCR/音频转写)
                do {
                    let result = try await MultimodalAnalysisService.shared.analyzeFile(at: fileURL)
                    if let r = result {
                        extractedContent = r.extractedText
                        keywords.append(contentsOf: r.keywords)
                        Logger.success("✅ 内容提取成功 (\(r.analysisType.rawValue)): \(file.displayName), 长度: \(r.extractedText.count) 字符")
                    }
                } catch {
                    Logger.warning("内容提取失败: \(file.displayName), 错误: \(error.localizedDescription)")
                }
                
                // 检查提取的内容是否有效
                guard let content = extractedContent, !content.isEmpty, content.count > 10 else {
                    Logger.warning("未能提取有效内容: \(file.displayName), 将使用文件名分析")
                    summary = "关于 \(file.displayName) 的文件"
                    keyPoints = ["请打开原文件查看详细内容"]
                    
                    let card = KnowledgeCard(
                        fileId: file.id,
                        title: file.displayName,
                        keyPoints: keyPoints,
                        summary: summary ?? "暂无摘要",
                        keywords: Array(Set(keywords)).prefix(10).map { $0 }
                    )
                    cards[file.id] = card
                    await saveData()
                    return card
                }
                
                // RAG 风格处理: 对长内容进行分块
                let chunks = chunkContent(content, maxChunkSize: 2000)
                Logger.info("内容分块: \(chunks.count) 个块, 总长度: \(content.count) 字符")
                
                // 调用 AI 分析 (使用所有分块的摘要)
                let aiService = AIServiceFactory.createService()
                let contentForAI = chunks.prefix(3).joined(separator: "\n\n---\n\n") // 取前3个分块
                let aiResult = try await aiService.analyzeFile(content: contentForAI, fileName: file.displayName)
                
                summary = aiResult.summary
                keywords.append(contentsOf: aiResult.suggestedTags)
                
                // 生成 Q&A 风格的关键点
                keyPoints = generateKeyPoints(from: content, summary: summary)
                
                Logger.success("✅ AI 分析完成: \(file.displayName)")
                
            } catch {
                Logger.error("AI 分析失败: \(error.localizedDescription)")
                summary = "关于 \(file.displayName) 的文件"
            }
        } else {
            // 从现有摘要提取关键点
            if let summaryText = summary {
                let sentences = summaryText.components(separatedBy: CharacterSet(charactersIn: "。.!！?？"))
                    .filter { $0.count > 5 }
                    .prefix(5)
                keyPoints.append(contentsOf: sentences.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                keywords.append(contentsOf: extractKeywords(from: summaryText))
            }
        }
        
        // 创建卡片
        let card = KnowledgeCard(
            fileId: file.id,
            title: file.displayName,
            keyPoints: keyPoints.isEmpty ? ["请阅读原文件了解详情"] : keyPoints,
            summary: summary ?? "暂无摘要",
            keywords: Array(Set(keywords)).prefix(10).map { $0 }
        )
        
        cards[file.id] = card
        await saveData()
        
        Logger.success("生成知识卡片 (AI): \(file.displayName)")
        return card
    }
    
    /// 批量生成知识卡片
    func batchGenerateCards(for files: [ManagedFile], progress: @escaping (Int, Int) -> Void) async -> [KnowledgeCard] {
        var generatedCards: [KnowledgeCard] = []
        let total = files.count
        
        for (index, file) in files.enumerated() {
            progress(index + 1, total)
            
            if let card = await generateCardWithAI(for: file) {
                generatedCards.append(card)
            }
            
            // 避免 API 速率限制
            if index < total - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s 间隔
            }
        }
        
        return generatedCards
    }
    
    /// 获取所有卡片数量
    func getCardsCount() -> Int {
        cards.count
    }
    
    /// 获取文件的知识卡片
    func getCard(for fileId: UUID) -> KnowledgeCard? {
        cards[fileId]
    }
    
    /// 获取需要复习的卡片
    func getCardsForReview() -> [KnowledgeCard] {
        cards.values.filter { $0.needsReview }.sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
    
    /// 获取所有卡片（浏览模式）
    func getAllCards() -> [KnowledgeCard] {
        Array(cards.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    /// 根据文件ID获取多个卡片
    func getCards(for fileIds: [UUID]) -> [KnowledgeCard] {
        fileIds.compactMap { cards[$0] }
    }
    
    /// 标记卡片已复习 (支持质量反馈)
    func markCardReviewed(_ cardId: UUID, quality: ReviewQuality = .good) async {
        for (fileId, var card) in cards {
            if card.id == cardId {
                card.reviewCount += 1
                card.lastReviewedAt = Date()
                
                // 根据质量调整 easeFactor (SM-2 风格)
                switch quality {
                case .hard:
                    card.easeFactor = max(1.3, card.easeFactor - 0.2)
                case .good:
                    break // 保持不变
                case .easy:
                    card.easeFactor = min(3.0, card.easeFactor + 0.1)
                }
                
                cards[fileId] = card
                await saveData()
                Logger.info("📚 卡片复习完成: \(card.title) [\(quality.rawValue)] 下次: \(card.daysUntilReview)天后")
                break
            }
        }
    }
    
    /// 获取今日待复习数量
    func getTodayReviewCount() -> Int {
        cards.values.filter { $0.needsReview }.count
    }
    
    /// 获取复习统计
    func getReviewStats() -> (total: Int, reviewed: Int, pending: Int) {
        let total = cards.count
        let pending = cards.values.filter { $0.needsReview }.count
        let reviewed = cards.values.filter { $0.reviewCount > 0 }.count
        return (total, reviewed, pending)
    }
    
    // MARK: - 自动摘要链
    
    /// 生成多个文件的综合摘要
    func generateSummaryChain(for files: [ManagedFile]) async -> String {
        guard !files.isEmpty else { return "无文件可摘要" }
        
        var combinedInfo: [String] = []
        
        for file in files {
            var fileInfo = "【\(file.displayName)】"
            if let summary = file.summary {
                fileInfo += "\n\(summary)"
            }
            if !file.tags.isEmpty {
                fileInfo += "\n关键词: \(file.tags.map { $0.name }.joined(separator: ", "))"
            }
            combinedInfo.append(fileInfo)
        }
        
        // 生成综合摘要
        let overview = """
        📚 综合摘要 (\(files.count) 个文件)
        
        \(combinedInfo.joined(separator: "\n\n---\n\n"))
        
        ---
        
        🔗 共同主题: \(findCommonThemes(in: files).joined(separator: ", "))
        """
        
        Logger.info("生成摘要链: \(files.count) 个文件")
        return overview
    }
    
    /// 查找文件的共同主题
    private func findCommonThemes(in files: [ManagedFile]) -> [String] {
        var tagCounts: [String: Int] = [:]
        
        for file in files {
            for tag in file.tags {
                tagCounts[tag.name, default: 0] += 1
            }
        }
        
        return tagCounts.filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    // MARK: - RAG 内容处理
    
    /// 将长内容分块处理 (RAG 风格)
    private func chunkContent(_ content: String, maxChunkSize: Int = 2000) -> [String] {
        guard content.count > maxChunkSize else { return [content] }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        // 按段落分割（优先保持段落完整）
        let paragraphs = content.components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        for paragraph in paragraphs {
            if currentChunk.count + paragraph.count < maxChunkSize {
                currentChunk += paragraph + "\n"
            } else {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                currentChunk = paragraph + "\n"
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return chunks
    }
    
    /// 从内容和摘要生成 Q&A 风格的关键点
    private func generateKeyPoints(from content: String, summary: String?) -> [String] {
        var keyPoints: [String] = []
        
        // 1. 从摘要提取要点
        if let summaryText = summary, !summaryText.isEmpty {
            let sentences = summaryText.components(separatedBy: CharacterSet(charactersIn: "。.!！?？"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 8 }
            keyPoints.append(contentsOf: sentences.prefix(3))
        }
        
        // 2. 从原文提取核心句子（寻找含有关键词的句子）
        let keywordPatterns = ["重要", "关键", "核心", "注意", "总结", "建议", "步骤", "方法", "结论", "目的"]
        let contentSentences = content.components(separatedBy: CharacterSet(charactersIn: "。.!！?？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 10 && $0.count < 100 }
        
        for sentence in contentSentences {
            if keyPoints.count >= 5 { break }
            for pattern in keywordPatterns {
                if sentence.contains(pattern) && !keyPoints.contains(sentence) {
                    keyPoints.append(sentence)
                    break
                }
            }
        }
        
        // 3. 如果关键点太少，补充前几句内容
        if keyPoints.count < 3 {
            for sentence in contentSentences.prefix(5) {
                if keyPoints.count >= 5 { break }
                if !keyPoints.contains(sentence) {
                    keyPoints.append(sentence)
                }
            }
        }
        
        return Array(keyPoints.prefix(5))
    }
    
    // MARK: - 上下文推荐
    
    /// 获取与当前文件相关的推荐
    func getContextRecommendations(for file: ManagedFile, limit: Int = 10) async -> [ContextRecommendation] {
        var recommendations: [ContextRecommendation] = []
        let allFiles = await DatabaseManager.shared.getRecentFiles(limit: 200)
        
        for otherFile in allFiles where otherFile.id != file.id {
            var score: Double = 0
            var reason: ContextRecommendation.RecommendationReason = .contentSimilar
            
            // 1. 相同标签
            let commonTags = Set(file.tags.map { $0.id }).intersection(Set(otherFile.tags.map { $0.id }))
            if !commonTags.isEmpty {
                score += Double(commonTags.count) * 0.3
                reason = .sameTag
            }
            
            // 2. 相同分类
            if file.category == otherFile.category {
                score += 0.2
                if reason != .sameTag { reason = .sameCategory }
            }
            
            // 3. 相同子分类
            if let sub1 = file.subcategory, let sub2 = otherFile.subcategory, sub1 == sub2 {
                score += 0.3
                reason = .sameProject
            }
            
            // 4. 关联文件
            if getLinks(for: file.id).contains(where: { $0.targetFileId == otherFile.id || $0.sourceFileId == otherFile.id }) {
                score += 0.5
                reason = .linkedFile
            }
            
            // 5. 最近查看
            let daysDiff = Calendar.current.dateComponents([.day], from: otherFile.lastAccessedAt, to: Date()).day ?? 100
            if daysDiff < 7 {
                score += 0.1
            }
            
            if score > 0.2 {
                recommendations.append(ContextRecommendation(file: otherFile, reason: reason, score: score))
            }
        }
        
        // 按分数排序
        return recommendations.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }
    
    // MARK: - 辅助方法
    
    private func extractKeywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var keywords: [String] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag = tag, [.noun, .verb].contains(tag) {
                let word = String(text[range])
                if word.count >= 2 {
                    keywords.append(word)
                }
            }
            return true
        }
        
        return Array(Set(keywords))
    }
    
    private func getFile(by id: UUID) async -> ManagedFile? {
        let files = await DatabaseManager.shared.getRecentFiles(limit: 1000)
        return files.first { $0.id == id }
    }
    
    // MARK: - 持久化
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: linksKey),
           let decoded = try? JSONDecoder().decode([KnowledgeLink].self, from: data) {
            links = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: cardsKey),
           let decoded = try? JSONDecoder().decode([UUID: KnowledgeCard].self, from: data) {
            cards = decoded
        }
        
        Logger.info("加载知识图谱: \(links.count) 个链接, \(cards.count) 张卡片")
    }
    
    private func saveData() async {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: linksKey)
        }
        
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: cardsKey)
        }
    }
    
    /// 获取统计信息
    func getStats() -> (links: Int, cards: Int, needsReview: Int, reviewed: Int) {
        let reviewedCount = cards.values.filter { $0.reviewCount > 0 }.count
        return (links.count, cards.count, getCardsForReview().count, reviewedCount)
    }
}
