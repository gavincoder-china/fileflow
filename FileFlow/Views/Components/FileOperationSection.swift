//
//  FileOperationSection.swift
//  FileFlow
//
//  快捷操作按钮区 - Grid Layout 重构版
//

import SwiftUI
import AppKit

struct FileOperationSection: View {
    let file: ManagedFile
    var onMoveRequest: () -> Void
    var onDeleteRequest: () -> Void
    
    @State private var showCopiedFeedback = false
    
    // Grid columns
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷操作")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: columns, spacing: 10) {
                // Row 1
                OperationButton(
                    title: "移动",
                    icon: "folder.badge.gearshape",
                    color: .blue
                ) {
                    onMoveRequest()
                }
                
                OperationButton(
                    title: showCopiedFeedback ? "已复制" : "复制路径",
                    icon: showCopiedFeedback ? "checkmark.circle.fill" : "doc.on.doc",
                    color: showCopiedFeedback ? .green : .indigo
                ) {
                    copyPathToClipboard()
                }
                
                // Row 2
                OperationButton(
                    title: "Finder 中显示",
                    icon: "folder",
                    color: .orange
                ) {
                    showInFinder()
                }
                
                OperationButton(
                    title: "默认应用打开",
                    icon: "arrow.up.forward.app",
                    color: .purple
                ) {
                    openWithDefaultApp()
                }
                
                // Row 3 (Danger)
                OperationButton(
                    title: "删除",
                    icon: "trash",
                    color: .red,
                    isDanger: true
                ) {
                    onDeleteRequest()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func copyPathToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.newPath, forType: .string)
        
        withAnimation {
            showCopiedFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
    
    private func showInFinder() {
        let url = URL(fileURLWithPath: file.newPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func openWithDefaultApp() {
        let url = URL(fileURLWithPath: file.newPath)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Operation Button Component

struct OperationButton: View {
    let title: String
    let icon: String
    let color: Color
    var isDanger: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isDanger && !isHovered ? .secondary : color)
                    .frame(height: 24)
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isDanger && !isHovered ? .secondary : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .opacity(isHovered ? 0.8 : 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDanger ? Color.red.opacity(isHovered ? 0.3 : 0.0) : color.opacity(isHovered ? 0.3 : 0.0), lineWidth: 1)
            )
            // Add subtle shadow for depth
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - File Type Specific Operations

struct FileTypeOperationsSection: View {
    let file: ManagedFile
    var onOpenReader: () -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    private var fileExtension: String {
        (file.newPath as NSString).pathExtension.lowercased()
    }
    
    private var isImageFile: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(fileExtension)
    }
    
    private var isDocumentFile: Bool {
        ["pdf", "doc", "docx", "md", "txt", "rtf", "pages"].contains(fileExtension)
    }
    
    private var isVideoFile: Bool {
        ["mp4", "mov", "avi", "mkv", "webm", "m4v"].contains(fileExtension)
    }
    
    private var isAudioFile: Bool {
        ["mp3", "wav", "m4a", "aac", "flac", "ogg"].contains(fileExtension)
    }
    
    var body: some View {
        if hasTypeSpecificOperations {
            VStack(alignment: .leading, spacing: 12) {
                Text("打开")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: columns, spacing: 10) {
                    if isImageFile {
                        imageOperations
                    }
                    
                    if isDocumentFile {
                        documentOperations
                    }
                    
                    if isVideoFile || isAudioFile {
                        mediaOperations
                    }
                }
            }
        }
    }
    
    private var hasTypeSpecificOperations: Bool {
        isImageFile || isDocumentFile || isVideoFile || isAudioFile
    }
    
    @ViewBuilder
    private var imageOperations: some View {
        OperationButton(
            title: "快速预览",
            icon: "eye",
            color: .teal
        ) {
            quickLookFile()
        }
    }
    
    @ViewBuilder
    private var documentOperations: some View {
        OperationButton(
            title: "全屏阅读",
            icon: "book.pages",
            color: .teal
        ) {
            onOpenReader()
        }
    }
    
    @ViewBuilder
    private var mediaOperations: some View {
        OperationButton(
            title: "播放预览",
            icon: isVideoFile ? "play.rectangle" : "waveform",
            color: .pink
        ) {
            quickLookFile()
        }
    }
    
    private func quickLookFile() {
        let url = URL(fileURLWithPath: file.newPath)
        NSWorkspace.shared.open(url)
    }
}
