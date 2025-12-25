//
//  CategoryFileListView.swift
//  FileFlow
//
//  Created for Eagle-style Layout
//

import SwiftUI

struct CategoryFileListView: View {
    let isLoading: Bool
    let files: [ManagedFile]
    @Binding var selectedFile: ManagedFile?
    
    // Actions
    let onReveal: (ManagedFile) -> Void
    let onRename: (ManagedFile) -> Void
    let onDuplicate: (ManagedFile) -> Void
    let onMove: (ManagedFile) -> Void
    let onDelete: (ManagedFile) -> Void
    let onOpenReader: (ManagedFile) -> Void
    
    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if files.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
        }
    }
    
    // MARK: - Subviews
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "暂无文件",
            systemImage: "folder.badge.questionmark",
            description: Text("此分类下还没有整理过的文件")
        )
        .glass(cornerRadius: 32)
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(files) { file in
                    fileRow(for: file)
                }
            }
            .padding(24)
            .padding(.bottom, 60)
        }
    }
    
    private func fileRow(for file: ManagedFile) -> some View {
        FileListRow(file: file, isSelected: selectedFile?.id == file.id)
            .onTapGesture(count: 2) {
                onOpenReader(file)
            }
            .onTapGesture {
                selectedFile = file
            }
            .contextMenu {
                fileContextActions(for: file)
            }
    }
    
    @ViewBuilder
    private func fileContextActions(for file: ManagedFile) -> some View {
        Button {
            onReveal(file)
        } label: {
            Label("在 Finder 中显示", systemImage: "folder")
        }
        
        Button {
            onRename(file)
        } label: {
            Label("重命名", systemImage: "pencil")
        }
        
        Button {
            onDuplicate(file)
        } label: {
            Label("创建副本", systemImage: "doc.on.doc")
        }
        
        Button {
            onOpenReader(file)
        } label: {
            Label("全屏阅读", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        
        Button {
            onMove(file)
        } label: {
            Label("移动到...", systemImage: "arrow.right.square")
        }
        
        Button {
            let link = "fileflow://open?id=\(file.id.uuidString)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        } label: {
            Label("复制文件链接", systemImage: "link")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete(file)
        } label: {
            Label("移到废纸篓", systemImage: "trash")
        }
    }
}

struct FileListRow: View {
    let file: ManagedFile
    let isSelected: Bool
    @State private var isHovering = false
    
    var body: some View {
        mainContent
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(selectionOverlay)
            .onHover { hovering in
                isHovering = hovering
            }
            .draggable(file) // Enable drag-and-drop
    }
    
    // Extracted to help compiler
    private var mainContent: some View {
        HStack(spacing: 12) {
            fileIcon
            fileInfo
            Spacer()
            fileDate
            fileHoverActions
        }
    }
    
    private var fileIcon: some View {
        RichFileIcon(path: file.newPath)
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var fileInfo: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(file.newName.isEmpty ? file.originalName : file.newName)
                .font(.body)
                .fontWeight(.regular)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .allowsTightening(true)
                .frame(minWidth: 120, alignment: .leading)
            
            // Chips / Metadata
            HStack(spacing: 6) {
                // Lifecycle stage badge
                if file.lifecycleStage != .active {
                    LifecycleStatusBadge(stage: file.lifecycleStage, showLabel: false, size: .mini)
                }
                
                if let subcategory = file.subcategory {
                    Label(subcategory, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                ForEach(file.tags.prefix(3)) { tag in
                    Text("#\(tag.name)")
                        .font(.caption2)
                        .foregroundStyle(tag.swiftUIColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tag.swiftUIColor.opacity(0.1))
                        .cornerRadius(3)
                }
            }
            
            // Size
            Text(file.formattedFileSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var fileDate: some View {
        Text(file.importedAt, style: .date)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    @ViewBuilder
    private var fileHoverActions: some View {
        if isHovering || isSelected {
            Button {
                FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
            } label: {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.primary : Color.blue.opacity(0.8))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected 
                ? Color.accentColor.opacity(0.15) // Subtle highlight, not solid
                : (isHovering ? Color.secondary.opacity(0.08) : Color.clear))
    }
    
    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
    }
}

// MARK: - Grid View Components

enum FileViewMode: String, CaseIterable {
    case icons = "图标"
    case list = "列表"
    
    var iconName: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct GridFileItem: View {
    let file: ManagedFile
    let isSelected: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon Area
            ZStack {
                RichFileIcon(path: file.newPath)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
            
            // Name Area
            VStack(spacing: 2) {
                Text(file.newName.isEmpty ? file.originalName : file.newName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .frame(height: 32, alignment: .top)
                
                if isHovering || isSelected {
                    Text(file.formattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 100, height: 130)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct GridFolderItem: View {
    let name: String
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon Area
            ZStack {
                Image(systemName: "folder.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.blue)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovering ? Color.blue.opacity(0.1) : Color.clear)
            )
            
            // Name Area
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(height: 32, alignment: .top)
                .padding(.horizontal, 4)
        }
        .frame(width: 100, height: 120)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
