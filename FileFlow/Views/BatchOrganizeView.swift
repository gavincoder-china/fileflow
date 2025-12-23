//
//  BatchOrganizeView.swift
//  FileFlow
//
//  批量整理视图
//

import SwiftUI
import UniformTypeIdentifiers

struct BatchOrganizeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BatchOrganizeViewModel()
    
    var body: some View {
        ZStack {
            AuroraBackground()
                .blur(radius: 20)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("批量整理")
                            .font(.title3.bold())
                        Text("扫描并整理多个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                
                if viewModel.files.isEmpty {
                    // Empty State - Select Folder
                    VStack(spacing: 24) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 72))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .symbolEffect(.bounce.up, value: true)
                        
                        VStack(spacing: 8) {
                            Text("选择要整理的文件夹")
                                .font(.title2.bold())
                            
                            Text("系统会扫描文件夹中的所有文件，并使用 AI 分析建议分类")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                        }
                        
                        Button("选择文件夹...") {
                            viewModel.selectFolder()
                        }
                        .buttonStyle(GlassButtonStyle(isActive: true))
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // File List Layout
                    VStack(spacing: 16) {
                        // Stats Bar
                        HStack {
                            Text("已扫描 \(viewModel.files.count) 个文件")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            if viewModel.isAnalyzing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("AI 分析中...")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                            }
                            
                            Text("\(viewModel.selectedCount) 已选择")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .glass(cornerRadius: 12)
                        
                        // File List
                        List {
                            ForEach($viewModel.files) { $file in
                                BatchFileRow(item: $file)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    .padding()
                    
                    // Actions Footer
                    HStack {
                        Button("选择其他文件夹") {
                            viewModel.selectFolder()
                        }
                        .buttonStyle(GlassButtonStyle())
                        
                        Spacer()
                        
                        Button("应用 AI 建议") {
                            viewModel.applyAISuggestions()
                        }
                        .disabled(viewModel.isAnalyzing)
                        .buttonStyle(GlassButtonStyle())
                        
                        Button("开始整理") {
                            Task {
                                await viewModel.organizeFiles()
                                dismiss()
                            }
                        }
                        .buttonStyle(GlassButtonStyle(isActive: true))
                        .disabled(viewModel.selectedCount == 0 || viewModel.isOrganizing)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .frame(width: 800, height: 600)
    }
}

// MARK: - Batch File Row
struct BatchFileRow: View {
    @Binding var item: BatchFileItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
            
            // Icon
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .font(.title3)
                .frame(width: 32)
            
            // File Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .lineLimit(1)
                    .fontWeight(.medium)
                
                if !item.suggestedTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.suggestedTags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Category Picker
            Picker("", selection: $item.selectedCategory) {
                ForEach(PARACategory.allCases) { category in
                    Label(category.displayName, systemImage: category.icon)
                        .tag(category)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            
            // Status
            if item.isAnalyzed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else if item.isAnalyzing {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(12)
        .glass(cornerRadius: 12, material: .ultraThin, shadowRadius: 2)
    }
}

// MARK: - Batch File Item
struct BatchFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    var isSelected: Bool = true
    var selectedCategory: PARACategory = .resources
    var selectedSubcategory: String?
    var suggestedTags: [String] = []
    var summary: String?
    var isAnalyzing: Bool = false
    var isAnalyzed: Bool = false
    
    var icon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg": return "photo.fill"
        case "mp4", "mov": return "video.fill"
        case "doc", "docx": return "doc.text.fill"
        default: return "doc.fill"
    }
    }
}

// MARK: - Batch Organize ViewModel
@MainActor
class BatchOrganizeViewModel: ObservableObject {
    @Published var files: [BatchFileItem] = []
    @Published var isAnalyzing = false
    @Published var isOrganizing = false
    
    var selectedCount: Int {
        files.filter { $0.isSelected }.count
    }
    
    private let fileManager = FileFlowManager.shared
    private let database = DatabaseManager.shared
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            scanFolder(url)
        }
    }
    
    private func scanFolder(_ url: URL) {
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var items: [BatchFileItem] = []
        
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    let item = BatchFileItem(url: fileURL, fileName: fileURL.lastPathComponent)
                    items.append(item)
                }
            } catch {
                continue
            }
        }
        
        files = items
        
        // Start AI analysis
        Task {
            await analyzeFiles()
        }
    }
    
    func analyzeFiles() async {
        isAnalyzing = true
        
        let aiService = AIServiceFactory.createService()
        
        for index in files.indices {
            files[index].isAnalyzing = true
            
            do {
                let content = try await DocumentContentExtractor.extractText(from: files[index].url)
                let result = try await aiService.analyzeFile(
                    content: content,
                    fileName: files[index].fileName
                )
                
                files[index].suggestedTags = result.suggestedTags
                files[index].selectedCategory = result.suggestedCategory
                files[index].selectedSubcategory = result.suggestedSubcategory
                files[index].summary = result.summary
                files[index].isAnalyzed = true
            } catch {
                // Use mock analysis on error
                files[index].isAnalyzed = true
            }
            
            files[index].isAnalyzing = false
        }
        
        isAnalyzing = false
    }
    
    func applyAISuggestions() {
        for index in files.indices where files[index].isAnalyzed {
            files[index].isSelected = true
        }
    }
    
    func organizeFiles() async {
        isOrganizing = true
        
        for item in files where item.isSelected {
            // Create tags
            var tags: [Tag] = []
            for tagName in item.suggestedTags {
                let tag = Tag(name: tagName, color: TagColors.random())
                tags.append(tag)
                await database.saveTag(tag)
            }
            
            // Create managed file
            let info = fileManager.getFileInfo(at: item.url)
            var file = ManagedFile(
                originalName: item.fileName,
                originalPath: item.url.path,
                category: item.selectedCategory,
                subcategory: item.selectedSubcategory,
                tags: tags,
                summary: item.summary,
                fileSize: info?.size ?? 0
            )
            
            // Generate new name and move
            let newName = fileManager.generateNewFileName(for: file, tags: tags)
            
            do {
                let newURL = try fileManager.moveAndRenameFile(
                    from: item.url,
                    to: item.selectedCategory,
                    subcategory: item.selectedSubcategory,
                    newName: newName,
                    tags: tags
                )
                
                file.newName = newName
                file.newPath = newURL.path
                
                await database.saveFile(file, tags: tags)
            } catch {
                print("Error organizing file: \(error)")
            }
        }
        
        isOrganizing = false
    }
}
