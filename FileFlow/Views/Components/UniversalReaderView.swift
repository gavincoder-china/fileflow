//
//  UniversalReaderView.swift
//  FileFlow
//
//  统一阅读器/编辑器视图
//  根据文件类型分发到不同的查看组件
//

import SwiftUI

struct UniversalReaderView: View {
    let file: ManagedFile
    @Environment(\.dismiss) private var dismiss
    
    @State private var readerType: ReaderType = .unknown
    @State private var fileURL: URL?
    
    enum ReaderType {
        case pdf
        case markdown
        case code
        case text
        case image
        case quickLook
        case unknown
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Core Reader
            if let url = fileURL {
                Group {
                    switch readerType {
                    case .pdf:
                        PDFReaderComponent(url: url, file: file)
                    case .markdown:
                        MarkdownEditorComponent(url: url, file: file)
                    case .code, .text:
                        CodePreviewComponent(url: url, file: file)
                    case .image:
                        imagePreview(url)
                    case .quickLook, .unknown:
                        quickLookView(url)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("正在载入文件...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            setupReader()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Image(systemName: file.category.icon)
                .foregroundStyle(file.category.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.headline)
                Text(file.newPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
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
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Generic Previews
    private func imagePreview(_ url: URL) -> some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
        } placeholder: {
            ProgressView()
        }
    }
    
    private func quickLookView(_ url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text(file.displayName)
                .font(.headline)
            
            Text("该文件类型需要使用外部应用打开")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("在默认应用中打开", systemImage: "arrow.up.forward.app")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Logic
    private func setupReader() {
        let url = URL(fileURLWithPath: file.newPath)
        self.fileURL = url
        
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf":
            readerType = .pdf
        case "md", "markdown":
            readerType = .markdown
        case "txt", "rtf":
            readerType = .text
        case "swift", "py", "js", "html", "css", "json", "xml", "c", "cpp", "h":
            readerType = .code
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            readerType = .image
        default:
            readerType = .quickLook
        }
    }
}
