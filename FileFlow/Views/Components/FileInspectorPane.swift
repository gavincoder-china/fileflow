//
//  FileInspectorPane.swift
//  FileFlow
//
//  Created for Eagle-style Layout
//

import SwiftUI

struct FileInspectorPane: View {
    let file: ManagedFile
    let onClose: () -> Void
    let onUpdateTags: ([Tag]) -> Void
    let onOpenReader: () -> Void
    
    // Local State
    @State private var notes: String = ""
    @State private var isEditingTags = false
    @State private var isGeneratingCard = false
    @State private var cardGenerated = false
    @State private var contextRecommendations: [ContextRecommendation] = []
    @State private var isLoadingRecommendations = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("详细信息")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    VStack(spacing: 12) {
                        RichFileIcon(path: file.newPath)
                            .frame(width: 120, height: 120)
                            .shadow(radius: 8)
                        
                        Text(file.newName.isEmpty ? file.originalName : file.newName)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        Text("信息")
                            .font(.headline)
                        
                        InfoRow(label: "大小", value: file.formattedFileSize)
                        InfoRow(label: "类型", value: (file.originalPath as NSString).pathExtension.uppercased())
                        InfoRow(label: "创建", value: file.importedAt.formatted(date: .abbreviated, time: .shortened))
                        InfoRow(label: "分类", value: file.category.displayName)
                        if let sub = file.subcategory {
                            InfoRow(label: "子文件夹", value: sub)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("标签")
                                .font(.headline)
                            Spacer()
                            Button {
                                // Trigger global tag manager or sheet
                                // For now we simulates edit
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if file.tags.isEmpty {
                            Text("无标签")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(file.tags) { tag in
                                    Text("#\(tag.name)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(tag.swiftUIColor.opacity(0.1))
                                        .foregroundStyle(tag.swiftUIColor)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            onOpenReader()
                        } label: {
                            Label("全屏阅读", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // AI Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI 助手")
                            .font(.headline)
                        
                        Button {
                            // TODO: Summarize
                        } label: {
                            Label("生成摘要", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            generateCardForFile()
                        } label: {
                            HStack {
                                if isGeneratingCard {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 16, height: 16)
                                } else if cardGenerated {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "rectangle.stack.badge.plus")
                                }
                                Text(cardGenerated ? "已生成卡片" : "生成知识卡片")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(cardGenerated ? Color.green.opacity(0.1) : Color.purple.opacity(0.1))
                            .foregroundStyle(cardGenerated ? .green : .purple)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGeneratingCard)
                    }
                    .padding(.horizontal, 20)
                    
                    // Context Recommendations (相关文件推荐)
                    if !contextRecommendations.isEmpty || isLoadingRecommendations {
                        Divider()
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("相关文件")
                                    .font(.headline)
                                if isLoadingRecommendations {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                            }
                            
                            if contextRecommendations.isEmpty && isLoadingRecommendations {
                                Text("正在分析...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(contextRecommendations.prefix(5)) { rec in
                                    RecommendationRow(recommendation: rec)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            notes = file.notes ?? ""
            checkExistingCard()
        }
        .task {
            // 自动更新文件访问时间 (无感生命周期追踪)
            await DatabaseManager.shared.updateLastAccessedAt(fileId: file.id)
            await checkExistingCardAsync()
            await loadContextRecommendations()
        }
    }
    
    // MARK: - Context Recommendations
    private func loadContextRecommendations() async {
        isLoadingRecommendations = true
        let recommendations = await KnowledgeLinkService.shared.getContextRecommendations(for: file, limit: 5)
        await MainActor.run {
            contextRecommendations = recommendations
            isLoadingRecommendations = false
        }
    }
    
    // MARK: - Card Generation
    private func checkExistingCard() {
        Task {
            await checkExistingCardAsync()
        }
    }
    
    private func checkExistingCardAsync() async {
        let existing = await KnowledgeLinkService.shared.getCard(for: file.id)
        await MainActor.run {
            cardGenerated = existing != nil
        }
    }
    
    private func generateCardForFile() {
        guard !isGeneratingCard else { return }
        
        isGeneratingCard = true
        Task {
            let card = await KnowledgeLinkService.shared.generateCardWithAI(for: file)
            await MainActor.run {
                isGeneratingCard = false
                cardGenerated = card != nil
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct RecommendationRow: View {
    let recommendation: ContextRecommendation
    
    var body: some View {
        HStack(spacing: 8) {
            // File icon
            RichFileIcon(path: recommendation.file.newPath)
                .frame(width: 24, height: 24)
            
            // File name
            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.file.displayName)
                    .font(.caption)
                    .lineLimit(1)
                
                Text(recommendation.reason.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Relevance score
            Text("\(Int(recommendation.score * 100))%")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }
}
