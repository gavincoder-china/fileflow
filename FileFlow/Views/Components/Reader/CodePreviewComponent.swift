//
//  CodePreviewComponent.swift
//  FileFlow
//
//  代码与纯文本查看组件
//

import SwiftUI

struct CodePreviewComponent: View {
    let url: URL
    let file: ManagedFile
    
    @State private var content: String = ""
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(url.pathExtension.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(4)
                
                Spacer()
                
                Button {
                    copyToClipboard()
                } label: {
                    Label(isCopied ? "已复制" : "复制代码", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.primary.opacity(0.02))
        }
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            content = "无法读取文件内容或不支持的编码。"
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }
}
