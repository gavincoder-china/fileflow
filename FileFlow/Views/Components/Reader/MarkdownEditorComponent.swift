//
//  MarkdownEditorComponent.swift
//  FileFlow
//
//  Markdown 编辑与预览组件 - Typora 风格
//

import SwiftUI
import AppKit

struct MarkdownEditorComponent: View {
    let url: URL
    let file: ManagedFile
    
    @State private var content: String = ""
    @State private var isSaving = false
    @State private var lastSaved: Date?
    @State private var showSplitView = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            Divider()
            
            // Content Area
            if showSplitView {
                splitEditorView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                livePreviewView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            loadContent()
        }
    }
    
    // MARK: - Toolbar
    private var toolbarView: some View {
        HStack(spacing: 16) {
            // View Mode Toggle
            HStack(spacing: 4) {
                Button {
                    showSplitView = false
                } label: {
                    Image(systemName: "doc.richtext")
                        .padding(8)
                        .background(showSplitView ? Color.clear : Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("实时预览")
                
                Button {
                    showSplitView = true
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .padding(8)
                        .background(showSplitView ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("分栏视图")
            }
            .padding(4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            Divider().frame(height: 20)
            
            // Formatting Buttons
            HStack(spacing: 2) {
                formatButton(icon: "bold", action: { insertFormat("**", "**") })
                formatButton(icon: "italic", action: { insertFormat("*", "*") })
                formatButton(icon: "strikethrough", action: { insertFormat("~~", "~~") })
                formatButton(icon: "link", action: { insertFormat("[", "](url)") })
                formatButton(icon: "photo", action: { insertFormat("![", "](image_url)") })
            }
            
            Spacer()
            
            // Status
            if let last = lastSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("已于 \(last.formatted(date: .omitted, time: .shortened)) 保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Save Button
            Button {
                saveContent()
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("保存")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    private func formatButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
    
    private func insertFormat(_ prefix: String, _ suffix: String) {
        content += prefix + "文本" + suffix
    }
    
    // MARK: - Live Preview (Typora-like)
    private var livePreviewView: some View {
        ScrollView {
            TyporaStyleEditor(content: $content)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 60)
        }
    }
    
    // MARK: - Split View
    private var splitEditorView: some View {
        HSplitView {
            // Editor
            VStack(alignment: .leading, spacing: 0) {
                Text("编辑")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            
            // Preview
            VStack(alignment: .leading, spacing: 0) {
                Text("预览")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                ScrollView {
                    MarkdownRenderer(text: content)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.primary.opacity(0.02))
        }
    }
    
    // MARK: - Data
    private func loadContent() {
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Logger.error("无法加载 Markdown 内容: \(error)")
        }
    }
    
    private func saveContent() {
        isSaving = true
        let contentToSave = content
        let targetUrl = url
        let fileName = file.displayName
        
        Task.detached(priority: .background) {
            do {
                try contentToSave.write(to: targetUrl, atomically: true, encoding: .utf8)
                await MainActor.run {
                    isSaving = false
                    lastSaved = Date()
                    Logger.success("Markdown 已保存: \(fileName)")
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    Logger.error("保存失败: \(error)")
                }
            }
        }
    }
}

// MARK: - Typora-Style Editor
struct TyporaStyleEditor: View {
    @Binding var content: String
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) { // Changed to LazyVStack for performance
            ForEach(Array(content.components(separatedBy: "\n\n").enumerated()), id: \.offset) { index, block in
                renderBlock(block.trimmingCharacters(in: .whitespaces))
            }
        }
    }
    
    @ViewBuilder
    private func renderBlock(_ block: String) -> some View {
        let lines = block.components(separatedBy: "\n")
        
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            renderLine(line)
        }
    }
    
    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(parseInlineFormatting(String(line.dropFirst(2))))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.top, 12)
                .padding(.bottom, 4)
        } else if line.hasPrefix("## ") {
            Text(parseInlineFormatting(String(line.dropFirst(3))))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .padding(.top, 10)
                .padding(.bottom, 4)
                .foregroundStyle(.primary.opacity(0.9))
        } else if line.hasPrefix("### ") {
            Text(parseInlineFormatting(String(line.dropFirst(4))))
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .padding(.top, 8)
                .foregroundStyle(.primary.opacity(0.85))
        } else if line.hasPrefix("#### ") {
            Text(parseInlineFormatting(String(line.dropFirst(5))))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.body)
                    .foregroundStyle(.secondary)
                renderContentLine(String(line.dropFirst(2)))
            }
        } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || line.trimmingCharacters(in: .whitespaces).hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Spacer().frame(width: 20)
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                renderContentLine(line.replacingOccurrences(of: "    - ", with: "").replacingOccurrences(of: "    * ", with: "").trimmingCharacters(in: .whitespaces).dropFirst(2))
            }
        } else if line.hasPrefix("> ") {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 4)
                Text(parseInlineFormatting(String(line.dropFirst(2))))
                    .font(.body)
                    .italic()
                    .foregroundStyle(.secondary.opacity(0.9))
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            }
            .background(Color.orange.opacity(0.05))
            .cornerRadius(4)
        } else if !line.isEmpty {
            Text(parseInlineFormatting(line))
                .font(.system(size: 16))
                .lineSpacing(6)
                .foregroundStyle(.primary.opacity(0.9))
        }
    }
    
    @ViewBuilder
    private func renderContentLine<S: StringProtocol>(_ text: S) -> some View {
        let str = String(text)
        if str.hasPrefix("## ") {
             Text(parseInlineFormatting(String(str.dropFirst(3))))
                 .font(.system(size: 20, weight: .semibold))
        } else if str.hasPrefix("### ") {
            Text(parseInlineFormatting(String(str.dropFirst(4))))
                .font(.system(size: 18, weight: .medium))
        } else {
             Text(parseInlineFormatting(str))
                 .font(.system(size: 16))
                 .lineSpacing(6)
        }
    }
    
    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var cleanText = text
        cleanText = cleanText.replacingOccurrences(of: "**", with: "")
        cleanText = cleanText.replacingOccurrences(of: "##", with: "")
        
        do {
            let processed = text.replacingOccurrences(of: "## ", with: "")
            return try AttributedString(markdown: processed)
        } catch {
            return AttributedString(cleanText)
        }
    }
}

// MARK: - Markdown Renderer (for split view)
struct MarkdownRenderer: View {
    let text: String
    
    var body: some View {
        Text(.init(text))
            .textSelection(.enabled)
            .lineSpacing(6)
    }
}
