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
            // Header
            headerView
            
            // Search & Filter
            searchAndFilterBar
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    
                    // Favorites Section (Only if no search/filter active, or matches exist)
                    if searchText.isEmpty && selectedColorFilter == nil && !favoriteTags.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("常用标签", systemImage: "star.fill")
                                .font(.title3.bold())
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 4)
                            
                            FlowLayout(spacing: 12) {
                                ForEach(favoriteTags) { tag in
                                    TagManagerChip(
                                        tag: tag,
                                        isFavoriteSection: true,
                                        onToggleFavorite: { toggleFavorite(tag) },
                                        onRename: { startRename(tag) },
                                        onDelete: { confirmDelete(tag) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        
                         Divider()
                            .padding(.horizontal, 32)
                            .opacity(0.5)
                    }
                    
                    // Main Tags Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(
                                searchText.isEmpty && selectedColorFilter == nil ? "所有标签" : "搜索结果",
                                systemImage: "tag.fill"
                            )
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Text("\(filteredTags.count) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        
                        if filteredTags.isEmpty {
                            ContentUnavailableView(
                                searchText.isEmpty && selectedColorFilter == nil ? "暂无标签" : "未找到标签",
                                systemImage: "tag.slash",
                                description: Text("尝试其他条件或新建标签")
                            )
                            .frame(height: 150)
                        } else {
                            FlowLayout(spacing: 12) {
                                ForEach(filteredTags) { tag in
                                    TagManagerChip(
                                        tag: tag,
                                        isFavoriteSection: false,
                                        onToggleFavorite: { toggleFavorite(tag) },
                                        onRename: { startRename(tag) },
                                        onDelete: { confirmDelete(tag) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.vertical, 24)
            }
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.2)
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(16)
                }
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
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("标签管理")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("管理所有标签，支持收藏与筛选")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            // Settings Menu
            Menu {
                Toggle(isOn: Binding(
                    get: { appState.sidebarShowFavorites },
                    set: { newValue in
                        appState.sidebarShowFavorites = newValue
                        appState.refreshData()
                    }
                )) {
                    Label("侧边栏显示收藏", systemImage: "star.fill")
                }
                
                Divider()
                
                Text("最热标签数量: \(appState.sidebarTopTagsCount)")
                Stepper(value: Binding(
                    get: { appState.sidebarTopTagsCount },
                    set: { newValue in
                        appState.sidebarTopTagsCount = newValue
                        appState.refreshData()
                    }
                ), in: 5...50, step: 5) {
                    Text("调整数量")
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            
            Button {
                showingAddTag = true
            } label: {
                Label("新建标签", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .shadow(color: .blue.opacity(0.3), radius: 5, y: 2)
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 20)
    }
    
    // Removed sidebarConfigSection
    
    private var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Search Bar - Modern & Minimal
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                TextField("搜索标签...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(14)
            .background(.background) // Use system background for cleaner look? Or Material?
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            
            // Color Filter Rows
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" Button
                    FilterChip(
                        title: "全部",
                        color: nil,
                        isSelected: selectedColorFilter == nil,
                        action: { selectedColorFilter = nil }
                    )
                    
                    // Colors
                    ForEach(AddTagSheet.defaultColors, id: \.self) { color in
                        FilterChip(
                            title: "",
                            color: color,
                            isSelected: selectedColorFilter == color,
                            action: {
                                if selectedColorFilter == color {
                                    selectedColorFilter = nil
                                } else {
                                    selectedColorFilter = color
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4) // Space for shadow
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 10)
    }
    
    // MARK: - Actions
    
    private func toggleFavorite(_ tag: Tag) {
        // Optimistic UI update could happen here, but since efficient, waiting for DB is fine
        // provided we force a refresh.
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

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let color: Color?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(0.4), radius: 2)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .padding(.horizontal, color == nil ? 12 : 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? (color ?? .blue).opacity(color == nil ? 1.0 : 0.2) : Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? (color ?? .blue) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.2 : 1)
            )
            .foregroundStyle(isSelected && color == nil ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}



// MARK: - Tag Manager Chip (Card Style)
struct TagManagerChip: View {
    let tag: Tag
    let isFavoriteSection: Bool
    let onToggleFavorite: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Color dot with glow
            Circle()
                .fill(tag.swiftUIColor.gradient)
                .frame(width: 12, height: 12)
                .shadow(color: tag.swiftUIColor.opacity(0.6), radius: 4)
            
            // Name
            Text(tag.name)
                .font(.system(size: isFavoriteSection ? 15 : 14, weight: isFavoriteSection ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            // File count badge (only if normal tag)
            if !isFavoriteSection {
                Text("\(tag.usageCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tag.swiftUIColor.opacity(0.8))
                    .cornerRadius(6)
            }
            
            // Inline favorite button (always visible when hovering or favorited)
            if isHovering || tag.isFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: tag.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(tag.isFavorite ? .yellow : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, isFavoriteSection ? 16 : 14)
        .padding(.vertical, isFavoriteSection ? 12 : 10)
        .background(
            // Use proper frosted glass effect
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(isHovering ? 0.08 : 0.03), radius: isHovering ? 6 : 2, y: isHovering ? 3 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovering ? tag.swiftUIColor.opacity(0.6) : .white.opacity(0.15),
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.3), value: tag.isFavorite)
        .onHover { hovering in
            isHovering = hovering
        }
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
