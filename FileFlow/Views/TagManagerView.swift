import SwiftUI

struct TagManagerView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var searchText = ""
    @State private var editingTag: Tag?
    @State private var newTagName: String = ""
    @State private var isRenaming = false
    @State private var isLoading = false
    @State private var showingAddTag = false
    @State private var newTag = NewTagInput()
    @State private var tagToDelete: Tag?
    @State private var showDeleteConfirm = false
    
    struct NewTagInput {
        var name: String = ""
        var color: Color = .blue
    }
    
    var filteredTags: [Tag] {
        if searchText.isEmpty {
            return appState.allTags
        } else {
            return appState.allTags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("标签管理")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("管理您的所有标签，支持收藏、重命名和删除")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // Add Tag Button
                Button {
                    showingAddTag = true
                } label: {
                    Label("新建标签", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(32)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索标签...", text: $searchText)
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
            .padding(12)
            .background(.regularMaterial)
            .cornerRadius(10)
            .padding(.horizontal, 32)
            
            // Tags List
            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredTags.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "暂无标签" : "未找到标签",
                            systemImage: searchText.isEmpty ? "tag" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "整理文件时会自动创建标签" : "尝试其他搜索关键词")
                        )
                        .frame(height: 200)
                        .glass()
                    } else {
                        ForEach(filteredTags) { tag in
                            TagCard(
                                tag: tag,
                                onToggleFavorite: { toggleFavorite(tag) },
                                onRename: { startRename(tag) },
                                onDelete: { confirmDelete(tag) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.2)
                    ProgressView("正在处理...")
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(16)
                }
            }
        }
        // Rename Alert
        .alert("重命名标签", isPresented: $isRenaming) {
            TextField("新名称", text: $newTagName)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let tag = editingTag, !newTagName.isEmpty {
                    renameTag(tag, to: newTagName)
                }
            }
        } message: {
            Text("修改标签名称将同步更新所有相关文件的文件名。")
        }
        // Add Tag Sheet
        .sheet(isPresented: $showingAddTag) {
            AddTagSheet(tagInput: $newTag) {
                addNewTag()
            }
        }
        // Delete Confirmation
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let tag = tagToDelete {
                    deleteTag(tag)
                }
            }
        } message: {
            if let tag = tagToDelete {
                Text("确定要删除标签「\(tag.name)」吗？此操作不会删除关联的文件。")
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleFavorite(_ tag: Tag) {
        Task {
            await DatabaseManager.shared.toggleTagFavorite(tag)
            appState.refreshData()
        }
    }
    
    private func startRename(_ tag: Tag) {
        editingTag = tag
        newTagName = tag.name
        isRenaming = true
    }
    
    private func renameTag(_ tag: Tag, to newName: String) {
        guard newName != tag.name else { return }
        
        isLoading = true
        Task {
            do {
                try await DatabaseManager.shared.renameTag(oldTag: tag, newName: newName)
                appState.refreshData()
            } catch {
                print("Rename failed: \(error)")
            }
            isLoading = false
        }
    }
    
    private func confirmDelete(_ tag: Tag) {
        tagToDelete = tag
        showDeleteConfirm = true
    }
    
    private func deleteTag(_ tag: Tag) {
        isLoading = true
        Task {
            await DatabaseManager.shared.deleteTag(tag)
            appState.refreshData()
            isLoading = false
        }
    }
    
    private func addNewTag() {
        guard !newTag.name.isEmpty else { return }
        
        isLoading = true
        Task {
            let tag = Tag(
                name: newTag.name,
                color: newTag.color.toHex() ?? "#007AFF"
            )
            await DatabaseManager.shared.saveTag(tag)
            appState.refreshData()
            newTag = NewTagInput()
            isLoading = false
        }
    }
}

// MARK: - Tag Card
struct TagCard: View {
    let tag: Tag
    let onToggleFavorite: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Color indicator
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 16, height: 16)
                .shadow(color: tag.swiftUIColor.opacity(0.5), radius: 4)
            
            // Tag info
            VStack(alignment: .leading, spacing: 4) {
                Text(tag.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("\(tag.usageCount) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                // Favorite
                Button(action: onToggleFavorite) {
                    Image(systemName: tag.isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(tag.isFavorite ? .yellow : .gray.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(tag.isFavorite ? "取消收藏" : "收藏标签")
                
                // Rename
                Button(action: onRename) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("重命名")
                
                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("删除标签")
            }
            .opacity(isHovering ? 1 : 0.6)
        }
        .padding(16)
        .glass(cornerRadius: 12, material: .ultraThin, shadowRadius: isHovering ? 6 : 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Add Tag Sheet
struct AddTagSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tagInput: TagManagerView.NewTagInput
    let onSave: () -> Void
    
    let colorOptions: [Color] = [
        .blue, .purple, .pink, .red, .orange,
        .yellow, .green, .mint, .teal, .cyan
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("新建标签")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("标签名称")
                    .font(.headline)
                TextField("输入标签名称", text: $tagInput.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }
            
            // Color Picker
            VStack(alignment: .leading, spacing: 12) {
                Text("选择颜色")
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(colorOptions, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 40, height: 40)
                            .overlay {
                                if tagInput.color == color {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .fontWeight(.bold)
                                }
                            }
                            .shadow(color: color.opacity(0.4), radius: 4)
                            .onTapGesture {
                                tagInput.color = color
                            }
                    }
                }
            }
            
            // Preview
            HStack {
                Text("预览：")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(tagInput.color)
                        .frame(width: 12, height: 12)
                    Text(tagInput.name.isEmpty ? "标签名称" : tagInput.name)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .cornerRadius(8)
                Spacer()
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("创建") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tagInput.name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 400)
    }
}

// MARK: - Color Extension
extension Color {
    func toHex() -> String? {
        guard let components = NSColor(self).cgColor.components else { return nil }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
