//
//  KnowledgeDiscoveryView.swift
//  FileFlow
//
//  知识发现视图
//  展示双向链接、知识卡片、上下文推荐
//

import SwiftUI

// MARK: - Knowledge Discovery View
struct KnowledgeDiscoveryView: View {
    let file: ManagedFile
    
    @State private var links: [KnowledgeLink] = []
    @State private var recommendations: [ContextRecommendation] = []
    @State private var card: KnowledgeCard?
    @State private var linkedFiles: [UUID: ManagedFile] = [:]
    @State private var selectedTab = 0
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("关联文件").tag(0)
                Text("知识卡片").tag(1)
                Text("推荐阅读").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else {
                switch selectedTab {
                case 0:
                    linksView
                case 1:
                    cardView
                case 2:
                    recommendationsView
                default:
                    linksView
                }
            }
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Links View
    private var linksView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Outgoing Links
            if !outgoingLinks.isEmpty {
                sectionHeader("📤 引用的文件", count: outgoingLinks.count)
                ForEach(outgoingLinks) { link in
                    linkRow(link, isOutgoing: true)
                }
            }
            
            // Incoming Links
            if !incomingLinks.isEmpty {
                sectionHeader("📥 被引用于", count: incomingLinks.count)
                ForEach(incomingLinks) { link in
                    linkRow(link, isOutgoing: false)
                }
            }
            
            if links.isEmpty {
                emptyState("暂无关联文件", icon: "link")
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var outgoingLinks: [KnowledgeLink] {
        links.filter { $0.sourceFileId == file.id }
    }
    
    private var incomingLinks: [KnowledgeLink] {
        links.filter { $0.targetFileId == file.id }
    }
    
    private func linkRow(_ link: KnowledgeLink, isOutgoing: Bool) -> some View {
        let linkedId = isOutgoing ? link.targetFileId : link.sourceFileId
        let linkedFile = linkedFiles[linkedId]
        
        return HStack(spacing: 12) {
            Image(systemName: link.linkType.icon)
                .foregroundStyle(link.linkType.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(linkedFile?.displayName ?? "未知文件")
                    .font(.body)
                
                HStack(spacing: 8) {
                    Text(link.linkType.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(link.linkType.color.opacity(0.1))
                        .foregroundStyle(link.linkType.color)
                        .cornerRadius(4)
                    
                    if let context = link.context {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Text(String(format: "%.0f%%", link.strength * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }
    
    // MARK: - Card View
    private var cardView: some View {
        ScrollView {
            if let card = card {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text(card.title)
                        .font(.title2.bold())
                    
                    // Key Points
                    if !card.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📌 关键要点")
                                .font(.headline)
                            
                            ForEach(card.keyPoints.indices, id: \.self) { i in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(card.keyPoints[i])
                                        .font(.body)
                                }
                            }
                        }
                    }
                    
                    // Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📝 摘要")
                            .font(.headline)
                        Text(card.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Keywords
                    if !card.keywords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🏷️ 关键词")
                                .font(.headline)
                            
                            FlowLayout(spacing: 6) {
                                ForEach(card.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    
                    // Review Info
                    HStack {
                        Text("复习次数: \(card.reviewCount)")
                        Spacer()
                        if card.needsReview {
                            Text("需要复习")
                                .foregroundStyle(.orange)
                        } else {
                            Text("下次复习: \(card.nextReviewDate.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    // Mark Reviewed Button
                    Button {
                        Task {
                            await KnowledgeLinkService.shared.markCardReviewed(card.id)
                            self.card = await KnowledgeLinkService.shared.getCard(for: file.id)
                        }
                    } label: {
                        Label("标记已复习", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    emptyState("尚未生成知识卡片", icon: "rectangle.stack")
                    
                    Button {
                        Task {
                            card = await KnowledgeLinkService.shared.generateCard(for: file)
                        }
                    } label: {
                        Label("生成知识卡片", systemImage: "plus.rectangle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Recommendations View
    private var recommendationsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if recommendations.isEmpty {
                    emptyState("暂无推荐", icon: "lightbulb")
                } else {
                    ForEach(recommendations) { rec in
                        HStack(spacing: 12) {
                            Image(systemName: rec.reason.icon)
                                .foregroundStyle(rec.reason.color)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.file.displayName)
                                    .font(.body)
                                
                                Text(rec.reason.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%.0f%%", rec.score * 100))
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .cornerRadius(4)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func emptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func loadData() async {
        isLoading = true
        
        // Load links
        links = await KnowledgeLinkService.shared.getLinks(for: file.id)
        
        // Load linked files
        let allFiles = await DatabaseManager.shared.getRecentFiles(limit: 500)
        for f in allFiles {
            linkedFiles[f.id] = f
        }
        
        // Load card
        card = await KnowledgeLinkService.shared.getCard(for: file.id)
        
        // Load recommendations
        recommendations = await KnowledgeLinkService.shared.getContextRecommendations(for: file)
        
        isLoading = false
    }
}

// MARK: - Link Type Extensions
extension KnowledgeLink.LinkType {
    var icon: String {
        switch self {
        case .reference: return "arrow.right.circle"
        case .related: return "link"
        case .derived: return "arrow.branch"
        case .parent: return "folder"
        case .sibling: return "doc.on.doc"
        }
    }
    
    var color: Color {
        switch self {
        case .reference: return .blue
        case .related: return .purple
        case .derived: return .orange
        case .parent: return .green
        case .sibling: return .teal
        }
    }
}

// MARK: - Recommendation Reason Extensions
extension ContextRecommendation.RecommendationReason {
    var icon: String {
        switch self {
        case .sameTag: return "tag"
        case .sameCategory: return "folder"
        case .contentSimilar: return "doc.text.magnifyingglass"
        case .recentlyViewed: return "clock"
        case .linkedFile: return "link"
        case .sameProject: return "folder.badge.gearshape"
        }
    }
    
    var color: Color {
        switch self {
        case .sameTag: return .blue
        case .sameCategory: return .purple
        case .contentSimilar: return .orange
        case .recentlyViewed: return .green
        case .linkedFile: return .teal
        case .sameProject: return .indigo
        }
    }
}
