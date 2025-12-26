import SwiftUI

struct TagManagerView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var searchText = ""
    @State private var selectedColorFilter: Color? = nil
    
    @State private var editingTag: Tag?
    @State private var newTagName: String = ""
    @State private var isRenaming = false
    @State private var isLoading = false
    @State private var showingAddTag = false
    @State private var newTag = NewTagInput()
    @State private var tagToDelete: Tag?
    @State private var showDeleteConfirm = false
    @State private var showingMergeSuggestions = false
    
    struct NewTagInput {
        var name: String = ""
        var color: Color = .blue
    }
    
    var filteredTags: [Tag] {
        var tags = appState.allTags
        
        // 1. Color Filter
        if let selectedColor = selectedColorFilter {
            // Simple color matching based on hex string prefix or close comparison
            // Since we store exact hex, we can compare exact hex or approximate.
            // For now, let's filter by the selected color "category" if possible, 
            // but since users pick specific colors, we'll try to match exact first.
            let selectedHex = selectedColor.toHex() ?? ""
            tags = tags.filter { $0.color == selectedHex }
        }
        
        // 2. Search Text
        if !searchText.isEmpty {
            tags = tags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        return tags.sorted { $0.usageCount > $1.usageCount }
    }
    
    var favoriteTags: [Tag] {
        appState.allTags.filter { $0.isFavorite }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header & Search Area
            VStack(spacing: 16) {
                // Top Action Bar
                HStack {
                    Text("标签管理")
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    // Merge Suggestions
                    Button {
                        showingMergeSuggestions = true
                    } label: {
                        Label("合并相似", systemImage: "arrow.triangle.merge")
                    }
                    .controlSize(.regular)
                    
                    // Add Tag
                    Button {
                        showingAddTag = true
                    } label: {
                        Label("新建标签", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Search & Filter
                HStack(spacing: 12) {
                    // Search Field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索标签...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Filter Divider
                    Divider().frame(height: 20)
                    
                    // Color Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button { selectedColorFilter = nil } label: {
                                Text("全部")
                                    .font(.subheadline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedColorFilter == nil ? Color.secondary.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(AddTagSheet.defaultColors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(selectedColorFilter == color ? Color.primary.opacity(0.5) : .clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        selectedColorFilter = (selectedColorFilter == color) ? nil : color
                                    }
                                    .padding(2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
                Divider()
            }
            .background(.ultraThinMaterial)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Favorites Section
                    if searchText.isEmpty && selectedColorFilter == nil && !favoriteTags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                Text("常用标签").font(.headline)
                            }
                            .padding(.horizontal, 24)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(favoriteTags) { tag in
                                    TagManagerChip(
                                        tag: tag,
                                        isFavorite: true,
                                        onToggleFavorite: { toggleFavorite(tag) },
                                        onRename: { startRename(tag) },
                                        onDelete: { confirmDelete(tag) }
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    
                    // All Tags Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(searchText.isEmpty && selectedColorFilter == nil ? "所有标签" : "搜索结果")
                                .font(.headline)
                            Spacer()
                            Text("\(filteredTags.count) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                        
                        if filteredTags.isEmpty {
                            ContentUnavailableView(
                                searchText.isEmpty && selectedColorFilter == nil ? "暂无标签" : "未找到标签",
                                systemImage: "tag.slash"
                            )
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(filteredTags) { tag in
                                    TagManagerChip(
                                        tag: tag,
                                        isFavorite: false,
                                        onToggleFavorite: { toggleFavorite(tag) },
                                        onRename: { startRename(tag) },
                                        onDelete: { confirmDelete(tag) }
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .overlay {
            if isLoading {
                ProgressView().controlSize(.large)
            }
        }
        // Sheets & Alerts
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
        .sheet(isPresented: $showingAddTag) {
            AddTagSheet(tagInput: $newTag) {
                addNewTag()
            }
        }
        .sheet(isPresented: $showingMergeSuggestions, onDismiss: {
            appState.refreshData()
        }) {
            TagMergeSuggestionView()
        }
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
                Logger.error("Rename failed: \(error)")
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

// MARK: - Tag Manager Chip (Cleaner Token Style)
struct TagManagerChip: View {
    let tag: Tag
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 8, height: 8)
            
            Text(tag.name)
                .font(.system(size: 13))
                .lineLimit(1)
            
            if !isFavorite && tag.usageCount > 0 {
                Text("\(tag.usageCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            
            if isHovering || tag.isFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: tag.isFavorite ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(tag.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isHovering ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(isHovering ? Color.secondary.opacity(0.2) : .clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hover in isHovering = hover }
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(tag.isFavorite ? "取消收藏" : "收藏", systemImage: tag.isFavorite ? "star.slash" : "star.fill")
            }
            Button(action: onRename) {
                Label("重命名", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }
}


// MARK: - Add Tag Sheet
struct AddTagSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tagInput: TagManagerView.NewTagInput
    let onSave: () -> Void
    
    static let defaultColors: [Color] = [
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
                    ForEach(Self.defaultColors, id: \.self) { color in
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
