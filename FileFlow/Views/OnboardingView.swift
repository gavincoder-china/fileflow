//
//  OnboardingView.swift
//  FileFlow
//
//  首次启动引导视图 - 选择根目录
//

import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void
    @State private var currentStep = 0
    @State private var selectedPath: URL?
    
    private let fileManager = FileFlowManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<3) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            
            // Content
            TabView(selection: $currentStep) {
                // Step 1: Welcome
                WelcomeStep()
                    .tag(0)
                
                // Step 2: Select Root Directory
                SelectRootStep(selectedPath: $selectedPath)
                    .tag(1)
                
                // Step 3: Ready
                ReadyStep(selectedPath: selectedPath)
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("上一步") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }
                
                Spacer()
                
                if currentStep < 2 {
                    Button("下一步") {
                        if currentStep == 1 && selectedPath == nil {
                            // 必须选择目录
                            return
                        }
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && selectedPath == nil)
                } else {
                    Button("开始使用") {
                        // 保存选择的根目录
                        if let path = selectedPath {
                            fileManager.rootURL = path
                        }
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 450)
    }
}

// MARK: - Welcome Step
struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("欢迎使用 FileFlow")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("智能文件整理系统")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "square.and.arrow.down", text: "拖拽文件即可开始整理")
                FeatureRow(icon: "tag", text: "智能标签和分类建议")
                FeatureRow(icon: "folder.badge.gear", text: "基于 PARA 方法论的文件结构")
                FeatureRow(icon: "sparkles", text: "AI 辅助分析文件内容")
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            
            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Select Root Step
struct SelectRootStep: View {
    @Binding var selectedPath: URL?
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            
            Text("选择根目录")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("所有整理的文件都将保存在这个目录中")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // Explanation
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 设计理念")
                    .font(.headline)
                
                Text("""
                FileFlow 采用类似 Obsidian 的 Vault 设计：
                • 您选择一个文件夹作为「根目录」
                • 所有文件将移动（而非复制）到此目录
                • 只保留一份文件，不占用额外空间
                • 即使卸载应用，文件仍然存在
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            
            // Selected Path Display
            if let path = selectedPath {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(path.path)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 40)
            }
            
            // Select Button
            Button {
                selectDirectory()
            } label: {
                Label(selectedPath == nil ? "选择文件夹" : "更换文件夹", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            
            Spacer()
        }
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 FileFlow 根目录"
        panel.message = "选择或创建一个文件夹作为 FileFlow 的数据存储位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url
        }
    }
}

// MARK: - Ready Step
struct ReadyStep: View {
    let selectedPath: URL?
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("准备就绪！")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("FileFlow 将在以下位置创建文件夹结构")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // PARA Preview
            VStack(alignment: .leading, spacing: 0) {
                DirectoryPreviewRow(name: selectedPath?.lastPathComponent ?? "FileFlow", icon: "folder.fill", isRoot: true)
                DirectoryPreviewRow(name: "1_Projects", icon: "folder.fill", color: .blue, indent: 1)
                DirectoryPreviewRow(name: "2_Areas", icon: "folder.fill", color: .purple, indent: 1)
                DirectoryPreviewRow(name: "3_Resources", icon: "folder.fill", color: .green, indent: 1)
                DirectoryPreviewRow(name: "4_Archives", icon: "folder.fill", color: .gray, indent: 1)
                DirectoryPreviewRow(name: ".fileflow", icon: "folder.fill", color: .secondary, indent: 1, isHidden: true)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal, 60)
            
            Text(".fileflow 文件夹用于存储数据库和配置，不会影响您的文件")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
    }
}

struct DirectoryPreviewRow: View {
    let name: String
    let icon: String
    var color: Color = .primary
    var isRoot: Bool = false
    var indent: Int = 0
    var isHidden: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            if indent > 0 {
                ForEach(0..<indent, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 24)
                        .padding(.leading, 12)
                }
            }
            
            Image(systemName: icon)
                .foregroundStyle(color)
            
            Text(name)
                .font(isRoot ? .headline : .body)
                .foregroundStyle(isHidden ? .secondary : .primary)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
