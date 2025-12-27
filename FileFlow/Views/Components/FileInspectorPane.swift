//
//  FileInspectorPane.swift
//  FileFlow
//
//  详细信息操作栏 - Visual Polish Version
//

import SwiftUI
import AppKit

struct FileInspectorPane: View {
    let file: ManagedFile
    let onClose: () -> Void
    let onUpdateTags: ([Tag]) -> Void
    let onOpenReader: () -> Void
    var onFileUpdated: ((ManagedFile) -> Void)?
    var onFileDeleted: (() -> Void)?
    
    // Local State
    @State private var notes: String = ""
    @State private var summary: String = ""
    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var isEditingSummary = false
    @State private var isEditingNotes = false
    @State private var isSaving = false
    
    // Sheet states
    @State private var showTagEditor = false
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    
    // AI features
    @State private var isGeneratingCard = false
    @State private var cardGenerated = false
    @State private var isGeneratingSummary = false
    @State private var contextRecommendations: [ContextRecommendation] = []
    @State private var isLoadingRecommendations = false
    
    var body: some View {
        ZStack {
            // Background Material
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView {
                    VStack(spacing: 16) {
                        // File preview and name
                        filePreviewSection
                        
                        // Metadata Card
                        metadataSection
                        
                        // Tags Card
                        tagsSection
                        
                        // Summary & Notes Card
                        summaryNotesSection
                        
                        // File type specific operations
                        FileTypeOperationsSection(file: file, onOpenReader: onOpenReader)
                            .padding(.horizontal, 20)
                        
                        // Quick operations
                        FileOperationSection(
                            file: file,
                            onMoveRequest: { showMoveSheet = true },
                            onDeleteRequest: { showDeleteConfirmation = true }
                        )
                        .padding(.horizontal, 20)
                        
                        // AI Actions Card
                        aiActionsSection
                        
                        // Related files Card
                        if !contextRecommendations.isEmpty || isLoadingRecommendations {
                            relatedFilesSection
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(width: 320) // Slightly wider for better grid layout
        .onAppear {
            notes = file.notes ?? ""
            summary = file.summary ?? ""
            editedName = file.displayName
            checkExistingCard()
        }
        .task {
            await DatabaseManager.shared.updateLastAccessedAt(fileId: file.id)
            await checkExistingCardAsync()
            await loadContextRecommendations()
        }
        // Sheets
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(file: file, isPresented: $showTagEditor) { newTags in
                saveTagsUpdate(newTags)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveFileSheet(file: file, isPresented: $showMoveSheet) { category, subcategory in
                moveFile(to: category, subcategory: subcategory)
            }
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteConfirmationDialog(
                file: file,
                isPresented: $showDeleteConfirmation,
                onConfirm: deleteFile
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("属性与操作")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(20)
        // No background, just floating
    }
    
    // MARK: - File Preview Section
    
    private var filePreviewSection: some View {
        VStack(spacing: 16) {
            RichFileIcon(path: file.newPath)
                .frame(width: 100, height: 100)
                .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            
            // Editable file name
            if isEditingName {
                VStack(spacing: 12) {
                    TextField("文件名", text: $editedName, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .lineLimit(1...5)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.1), radius: 4)
                    
                    HStack(spacing: 12) {
                        Button("取消") {
                            editedName = file.displayName
                            isEditingName = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        
                        Button("保存") {
                            saveNameChange()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .disabled(editedName.isEmpty || editedName == file.displayName)
                    }
                }
                .padding(.horizontal, 20)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Text(file.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                    
                    Button {
                        editedName = file.displayName
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("信息")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            
            VStack(spacing: 8) {
                InfoRow(label: "大小", value: file.formattedFileSize)
                InfoRow(label: "类型", value: (file.originalPath as NSString).pathExtension.uppercased())
                InfoRow(label: "创建", value: file.importedAt.formatted(date: .abbreviated, time: .shortened))
                InfoRow(label: "分类", value: file.category.displayName)
                if let sub = file.subcategory {
                    InfoRow(label: "子文件夹", value: sub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("标签")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                
                Button {
                    showTagEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            if file.tags.isEmpty {
                Button {
                    showTagEditor = true
                } label: {
                    Text("添加标签...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(file.tags) { tag in
                        HStack(spacing: 6) {
                            Text("#\(tag.name)")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tag.swiftUIColor.opacity(0.15))
                        .foregroundStyle(tag.swiftUIColor) // darker text
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Summary & Notes Section
    
    private var summaryNotesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("摘要")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isEditingSummary {
                        Button("完成") {
                            saveSummary()
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                    }
                }
                
                if isEditingSummary {
                    TextEditor(text: $summary)
                        .font(.caption)
                        .frame(height: 80)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.05), radius: 2)
                } else {
                    Button {
                        isEditingSummary = true
                    } label: {
                        Text(summary.isEmpty ? "点击添加摘要..." : summary)
                            .font(.caption)
                            .foregroundStyle(summary.isEmpty ? .secondary : .primary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Notes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("备注")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isEditingNotes {
                        Button("完成") {
                            saveNotes()
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                    }
                }
                
                if isEditingNotes {
                    TextEditor(text: $notes)
                        .font(.caption)
                        .frame(height: 80)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.05), radius: 2)
                } else {
                    Button {
                        isEditingNotes = true
                    } label: {
                        Text(notes.isEmpty ? "点击添加备注..." : notes)
                            .font(.caption)
                            .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    // MARK: - AI Actions Section
    
    private var aiActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 助手")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                generateAISummary()
            } label: {
                HStack {
                    if isGeneratingSummary {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("AI 生成摘要")
                        .font(.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                     LinearGradient(colors: [.blue.opacity(0.1), .purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .foregroundStyle(.primary)
                .cornerRadius(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingSummary)
            
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
                        .font(.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    cardGenerated ? Color.green.opacity(0.1) : Color.purple.opacity(0.1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(cardGenerated ? Color.green.opacity(0.3) : Color.purple.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(cardGenerated ? .green : .primary)
                .cornerRadius(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingCard)
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Related Files Section
    
    private var relatedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("相关文件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Actions (Same as before)
    
    private func saveNameChange() {
        guard !editedName.isEmpty, editedName != file.displayName else {
            isEditingName = false
            return
        }
        
        isSaving = true
        Task {
            do {
                let currentExtension = (file.newPath as NSString).pathExtension
                var newFileName = editedName
                if !newFileName.hasSuffix(".\(currentExtension)") {
                    newFileName += ".\(currentExtension)"
                }
                
                let newURL = try FileFlowManager.shared.relocateFile(
                    from: URL(fileURLWithPath: file.newPath),
                    to: file.category,
                    subcategory: file.subcategory,
                    newName: newFileName
                )
                
                var updatedFile = file
                updatedFile.newName = newFileName
                updatedFile.newPath = newURL.path
                updatedFile.modifiedAt = Date()
                await DatabaseManager.shared.updateFile(updatedFile)
                
                await MainActor.run {
                    isEditingName = false
                    isSaving = false
                    onFileUpdated?(updatedFile)
                }
            } catch {
                Logger.error("Failed to rename file: \(error)")
                await MainActor.run {
                    editedName = file.displayName
                    isEditingName = false
                    isSaving = false
                }
            }
        }
    }
    
    private func saveTagsUpdate(_ newTags: [Tag]) {
        Task {
            await DatabaseManager.shared.updateTags(fileId: file.id, tags: newTags)
            await MainActor.run {
                var updatedFile = file
                updatedFile.tags = newTags
                onUpdateTags(newTags)
                onFileUpdated?(updatedFile)
            }
        }
    }
    
    private func removeTag(_ tag: Tag) {
        let newTags = file.tags.filter { $0.id != tag.id }
        saveTagsUpdate(newTags)
    }
    
    private func saveSummary() {
        Task {
            var updatedFile = file
            updatedFile.summary = summary.isEmpty ? nil : summary
            updatedFile.modifiedAt = Date()
            await DatabaseManager.shared.updateFile(updatedFile)
            
            await MainActor.run {
                isEditingSummary = false
                onFileUpdated?(updatedFile)
            }
        }
    }
    
    private func saveNotes() {
        Task {
            var updatedFile = file
            updatedFile.notes = notes.isEmpty ? nil : notes
            updatedFile.modifiedAt = Date()
            await DatabaseManager.shared.updateFile(updatedFile)
            
            await MainActor.run {
                isEditingNotes = false
                onFileUpdated?(updatedFile)
            }
        }
    }
    
    private func moveFile(to category: PARACategory, subcategory: String?) {
        Task {
            do {
                let newURL = try FileFlowManager.shared.relocateFile(
                    from: URL(fileURLWithPath: file.newPath),
                    to: category,
                    subcategory: subcategory,
                    newName: file.displayName
                )
                
                var updatedFile = file
                updatedFile.category = category
                updatedFile.subcategory = subcategory
                updatedFile.newPath = newURL.path
                updatedFile.modifiedAt = Date()
                await DatabaseManager.shared.updateFile(updatedFile)
                
                await MainActor.run {
                    onFileUpdated?(updatedFile)
                }
            } catch {
                Logger.error("Failed to move file: \(error)")
            }
        }
    }
    
    private func deleteFile() {
        Task {
            do {
                let fileURL = URL(fileURLWithPath: file.newPath)
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                await DatabaseManager.shared.deleteFile(file.id)
                
                await MainActor.run {
                    onFileDeleted?()
                    onClose()
                }
            } catch {
                Logger.error("Failed to delete file: \(error)")
            }
        }
    }
    
    // MARK: - AI Features (Same as before)
    
    private func generateAISummary() {
        isGeneratingSummary = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                isGeneratingSummary = false
                summary = "AI 摘要功能开发中... 这是一段自动生成的示例文本。"
                isEditingSummary = true
            }
        }
    }
    
    private func loadContextRecommendations() async {
        isLoadingRecommendations = true
        let recommendations = await KnowledgeLinkService.shared.getContextRecommendations(for: file, limit: 5)
        await MainActor.run {
            contextRecommendations = recommendations
            isLoadingRecommendations = false
        }
    }
    
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

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing) // Fixed width, trailing alignment
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2) // Allow some wrapping
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RecommendationRow: View {
    let recommendation: ContextRecommendation
    
    var body: some View {
        HStack(spacing: 8) {
            RichFileIcon(path: recommendation.file.newPath)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.file.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(recommendation.reason.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(Int(recommendation.score * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}
