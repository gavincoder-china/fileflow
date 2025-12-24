//
//  SettingsView.swift
//  FileFlow
//
//  应用设置界面
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openaiApiKey") private var openaiApiKey = ""
    @AppStorage("openaiModel") private var openaiModel = "gpt-4o-mini"
    @AppStorage("ollamaHost") private var ollamaHost = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("autoAnalyze") private var autoAnalyze = true
    @AppStorage("fileFlowPath") private var fileFlowPath = ""
    
    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?
    
    @State private var showRebuildAlert = false
    @State private var isRebuilding = false
    @State private var rebuildMessage = ""
    
    var body: some View {
        TabView {
            // General Settings
            Form {
                Section("文件存储") {
                    LabeledContent("FileFlow 目录") {
                        HStack {
                            Text(fileFlowPath.isEmpty ? (FileFlowManager.shared.rootURL?.path ?? "未设置") : fileFlowPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .font(.system(.body, design: .monospaced))
                            
                            Button("更改...") {
                                appState.showRootSelector = true
                            }
                        }
                    }
                }
                
                Section("监控配置") {
                    LabeledContent("监控目录") {
                        HStack {
                            if let url = appState.monitoredFolder {
                                Text(url.path)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .font(.system(.body, design: .monospaced))
                                
                                Button {
                                    appState.monitoredFolder = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.gray)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("未启用")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Button("选择...") {
                                selectMonitoredFolder()
                            }
                        }
                    }
                    
                    Text("当该目录有新文件时自动提示整理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("文件命名") {
                    Toggle("包含日期前缀", isOn: .constant(true))
                        .disabled(true)
                    Toggle("包含标签后缀", isOn: .constant(true))
                        .disabled(true)
                    
                    Text("文件命名格式：YYYY-MM-DD_[分类]_[简述]_[标签].ext")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("高级") {
                    Button(action: {
                        showRebuildAlert = true
                    }) {
                        Label("重建数据库索引", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.red)
                    }
                    .alert("重建数据库索引", isPresented: $showRebuildAlert) {
                        Button("取消", role: .cancel) { }
                        Button("重建", role: .destructive) {
                            rebuildDatabase()
                        }
                    } message: {
                        Text("这将扫描根目录下的所有文件并重新建立数据库索引。现有数据将会被更新，但文件不会被删除。此操作可能需要几分钟。")
                    }
                    
                    if isRebuilding {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(rebuildMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("通用", systemImage: "gearshape")
            }
            
            // Appearance Settings
            Form {
                Section("背景壁纸") {
                    Toggle("使用 Bing 每日精选壁纸", isOn: $appState.useBingWallpaper)
                        .onChange(of: appState.useBingWallpaper) { oldValue, newValue in
                            if newValue && appState.wallpaperURL == nil {
                                appState.fetchDailyWallpaper()
                            }
                        }
                    
                    if appState.useBingWallpaper {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("透明度")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $appState.wallpaperOpacity, in: 0...1)
                            
                            Text("模糊度")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $appState.wallpaperBlur, in: 0...50)
                            
                            Toggle("启用磨砂玻璃层", isOn: $appState.showGlassOverlay)
                                .help("在壁纸上方添加一层半透明的材质（ultraThinMaterial），以增强文字的可读性。")
                                .padding(.top, 4)
                            
                            HStack {
                                Group {
                                    Button {
                                        if appState.wallpaperIndex < 7 {
                                            appState.fetchDailyWallpaper(index: appState.wallpaperIndex + 1)
                                        }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                    }
                                    .disabled(appState.wallpaperIndex >= 7)
                                    .help("查看更早的壁纸")
                                    
                                    Text(appState.wallpaperIndex == 0 ? "今天" : "\(appState.wallpaperIndex) 天前")
                                        .font(.caption)
                                        .frame(minWidth: 50)
                                    
                                    Button {
                                        if appState.wallpaperIndex > 0 {
                                            appState.fetchDailyWallpaper(index: appState.wallpaperIndex - 1)
                                        }
                                    } label: {
                                        Image(systemName: "chevron.right")
                                    }
                                    .disabled(appState.wallpaperIndex <= 0)
                                    .help("查看更新的壁纸")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Spacer()
                                
                                Button("重置今日") {
                                    appState.fetchDailyWallpaper(index: 0)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                if appState.useBingWallpaper, let url = appState.wallpaperURL {
                    Section("当前预览") {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 120)
                                .cornerRadius(8)
                        } placeholder: {
                            ProgressView()
                                .frame(height: 120)
                        }
                        
                        Text("提供商: Bing 每日精选图片")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Section("视觉风格") {
                    Text("您可以根据个人喜好开启或关闭超薄材质 (ultraThinMaterial) 叠加层。开启后会增加磨砂玻璃感，提高文字可读性；关闭后壁纸会更加清晰。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("外观", systemImage: "paintbrush")
            }
            
            // Auto Rules
            RuleConfigurationView()
                .tabItem {
                    Label("自动归档", systemImage: "bolt.fill")
                }
            
            // AI Settings
            Form {
                Section("AI 服务") {
                    Picker("提供商", selection: $aiProvider) {
                        Text("OpenAI").tag("openai")
                        Text("本地 Ollama").tag("ollama")
                        Text("禁用").tag("disabled")
                    }
                    
                    Toggle("自动分析文件", isOn: $autoAnalyze)
                }
                
                if aiProvider == "openai" {
                    Section("OpenAI 配置") {
                        SecureField("API Key", text: $openaiApiKey)
                            .font(.system(.body, design: .monospaced))
                        
                        TextField("模型名称", text: $openaiModel)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("默认使用 gpt-4o-mini，可自定义其他模型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Link("获取 API Key →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                        
                        testConnectionButton
                    }
                }
                
                if aiProvider == "ollama" {
                    Section("Ollama 配置") {
                        TextField("服务地址", text: $ollamaHost)
                            .font(.system(.body, design: .monospaced))
                        
                        TextField("模型名称", text: $ollamaModel)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("确保已安装并运行 Ollama")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Link("下载 Ollama →", destination: URL(string: "https://ollama.ai")!)
                            .font(.caption)
                        
                        testConnectionButton
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("AI", systemImage: "sparkles")
            }
            
            // About
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
                
                Text("FileFlow")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("智能文件整理系统")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Divider()
                    .padding(.vertical)
                
                VStack(spacing: 8) {
                    Text("基于 PARA 方法论")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Text("Projects · Areas · Resources · Archives")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
            .padding(40)
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
        }
        .frame(width: 550, height: 450)
    }
    private var testConnectionButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isTesting = true
                testResult = nil
                
                Task {
                    do {
                        let service = AIServiceFactory.createService()
                        let _ = try await service.testConnection()
                        testResult = (true, "连接成功")
                    } catch {
                        testResult = (false, "连接失败: \(error.localizedDescription)")
                    }
                    isTesting = false
                }
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("测试连接")
                }
            }
            .disabled(isTesting)
            
            if let result = testResult {
                HStack {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.success ? .green : .red)
                }
            }
        }
    }
    
    private func rebuildDatabase() {
        isRebuilding = true
        rebuildMessage = "正在扫描文件..."
        
        Task {
            do {
                let count = try await FileFlowManager.shared.rebuildIndex()
                
                await MainActor.run {
                    rebuildMessage = "完成！重建了 \(count) 个索引"
                    isRebuilding = false
                    
                    // Trigger refresh
                    appState.refreshData()
                    
                    // Clear success message after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        rebuildMessage = ""
                    }
                }
            } catch {
                await MainActor.run {
                    rebuildMessage = "失败: \(error.localizedDescription)"
                    isRebuilding = false
                }
            }
        }
    }
    
    private func selectMonitoredFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择要监控的文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            appState.monitoredFolder = url
        }
    }
}

/*
#Preview {
    SettingsView()
        .environmentObject(AppState())
}
*/
