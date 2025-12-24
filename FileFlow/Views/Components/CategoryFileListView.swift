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
            onMove(file)
        } label: {
            Label("移动到...", systemImage: "arrow.right.square")
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
            .padding(14)
            .background(rowBackground)
            .glass(cornerRadius: 16, material: isSelected ? .regular : .ultraThin, shadowRadius: isHovering ? 6 : 0)
            .overlay(selectionOverlay)
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.spring(response: 0.3), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .draggable(file) // Enable drag-and-drop
    }
    
    // Extracted to help compiler
    private var mainContent: some View {
        HStack(spacing: 16) {
            fileIcon
            fileInfo
            Spacer()
            fileDate
            fileHoverActions
        }
    }
    
    private var fileIcon: some View {
        RichFileIcon(path: file.newPath)
            .frame(width: 48, height: 48)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.newName.isEmpty ? file.originalName : file.newName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(2)
                .allowsTightening(true)
            
            HStack(spacing: 8) {
                if let subcategory = file.subcategory {
                    Label(subcategory, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                ForEach(file.tags.prefix(3)) { tag in
                    Text("#\(tag.name)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white : tag.swiftUIColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? .white.opacity(0.2) : tag.swiftUIColor.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Text(file.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.6) : Color.gray.opacity(0.6))
            }
        }
    }
    
    private var fileDate: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(file.importedAt, style: .date)
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            Text(file.importedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.white.opacity(0.6) : Color.gray.opacity(0.6))
        }
    }
    
    @ViewBuilder
    private var fileHoverActions: some View {
        if isHovering || isSelected {
            Button {
                FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
            } label: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(isSelected ? Color.primary : Color.blue.opacity(0.8))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isSelected 
                ? Color.accentColor.opacity(0.15) // Soft accent tint
                : (isHovering ? Color.white.opacity(0.08) : Color.clear))
    }
    
    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 0)
            .allowsHitTesting(false)
    }
}
