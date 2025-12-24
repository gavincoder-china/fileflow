//
//  FileInspectorPane.swift
//  FileFlow
//
//  Created for Eagle-style Layout
//

import SwiftUI

struct FileInspectorPane: View {
    let file: ManagedFile
    let onClose: () -> Void
    let onUpdateTags: ([Tag]) -> Void
    
    // Local State
    @State private var notes: String = ""
    @State private var isEditingTags = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("详细信息")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    VStack(spacing: 12) {
                        RichFileIcon(path: file.newPath)
                            .frame(width: 120, height: 120)
                            .shadow(radius: 8)
                        
                        Text(file.newName.isEmpty ? file.originalName : file.newName)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        Text("信息")
                            .font(.headline)
                        
                        InfoRow(label: "大小", value: file.formattedFileSize)
                        InfoRow(label: "类型", value: (file.originalPath as NSString).pathExtension.uppercased())
                        InfoRow(label: "创建", value: file.importedAt.formatted(date: .abbreviated, time: .shortened))
                        InfoRow(label: "分类", value: file.category.displayName)
                        if let sub = file.subcategory {
                            InfoRow(label: "子文件夹", value: sub)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("标签")
                                .font(.headline)
                            Spacer()
                            Button {
                                // Trigger global tag manager or sheet
                                // For now we simulates edit
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if file.tags.isEmpty {
                            Text("无标签")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(file.tags) { tag in
                                    Text("#\(tag.name)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(tag.swiftUIColor.opacity(0.1))
                                        .foregroundStyle(tag.swiftUIColor)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // AI Actions Placeholder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI 助手")
                            .font(.headline)
                        
                        Button {
                            // TODO: Summarize
                        } label: {
                            Label("生成摘要", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            notes = file.notes ?? ""
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}


