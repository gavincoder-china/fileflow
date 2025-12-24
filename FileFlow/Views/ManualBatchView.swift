import SwiftUI

/// Manual Batch View: User picks target folder and tags, AI only assists with suggestions.
struct ManualBatchView: View {
    let fileURLs: [URL]
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    // User selections
    @State private var selectedCategory: PARACategory = .projects
    @State private var selectedSubcategoryId: UUID?
    @State private var commonTagsInput: String = ""
    
    // All subcategories for path display
    @State private var allSubcategories: [Subcategory] = []
    
    // Processing state
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var processingStatus = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("手动整理 \(fileURLs.count) 个文件")
                        .font(.headline)
                    Text("选择目标位置，AI 将辅助添加标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Main Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Folder Tree Picker
                    FolderTreePicker(
                        selectedCategory: $selectedCategory,
                        selectedSubcategoryId: $selectedSubcategoryId
                    )
                    
                    // Current Selection Display
                    if let subId = selectedSubcategoryId,
                       let sub = allSubcategories.first(where: { $0.id == subId }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("目标: \(selectedCategory.displayName)/\(sub.fullPath(allSubcategories: allSubcategories))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("目标: \(selectedCategory.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Tags Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("添加公共标签")
                            .font(.headline)
                        
                        TextField("输入标签，用逗号分隔...", text: $commonTagsInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("AI 将在处理时自动为每个文件推荐更多标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // File Preview List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("待整理文件")
                            .font(.headline)
                        
                        ForEach(fileURLs.prefix(10), id: \.absoluteString) { url in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }
                        
                        if fileURLs.count > 10 {
                            Text("... 还有 \(fileURLs.count - 10) 个文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer Actions
            HStack {
                Button("取消") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(GlassButtonStyle())
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                    Text(processingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button("开始整理") {
                    startManualProcessing()
                }
                .buttonStyle(GlassButtonStyle(isActive: true))
                .disabled(isProcessing)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .task {
            allSubcategories = await DatabaseManager.shared.getAllSubcategories()
        }
    }
    
    private func startManualProcessing() {
        isProcessing = true
        processedCount = 0
        
        // Parse common tags from input
        let tagNames = commonTagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // Calculate subcategory path for file organization
        let subcategoryPath: String? = {
            guard let subId = selectedSubcategoryId,
                  let sub = allSubcategories.first(where: { $0.id == subId }) else {
                return nil
            }
            return sub.fullPath(allSubcategories: allSubcategories)
        }()
        
        Task {
            // Create/fetch tags
            var tags: [Tag] = []
            for name in tagNames {
                let existingTags = await DatabaseManager.shared.searchTags(matching: name)
                if let existing = existingTags.first(where: { $0.name.lowercased() == name.lowercased() }) {
                    tags.append(existing)
                } else {
                    let newTag = Tag(name: name, color: TagColors.random())
                    await DatabaseManager.shared.saveTag(newTag)
                    tags.append(newTag)
                }
            }
            
            for url in fileURLs {
                processingStatus = "处理中 \(processedCount + 1)/\(fileURLs.count)"
                
                do {
                    // Organize file using FileFlowManager
                    try await FileFlowManager.shared.organizeFileManually(
                        url: url,
                        category: selectedCategory,
                        subcategoryPath: subcategoryPath,
                        tags: tags
                    )
                    processedCount += 1
                } catch {
                    Logger.error("Failed to organize file: \(error)")
                    processedCount += 1
                }
            }
            
            await MainActor.run {
                onComplete()
                dismiss()
            }
        }
    }
}
