//
//  NaturalLanguageQueryService.swift
//  FileFlow
//
//  自然语言查询解析器 - 将用户自然语言转换为结构化搜索
//

import Foundation
import NaturalLanguage

// MARK: - Query Result

struct ParsedQuery {
    var keywords: [String] = []
    var fileTypes: [String] = []
    var dateRange: (start: Date?, end: Date?) = (nil, nil)
    var categories: [PARACategory] = []
    var tags: [String] = []
    var sortOrder: SortOrder = .dateDescending
    
    enum SortOrder {
        case dateDescending, dateAscending, nameAscending, sizeDescending
    }
    
    var isEmpty: Bool {
        keywords.isEmpty && fileTypes.isEmpty && dateRange.start == nil && categories.isEmpty && tags.isEmpty
    }
}

// MARK: - Service

class NaturalLanguageQueryService {
    static let shared = NaturalLanguageQueryService()
    
    private init() {}
    
    // MARK: - Time Patterns
    
    private let timePatterns: [(pattern: String, handler: () -> (Date, Date))] = [
        ("今天", { 
            let start = Calendar.current.startOfDay(for: Date())
            return (start, Date())
        }),
        ("昨天", {
            let cal = Calendar.current
            let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
            let start = cal.startOfDay(for: yesterday)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        }),
        ("前天", {
            let cal = Calendar.current
            let day = cal.date(byAdding: .day, value: -2, to: Date())!
            let start = cal.startOfDay(for: day)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        }),
        ("这周|本周|这一周", {
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            return (start, Date())
        }),
        ("上周|上一周", {
            let cal = Calendar.current
            let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            return (lastWeekStart, thisWeekStart)
        }),
        ("这个月|本月", {
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            return (start, Date())
        }),
        ("上个月|上月", {
            let cal = Calendar.current
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart)!
            return (lastMonthStart, thisMonthStart)
        }),
        ("最近三天|近三天", {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -3, to: Date())!
            return (start, Date())
        }),
        ("最近一周|近一周", {
            let cal = Calendar.current
            let start = cal.date(byAdding: .weekOfYear, value: -1, to: Date())!
            return (start, Date())
        }),
        ("最近一个月|近一个月", {
            let cal = Calendar.current
            let start = cal.date(byAdding: .month, value: -1, to: Date())!
            return (start, Date())
        })
    ]
    
    // MARK: - File Type Patterns
    
    private let fileTypePatterns: [String: [String]] = [
        "pdf|PDF文件|PDF文档": ["pdf"],
        "图片|照片|截图|图像": ["jpg", "jpeg", "png", "gif", "webp", "heic"],
        "文档|Word|文字文件": ["doc", "docx", "txt", "md", "rtf"],
        "表格|Excel|电子表格": ["xls", "xlsx", "csv"],
        "PPT|演示文稿|幻灯片": ["ppt", "pptx", "key"],
        "视频|影片": ["mp4", "mov", "avi", "mkv"],
        "音频|音乐|录音": ["mp3", "wav", "m4a", "flac"],
        "压缩包|压缩文件": ["zip", "rar", "7z", "tar", "gz"]
    ]
    
    // MARK: - Category Patterns
    
    private let categoryPatterns: [String: PARACategory] = [
        "项目|Projects": .projects,
        "领域|Areas": .areas,
        "资源|Resources": .resources,
        "归档|Archives": .archives
    ]
    
    // MARK: - Parse Query
    
    func parse(_ query: String) -> ParsedQuery {
        var result = ParsedQuery()
        var remainingQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 提取时间范围
        for (pattern, handler) in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: remainingQuery, options: [], range: NSRange(remainingQuery.startIndex..., in: remainingQuery)) {
                let (start, end) = handler()
                result.dateRange = (start, end)
                
                // 移除已匹配的时间表达式
                if let range = Range(match.range, in: remainingQuery) {
                    remainingQuery = remainingQuery.replacingCharacters(in: range, with: "")
                }
                break
            }
        }
        
        // 2. 提取文件类型
        for (pattern, extensions) in fileTypePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: remainingQuery, options: [], range: NSRange(remainingQuery.startIndex..., in: remainingQuery)) {
                result.fileTypes.append(contentsOf: extensions)
                
                if let range = Range(match.range, in: remainingQuery) {
                    remainingQuery = remainingQuery.replacingCharacters(in: range, with: "")
                }
            }
        }
        
        // 3. 提取分类
        for (pattern, category) in categoryPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: remainingQuery, options: [], range: NSRange(remainingQuery.startIndex..., in: remainingQuery)) != nil {
                result.categories.append(category)
            }
        }
        
        // 4. 提取标签 (#xxx)
        let tagRegex = try? NSRegularExpression(pattern: "#(\\w+)", options: [])
        let tagMatches = tagRegex?.matches(in: remainingQuery, options: [], range: NSRange(remainingQuery.startIndex..., in: remainingQuery)) ?? []
        for match in tagMatches {
            if let range = Range(match.range(at: 1), in: remainingQuery) {
                result.tags.append(String(remainingQuery[range]))
            }
        }
        
        // 5. 剩余部分作为关键词
        // 移除常见的停用词
        let stopWords = ["找", "找一下", "搜索", "查找", "的", "关于", "有关", "文件", "所有"]
        let keywords = remainingQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !stopWords.contains($0) && !$0.hasPrefix("#") }
        
        result.keywords = keywords
        
        return result
    }
    
    // MARK: - Build SQL Query (for DatabaseManager)
    
    func buildSQLConditions(from parsed: ParsedQuery) -> (whereClause: String, params: [Any]) {
        var conditions: [String] = []
        var params: [Any] = []
        
        // 时间范围
        if let start = parsed.dateRange.start {
            conditions.append("imported_at >= ?")
            params.append(start.timeIntervalSince1970)
        }
        if let end = parsed.dateRange.end {
            conditions.append("imported_at <= ?")
            params.append(end.timeIntervalSince1970)
        }
        
        // 文件类型
        if !parsed.fileTypes.isEmpty {
            let placeholders = parsed.fileTypes.map { _ in "?" }.joined(separator: ", ")
            conditions.append("LOWER(file_extension) IN (\(placeholders))")
            params.append(contentsOf: parsed.fileTypes)
        }
        
        // 分类
        if !parsed.categories.isEmpty {
            let placeholders = parsed.categories.map { _ in "?" }.joined(separator: ", ")
            conditions.append("category IN (\(placeholders))")
            params.append(contentsOf: parsed.categories.map { $0.rawValue })
        }
        
        // 关键词 (FTS or LIKE)
        for keyword in parsed.keywords {
            conditions.append("(new_name LIKE ? OR original_name LIKE ? OR summary LIKE ?)")
            let likePattern = "%\(keyword)%"
            params.append(contentsOf: [likePattern, likePattern, likePattern])
        }
        
        let whereClause = conditions.isEmpty ? "1=1" : conditions.joined(separator: " AND ")
        return (whereClause, params)
    }
}

// MARK: - Preview Helper

extension NaturalLanguageQueryService {
    /// 返回人类可读的解析结果描述
    func describeQuery(_ parsed: ParsedQuery) -> String {
        var parts: [String] = []
        
        if let start = parsed.dateRange.start, let end = parsed.dateRange.end {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            parts.append("时间: \(formatter.string(from: start)) - \(formatter.string(from: end))")
        }
        
        if !parsed.fileTypes.isEmpty {
            parts.append("类型: \(parsed.fileTypes.joined(separator: ", "))")
        }
        
        if !parsed.categories.isEmpty {
            parts.append("分类: \(parsed.categories.map { $0.displayName }.joined(separator: ", "))")
        }
        
        if !parsed.tags.isEmpty {
            parts.append("标签: \(parsed.tags.map { "#\($0)" }.joined(separator: " "))")
        }
        
        if !parsed.keywords.isEmpty {
            parts.append("关键词: \(parsed.keywords.joined(separator: ", "))")
        }
        
        return parts.isEmpty ? "无特定筛选条件" : parts.joined(separator: " | ")
    }
}
