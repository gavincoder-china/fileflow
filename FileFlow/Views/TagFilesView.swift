//
//  TagFilesView.swift
//  FileFlow
//
//  Created by Auto-Agent
//

import SwiftUI

// MARK: - Tag Files View
struct TagFilesView: View {
    let tag: Tag
    @State private var files: [ManagedFile] = []
    @State private var isLoading = true
    
    @State private var selectedFile: ManagedFile?
    
    // Reader State - using item binding
    @State private var fileForReader: ManagedFile?
    
    private let database = DatabaseManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Main Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(tag.swiftUIColor)
                            .frame(width: 24, height: 24)
                            .shadow(color: tag.swiftUIColor.opacity(0.3), radius: 8)
                        
                        Text("#\(tag.name)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                    }
                    
                    Spacer()
                    
                    Text("\(files.count) 个文件")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glass()
                }
                .padding(24)
                .padding(.top, 16)
                
                // File List
                CategoryFileListView(
                    isLoading: isLoading,
                    files: files,
                    selectedFile: $selectedFile,
                    onReveal: { file in
                        FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
                    },
                    onRename: { _ in }, // Read-only in tag view for now or implement later
                    onDuplicate: { _ in },
                    onMove: { _ in },
                    onDelete: { _ in },
                    onOpenReader: { file in
                        fileForReader = file
                    }
                )
            }
            .frame(maxWidth: .infinity)
            
            // Inspector
            if let file = selectedFile {
                Divider()
                FileInspectorPane(
                    file: file,
                    onClose: { selectedFile = nil },
                    onUpdateTags: { tags in
                        Task {
                            await FileFlowManager.shared.updateFileTags(for: file, tags: tags)
                            await loadFiles()
                        }
                    },
                    onOpenReader: {
                        fileForReader = file
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .sheet(item: $fileForReader) { file in
            UniversalReaderView(file: file)
                .frame(minWidth: 900, minHeight: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: tag.id) {
            await loadFiles()
        }
    }
    
    private func loadFiles() async {
        isLoading = true
        files = await database.getFilesWithTag(tag)
        isLoading = false
    }
}
