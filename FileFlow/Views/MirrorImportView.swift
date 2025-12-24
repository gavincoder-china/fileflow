import SwiftUI

/// Mirror Import View: Preserve original folder structure, user picks parent category.
struct MirrorImportView: View {
    let fileURLs: [URL]
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    // User selections
    @State private var selectedCategory: PARACategory = .resources
    @State private var selectedSubcategoryId: UUID?
    @State private var runAITagging: Bool = true
    
    // All subcategories for path display
    @State private var allSubcategories: [Subcategory] = []
    
    // Processing state
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var processingStatus = ""
    
    // Detected folder structure
    @State private var rootFolderName: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("镜像导入")
                        .font(.headline)
                    Text("保留原始目录结构导入到指定位置")
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
                    
                    // AI Tagging Option
                    Toggle(isOn: $runAITagging) {
                        VStack(alignment: .leading) {
                            Text("启用 AI 智能标签")
                                .font(.headline)
                            Text("导入后在后台自动分析文件并添加标签")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(12)
                    
                    // Files/Folders Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("文件预览")
                            .font(.headline)
                        
                        // Show detected structure
                        if let rootName = rootFolderName {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(rootName)
                                    .fontWeight(.medium)
                                Text("(将作为子文件夹)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        ForEach(fileURLs.prefix(10), id: \.absoluteString) { url in
                            HStack(spacing: 12) {
                                Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(url.hasDirectoryPath ? .blue : .secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }
                        
                        if fileURLs.count > 10 {
                            Text("... 还有 \(fileURLs.count - 10) 个文件/文件夹")
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
                
                Button("开始导入") {
                    startMirrorImport()
                }
                .buttonStyle(GlassButtonStyle(isActive: true))
                .disabled(isProcessing)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .task {
            allSubcategories = await DatabaseManager.shared.getAllSubcategories()
            detectFolderStructure()
        }
    }
    
    private func detectFolderStructure() {
        // Detect if we're importing a folder (common root)
        // This helps preserve folder structure
        if let firstURL = fileURLs.first {
            let parent = firstURL.deletingLastPathComponent().lastPathComponent
            // Check if all files share the same parent
            let allSameParent = fileURLs.allSatisfy {
                $0.deletingLastPathComponent().lastPathComponent == parent
            }
            if allSameParent && parent != "/" && parent != "Desktop" && parent != "Downloads" {
                rootFolderName = parent
            }
        }
    }
    
    private func startMirrorImport() {
        isProcessing = true
        processedCount = 0
        
        // Calculate base path for subcategory
        let basePath: String = {
            if let subId = selectedSubcategoryId,
               let sub = allSubcategories.first(where: { $0.id == subId }) {
                return sub.fullPath(allSubcategories: allSubcategories)
            }
            return ""
        }()
        
        Task {
            if let rootName = rootFolderName {
                // Check if this subcategory already exists
                let existingSubs = await DatabaseManager.shared.getSubcategories(for: selectedCategory)
                
                // Build the full path for the new subcategory
                let newSubcategory = Subcategory(
                    name: rootName,
                    parentCategory: selectedCategory,
                    parentSubcategoryId: selectedSubcategoryId
                )
                
                // Check for existing with same name under same parent
                let exists = existingSubs.contains { sub in
                    sub.name == rootName && sub.parentSubcategoryId == selectedSubcategoryId
                }
                
                if !exists {
                    await DatabaseManager.shared.saveSubcategory(newSubcategory)
                    Logger.success("Created new subcategory: \(rootName)")
                }
            }
            
            for url in fileURLs {
                processingStatus = "导入中 \(processedCount + 1)/\(fileURLs.count)"
                
                do {
                    // Calculate relative path
                    var relativePath = basePath
                    
                    // If we detected a root folder, include it
                    if let rootName = rootFolderName {
                        if relativePath.isEmpty {
                            relativePath = rootName
                        } else {
                            relativePath = "\(relativePath)/\(rootName)"
                        }
                    }
                    
                    try await FileFlowManager.shared.organizeFileMirror(
                        url: url,
                        targetCategory: selectedCategory,
                        relativePath: relativePath,
                        runAITagging: runAITagging
                    )
                    processedCount += 1
                } catch {
                    Logger.error("Mirror import failed: \(error)")
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
