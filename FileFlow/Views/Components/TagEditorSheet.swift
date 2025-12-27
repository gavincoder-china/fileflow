//
//  TagEditorSheet.swift
//  FileFlow
//
//  标签编辑弹窗 - 用于在详细信息面板中管理文件标签
//

import SwiftUI

struct TagEditorSheet: View {
    let file: ManagedFile
    @Binding var isPresented: Bool
    let onSave: ([Tag]) -> Void
    
    @State private var selectedTags: [Tag]
    @State private var allTags: [Tag] = []
    @State private var searchText: String = ""
    @State private var isLoading = true
    @State private var showCreateTag = false
    @State private var newTagName = ""
    @State private var newTagColor = TagColors.presets.first!
    
    init(file: ManagedFile, isPresented: Binding<Bool>, onSave: @escaping ([Tag]) -> Void) {
        self.file = file
        self._isPresented = isPresented
        self.onSave = onSave
        self._selectedTags = State(initialValue: file.tags)
    }
    
    private var filteredTags: [Tag] {
        if searchText.isEmpty {
            return allTags.filter { tag in
                !selectedTags.contains(where: { $0.id == tag.id })
            }
        }
        return allTags.filter { tag in
            tag.name.localizedCaseInsensitiveContains(searchText) &&
            !selectedTags.contains(where: { $0.id == tag.id })
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with file info
                HStack(spacing: 12) {
                    RichFileIcon(path: file.newPath)
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("编辑标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.primary.opacity(0.03))
                
                // Selected tags section
                VStack(alignment: .leading, spacing: 8) {
                    Text("已选标签")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if selectedTags.isEmpty {
                        Text("点击下方标签添加")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(selectedTags) { tag in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(tag.swiftUIColor)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                        .font(.caption)
                                    
                                    Button {
                                        withAnimation {
                                            selectedTags.removeAll { $0.id == tag.id }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tag.swiftUIColor.opacity(0.15))
                                .foregroundStyle(tag.swiftUIColor)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding()
                
                Divider()
                
                // Search and available tags
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索或创建标签", text: $searchText)
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(10)
                    
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                // Create new tag option if search text doesn't match existing
                                if !searchText.isEmpty && !allTags.contains(where: { $0.name.lowercased() == searchText.lowercased() }) {
                                    Button {
                                        createAndSelectTag()
                                    } label: {
                                        HStack {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(.blue)
                                            Text("创建「\(searchText)」")
                                                .foregroundStyle(.primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                ForEach(filteredTags) { tag in
                                    Button {
                                        withAnimation {
                                            selectedTags.append(tag)
                                        }
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(tag.swiftUIColor)
                                                .frame(width: 10, height: 10)
                                            Text(tag.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Text("\(tag.usageCount)")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.primary.opacity(0.03))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding()
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 16) {
                    Button("取消") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        onSave(selectedTags)
                        isPresented = false
                    } label: {
                        Text("保存")
                            .fontWeight(.medium)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .frame(width: 400, height: 550)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task {
            await loadTags()
        }
    }
    
    private func loadTags() async {
        let tags = await DatabaseManager.shared.getAllTags()
        await MainActor.run {
            allTags = tags
            isLoading = false
        }
    }
    
    private func createAndSelectTag() {
        let newTag = Tag(name: searchText, color: TagColors.random())
        Task {
            await DatabaseManager.shared.saveTag(newTag)
            await MainActor.run {
                allTags.append(newTag)
                selectedTags.append(newTag)
                searchText = ""
            }
        }
    }
}
