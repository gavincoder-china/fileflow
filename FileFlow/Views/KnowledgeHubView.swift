//
//  KnowledgeHubView.swift
//  FileFlow
//
//  知识中心视图
//  整合知识发现、卡片复习、反向搜索等功能
//

import SwiftUI

struct KnowledgeHubView: View {
    @State private var selectedTab = 0
    @State private var searchQuery = ""
    @State private var reverseSearchResults: [(file: ManagedFile, context: String)] = []
    @State private var cardsForReview: [KnowledgeCard] = []
    @State private var allFiles: [ManagedFile] = []
    @State private var selectedFile: ManagedFile?
    @State private var isLoading = true
    @State private var stats: (links: Int, cards: Int, needsReview: Int, reviewed: Int) = (0, 0, 0, 0)
    
    var isEmbedded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            if !isEmbedded {
                headerView
                Divider()
            }
            
            // Tab Bar
            tabBar
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else {
                switch selectedTab {
                case 0:
                    reviewCardsView
                case 1:
                    reverseSearchView
                case 2:
                    allLinksView
                default:
                    reviewCardsView
                }
            }
        }
        .task {
            await loadData()
        }
        .sheet(item: $selectedFile) { file in
            KnowledgeDiscoveryView(file: file)
                .frame(width: 600, height: 500)
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("🧠 知识发现")
                    .font(.title2.bold())
                Text("发现隐藏的知识连接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Stats
            HStack(spacing: 16) {
                statBadge(value: stats.links, label: "链接", color: .blue)
                statBadge(value: stats.cards, label: "卡片", color: .green)
                statBadge(value: stats.needsReview, label: "待复习", color: .orange)
            }
            
            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private func statBadge(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "待复习", icon: "clock.badge", index: 0, badge: stats.needsReview)
            tabButton(title: "反向搜索", icon: "magnifyingglass", index: 1, badge: nil)
            tabButton(title: "全部链接", icon: "link", index: 2, badge: stats.links)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func tabButton(title: String, icon: String, index: Int, badge: Int?) -> some View {
        Button {
            withAnimation { selectedTab = index }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == index ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .foregroundStyle(selectedTab == index ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Review Cards View
    private var reviewCardsView: some View {
        ScrollView {
            if cardsForReview.isEmpty {
                emptyState("没有需要复习的卡片", icon: "checkmark.circle", description: "所有知识卡片都已复习过")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(cardsForReview) { card in
                        cardRow(card)
                    }
                }
                .padding()
            }
        }
    }
    
    private func cardRow(_ card: KnowledgeCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.title)
                    .font(.headline)
                Spacer()
                if card.needsReview {
                    Text("需要复习")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                }
            }
            
            Text(card.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            
            if !card.keywords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(card.keywords.prefix(5), id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }
            }
            
            HStack {
                Text("复习次数: \(card.reviewCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    Task {
                        await KnowledgeLinkService.shared.markCardReviewed(card.id)
                        await loadData()
                    }
                } label: {
                    Label("标记复习", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
    }
    
    // MARK: - Reverse Search View
    private var reverseSearchView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("输入主题或关键词...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await performReverseSearch() }
                    }
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        reverseSearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .padding()
            
            // Results
            if reverseSearchResults.isEmpty && !searchQuery.isEmpty {
                emptyState("未找到相关文件", icon: "doc.text.magnifyingglass", description: "尝试其他关键词")
            } else if reverseSearchResults.isEmpty {
                emptyState("搜索提到某主题的文件", icon: "text.magnifyingglass", description: "输入主题或关键词开始搜索")
            } else {
                List {
                    ForEach(reverseSearchResults, id: \.file.id) { result in
                        Button {
                            selectedFile = result.file
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.file.displayName)
                                        .font(.body)
                                    Text(result.context)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - All Links View
    private var allLinksView: some View {
        ScrollView {
            if allFiles.isEmpty {
                emptyState("暂无知识链接", icon: "link", description: "开始创建文件间的关联")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(allFiles.prefix(50)) { file in
                        Button {
                            selectedFile = file
                        } label: {
                            HStack {
                                Image(systemName: file.category.icon)
                                    .foregroundStyle(file.category.color)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.displayName)
                                        .font(.body)
                                    Text(file.category.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Empty State
    private func emptyState(_ title: String, icon: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Data Loading
    private func loadData() async {
        isLoading = true
        
        stats = await KnowledgeLinkService.shared.getStats()
        cardsForReview = await KnowledgeLinkService.shared.getCardsForReview()
        allFiles = await DatabaseManager.shared.getRecentFiles(limit: 100)
        
        isLoading = false
    }
    
    private func performReverseSearch() async {
        guard !searchQuery.isEmpty else { return }
        reverseSearchResults = await KnowledgeLinkService.shared.reverseSearch(keyword: searchQuery)
    }
}

// MARK: - Preview
#Preview {
    KnowledgeHubView()
        .frame(width: 700, height: 600)
}
