//
//  FileOrganizeSheet.swift
//  FileFlow
//
//  文件整理弹窗 - 核心交互界面
//

import SwiftUI

struct FileOrganizeSheet: View {
    let fileURL: URL
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FileOrganizeViewModel
    @State private var showingSubcategoryInput = false
    @State private var newSubcategoryName = ""
    
    init(fileURL: URL, onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onComplete = onComplete
        self.onCancel = onCancel
        self._viewModel = StateObject(wrappedValue: FileOrganizeViewModel(fileURL: fileURL))
    }
    
    var body: some View {
        ZStack {
            AuroraBackground()
                .blur(radius: 20)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("整理文件")
                        .font(.title3.bold())
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
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // File Preview Card
                        FilePreviewSection(viewModel: viewModel)
                            .padding(.horizontal)
                        
                        // AI Summary Card
                        if viewModel.isAnalyzing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("AI 正在分析文件...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .glass(cornerRadius: 12)
                            .padding(.horizontal)
                        } else if let summary = viewModel.aiSummary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("AI 摘要", systemImage: "sparkles")
                                    .font(.subheadline)
                                    .foregroundStyle(.indigo)
                                
                                Text(summary)
                                    .font(.body)
                                    .lineSpacing(4)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glass(cornerRadius: 12)
                            .padding(.horizontal)
                        }
                        
                        // Tags Card
                        TagsSection(viewModel: viewModel)
                            .padding()
                            .glass(cornerRadius: 16)
                            .padding(.horizontal)
                        
                        // Category Card
                        VStack(spacing: 16) {
                            CategorySection(
                                viewModel: viewModel,
                                showingSubcategoryInput: $showingSubcategoryInput,
                                newSubcategoryName: $newSubcategoryName
                            )
                            
                            Divider().opacity(0.3)
                            
                            FileNamePreviewSection(viewModel: viewModel)
                        }
                        .padding()
                        .glass(cornerRadius: 16)
                        .padding(.horizontal)
                        
                        // Notes Card
                        NotesSection(viewModel: viewModel)
                            .padding()
                            .glass(cornerRadius: 16)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .scrollContentBackground(.hidden)
                
                // Footer
                HStack {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                    .buttonStyle(GlassButtonStyle())
                    
                    Spacer()
                    
                    Button("保存并归档") {
                        Task {
                            await viewModel.saveFile()
                            dismiss()
                            onComplete()
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(GlassButtonStyle(isActive: true))
                    .disabled(viewModel.isSaving)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .frame(width: 650, height: 750)
        .task {
            await viewModel.loadInitialData()
        }
    }
}

// MARK: - File Preview Section
struct FilePreviewSection: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    
    var body: some View {
        HStack(spacing: 20) {
            // File Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.1), radius: 5)
                
                Image(systemName: viewModel.file.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.primary)
            }
            
            // File Info
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.file.originalName)
                    .font(.title3.width(.expanded))
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label(viewModel.file.formattedFileSize, systemImage: "doc")
                    Label(viewModel.file.fileExtension.uppercased(), systemImage: "tag")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .glass(cornerRadius: 20)
    }
}

// MARK: - Tags Section
struct TagsSection: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    @State private var tagInput = ""
    @FocusState private var isTagInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("标签", systemImage: "tag.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Selected Tags
            FlowLayout(spacing: 8) {
                ForEach(viewModel.selectedTags) { tag in
                    TagChip(tag: tag) {
                        viewModel.removeTag(tag)
                    }
                }
                
                // Tag Input
                TextField("添加标签...", text: $tagInput)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 100, maxWidth: 150)
                    .focused($isTagInputFocused)
                    .onSubmit {
                        if !tagInput.isEmpty {
                            viewModel.addTag(name: tagInput)
                            tagInput = ""
                        }
                    }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // Suggested Tags
            if !viewModel.suggestedTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("推荐标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.suggestedTags, id: \.self) { tagName in
                            Button {
                                viewModel.addTag(name: tagName)
                            } label: {
                                Text(tagName)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Recent Tags
            if !viewModel.recentTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.recentTags) { tag in
                            Button {
                                viewModel.selectTag(tag)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(tag.swiftUIColor)
                                        .frame(width: 6, height: 6)
                                    Text(tag.name)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tag Chip
struct TagChip: View {
    let tag: Tag
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 8, height: 8)
            
            Text(tag.name)
                .font(.callout)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tag.swiftUIColor.opacity(0.15))
        .cornerRadius(16)
    }
}

// MARK: - Category Section
struct CategorySection: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    @Binding var showingSubcategoryInput: Bool
    @Binding var newSubcategoryName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("分类", systemImage: "folder.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Category Picker
            HStack(spacing: 12) {
                ForEach(PARACategory.allCases) { category in
                    CategoryButton(
                        category: category,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        viewModel.selectedCategory = category
                    }
                }
            }
            
            // Subcategory
            VStack(alignment: .leading, spacing: 8) {
                Text("子目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Picker("", selection: $viewModel.selectedSubcategory) {
                        Text("无").tag(String?.none)
                        ForEach(viewModel.availableSubcategories, id: \.self) { subcategory in
                            Text(subcategory).tag(Optional(subcategory))
                        }
                    }
                    .labelsHidden()
                    
                    Button {
                        showingSubcategoryInput.toggle()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingSubcategoryInput) {
                        VStack(spacing: 12) {
                            Text("新建子目录")
                                .font(.headline)
                            TextField("名称", text: $newSubcategoryName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            HStack {
                                Button("取消") {
                                    showingSubcategoryInput = false
                                    newSubcategoryName = ""
                                }
                                Button("创建") {
                                    viewModel.createSubcategory(name: newSubcategoryName)
                                    showingSubcategoryInput = false
                                    newSubcategoryName = ""
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Category Button
struct CategoryButton: View {
    let category: PARACategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.title2)
                Text(category.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? category.color.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? category.color : .secondary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? category.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Name Preview Section
struct FileNamePreviewSection: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("文件名预览", systemImage: "pencil")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(viewModel.generatedFileName)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
        }
    }
}

// MARK: - Notes Section
struct NotesSection: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("备注 (可选)", systemImage: "note.text")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextEditor(text: $viewModel.notes)
                .font(.body)
                .frame(height: 80)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
        }
    }
}


