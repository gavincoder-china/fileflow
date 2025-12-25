//
//  UserFeedbackService.swift
//  FileFlow
//
//  用户反馈学习服务
//  记录用户对 AI 建议的修改，学习用户偏好
//

import Foundation

// MARK: - Feedback Types
struct AIFeedback: Codable, Identifiable {
    let id: UUID
    let fileType: String           // 文件扩展名
    let aiSuggestedCategory: String
    let userSelectedCategory: String
    let aiSuggestedTags: [String]
    let userSelectedTags: [String]
    let aiSuggestedName: String?
    let userSelectedName: String?
    let timestamp: Date
    let accepted: Bool             // 用户是否接受 AI 建议
    
    init(
        fileType: String,
        aiSuggestedCategory: PARACategory,
        userSelectedCategory: PARACategory,
        aiSuggestedTags: [String],
        userSelectedTags: [String],
        aiSuggestedName: String? = nil,
        userSelectedName: String? = nil
    ) {
        self.id = UUID()
        self.fileType = fileType.lowercased()
        self.aiSuggestedCategory = aiSuggestedCategory.rawValue
        self.userSelectedCategory = userSelectedCategory.rawValue
        self.aiSuggestedTags = aiSuggestedTags
        self.userSelectedTags = userSelectedTags
        self.aiSuggestedName = aiSuggestedName
        self.userSelectedName = userSelectedName
        self.timestamp = Date()
        self.accepted = (aiSuggestedCategory == userSelectedCategory) && 
                       Set(aiSuggestedTags) == Set(userSelectedTags)
    }
}

// MARK: - User Preference
struct UserPreference: Codable {
    var fileType: String
    var preferredCategory: String
    var preferredTags: [String: Int]  // tag -> usage count
    var acceptanceRate: Double
    var sampleCount: Int
    
    init(fileType: String) {
        self.fileType = fileType
        self.preferredCategory = PARACategory.resources.rawValue
        self.preferredTags = [:]
        self.acceptanceRate = 0.0
        self.sampleCount = 0
    }
}

// MARK: - User Feedback Service
actor UserFeedbackService {
    static let shared = UserFeedbackService()
    
    private let feedbacksKey = "user_ai_feedbacks"
    private let preferencesKey = "user_preferences"
    private let maxFeedbacks = 1000
    
    private var feedbacks: [AIFeedback] = []
    private var preferences: [String: UserPreference] = [:]  // fileType -> preference
    
    private init() {
        Task { await loadData() }
    }
    
    // MARK: - Record Feedback
    
    /// 记录用户对 AI 建议的反馈
    func recordFeedback(
        fileType: String,
        aiCategory: PARACategory,
        userCategory: PARACategory,
        aiTags: [String],
        userTags: [String],
        aiName: String? = nil,
        userName: String? = nil
    ) async {
        let feedback = AIFeedback(
            fileType: fileType,
            aiSuggestedCategory: aiCategory,
            userSelectedCategory: userCategory,
            aiSuggestedTags: aiTags,
            userSelectedTags: userTags,
            aiSuggestedName: aiName,
            userSelectedName: userName
        )
        
        feedbacks.append(feedback)
        
        // 限制存储数量
        if feedbacks.count > maxFeedbacks {
            feedbacks.removeFirst(feedbacks.count - maxFeedbacks)
        }
        
        // 更新偏好
        await updatePreference(for: fileType, with: feedback)
        
        // 保存
        await saveData()
        
        Logger.info("记录用户反馈: \(fileType) → \(userCategory.rawValue) (AI: \(aiCategory.rawValue))")
    }
    
    // MARK: - Get Suggestions
    
    /// 根据用户偏好获取建议分类
    func getSuggestedCategory(for fileType: String) -> PARACategory? {
        guard let pref = preferences[fileType.lowercased()],
              pref.sampleCount >= 3 else {  // 至少 3 个样本
            return nil
        }
        
        return PARACategory(rawValue: pref.preferredCategory)
    }
    
    /// 根据用户偏好获取建议标签
    func getSuggestedTags(for fileType: String, limit: Int = 5) -> [String] {
        guard let pref = preferences[fileType.lowercased()] else {
            return []
        }
        
        return pref.preferredTags
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    /// 获取用户对 AI 建议的接受率
    func getAcceptanceRate(for fileType: String? = nil) -> Double {
        if let type = fileType {
            return preferences[type.lowercased()]?.acceptanceRate ?? 0.0
        }
        
        // 总体接受率
        guard !feedbacks.isEmpty else { return 0.0 }
        let accepted = feedbacks.filter { $0.accepted }.count
        return Double(accepted) / Double(feedbacks.count)
    }
    
    // MARK: - Statistics
    
    /// 获取用户偏好统计
    func getPreferenceStats() -> [(fileType: String, category: String, acceptance: Double, count: Int)] {
        preferences.values.map { pref in
            (pref.fileType, pref.preferredCategory, pref.acceptanceRate, pref.sampleCount)
        }
        .sorted { $0.count > $1.count }
    }
    
    /// 获取最常修正的分类
    func getMostCorrectedCategories() -> [(from: String, to: String, count: Int)] {
        var corrections: [String: Int] = [:]
        
        for feedback in feedbacks where !feedback.accepted {
            let key = "\(feedback.aiSuggestedCategory)→\(feedback.userSelectedCategory)"
            corrections[key, default: 0] += 1
        }
        
        return corrections
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { pair in
                let parts = pair.key.split(separator: "→")
                return (String(parts[0]), String(parts[1]), pair.value)
            }
    }
    
    // MARK: - Private Methods
    
    private func updatePreference(for fileType: String, with feedback: AIFeedback) async {
        let type = fileType.lowercased()
        var pref = preferences[type] ?? UserPreference(fileType: type)
        
        // 更新分类偏好 (使用最近选择)
        pref.preferredCategory = feedback.userSelectedCategory
        
        // 更新标签偏好
        for tag in feedback.userSelectedTags {
            pref.preferredTags[tag, default: 0] += 1
        }
        
        // 更新接受率
        let typeFeeds = feedbacks.filter { $0.fileType == type }
        let accepted = typeFeeds.filter { $0.accepted }.count
        pref.acceptanceRate = typeFeeds.isEmpty ? 0 : Double(accepted) / Double(typeFeeds.count)
        pref.sampleCount = typeFeeds.count
        
        preferences[type] = pref
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: feedbacksKey),
           let decoded = try? JSONDecoder().decode([AIFeedback].self, from: data) {
            feedbacks = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode([String: UserPreference].self, from: data) {
            preferences = decoded
        }
        
        Logger.info("加载用户反馈: \(feedbacks.count) 条, 偏好: \(preferences.count) 种")
    }
    
    private func saveData() async {
        if let data = try? JSONEncoder().encode(feedbacks) {
            UserDefaults.standard.set(data, forKey: feedbacksKey)
        }
        
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
    }
    
    /// 清除所有反馈数据
    func clearAllData() async {
        feedbacks.removeAll()
        preferences.removeAll()
        UserDefaults.standard.removeObject(forKey: feedbacksKey)
        UserDefaults.standard.removeObject(forKey: preferencesKey)
        Logger.info("用户反馈数据已清除")
    }
}
