//
//  SettingsView.swift
//  FileFlow
//
//  应用设置界面 - macOS 风格重构版
//  采用类似系统设置的双栏布局 (Side-by-side)
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    // Tab Selection
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "通用"
        case appearance = "外观"
        case ai = "智能服务"
        case sync = "云同步"
        case about = "关于"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .appearance: return "paintbrush.fill"
            case .ai: return "sparkles"
            case .sync: return "icloud.fill"
            case .about: return "info.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .general: return .gray
            case .appearance: return .pink
            case .ai: return .indigo
            case .sync: return .blue
            case .about: return .gray
            }
        }
    }
    
    @State private var selectedTab: SettingsTab? = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Custom Settings Sidebar
            VStack(spacing: 0) {
                List(SettingsTab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab.color.gradient)
                                .frame(width: 22, height: 22)
                            
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(tab.rawValue)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                    .tag(tab)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 200)
            .background(Color(nsColor: .controlBackgroundColor)) // Match sidebar background
            
            Divider()
            
            // Settings Detail Content
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                if let selectedTab = selectedTab {
                    switch selectedTab {
                    case .general: GeneralSettingsView()
                    case .appearance: AppearanceSettingsView()
                    case .ai: AISettingsView()
                    case .sync: SyncSettingsView()
                    case .about: AboutSettingsView()
                    }
                } else {
                    ContentUnavailableView("选择设置项", systemImage: "gear")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}



// MARK: - 1. General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("fileFlowPath") private var fileFlowPath = ""
    @State private var showRebuildAlert = false
    @State private var isRebuilding = false
    @State private var rebuildMessage = ""
    
    var body: some View {
        SettingsScrollView {
            SettingsGroup(header: "文件管理", footer: "监控文件夹中的新文件将自动提示导入到 FileFlow。") {
                // File Path
                SettingsRow(icon: "folder", title: "存储位置") {
                    HStack {
                        Text(fileFlowPath.isEmpty ? (FileFlowManager.shared.rootURL?.path ?? "未设置") : fileFlowPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        ThemeButton("更换...") {
                            appState.showRootSelector = true
                        }
                    }
                }
                
                Divider()
                
                // Monitor
                SettingsRow(icon: "eye", title: "自动监控") {
                    HStack {
                        if let url = appState.monitoredFolder {
                            Text(url.path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
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
                        
                        ThemeButton("选择...") {
                            selectMonitoredFolder()
                        }
                    }
                }
                
                Divider()
                
                // Auto Rules
                SettingsRow(title: "启用自动归档规则") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .disabled(true)
                }
            }
            
            SettingsGroup(header: "维护") {
                SettingsRow(icon: "arrow.clockwise", title: "重建索引", subtitle: "修复搜索无法找到文件的问题") {
                    ThemeButton("执行重建", role: .destructive) {
                        showRebuildAlert = true
                    }
                }
                
                if isRebuilding {
                    Divider()
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(rebuildMessage).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
                
                SettingsRow(icon: "doc.text", title: "导出日志", subtitle: "用于故障排查") {
                    ThemeButton("导出...") {
                        exportDiagnosticLogs()
                    }
                }
            }
        }
        .alert("重建数据库索引", isPresented: $showRebuildAlert) {
            Button("取消", role: .cancel) { }
            Button("重建", role: .destructive) { rebuildDatabase() }
        } message: {
            Text("这将重新扫描所有文件，可能需要几分钟时间。")
        }
    }
    
    // ... helper methods remain same
    private func rebuildDatabase() {
        isRebuilding = true
        rebuildMessage = "正在扫描..."
        Task {
            do {
                _ = try await FileFlowManager.shared.rebuildIndex()
                await MainActor.run {
                    isRebuilding = false
                    rebuildMessage = "重建完成"
                    appState.refreshData()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { rebuildMessage = "" }
                }
            } catch {
                await MainActor.run { isRebuilding = false; rebuildMessage = "" }
            }
        }
    }
    
    private func selectMonitoredFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            appState.monitoredFolder = url
        }
    }
    
    private func exportDiagnosticLogs() {
        guard let logURL = Logger.exportLogs() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FileFlow_Logs.txt"
        if panel.runModal() == .OK, let saveURL = panel.url {
            try? FileManager.default.copyItem(at: logURL, to: saveURL)
        }
    }
}

// MARK: - 2. Appearance Settings
struct AppearanceSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        SettingsScrollView {
            SettingsGroup(header: "主题模式") {
                VStack(spacing: 16) {
                    Picker("外观", selection: ThemeManager.shared.$currentTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("强调色")
                        Spacer()
                        Picker("", selection: ThemeManager.shared.$currentAccent) {
                            ForEach(AppAccent.allCases) { accent in
                                HStack {
                                    Circle().fill(accent.color).frame(width: 10, height: 10)
                                    Text(accent.rawValue)
                                }.tag(accent)
                            }
                        }
                        .fixedSize()
                    }
                }
                .padding(.vertical, 4)
            }
            
            SettingsGroup(header: "每日壁纸") {
                Toggle(isOn: $appState.useBingWallpaper) {
                    VStack(alignment: .leading) {
                        Text("使用 Bing 每日精选")
                        Text("每天自动获取来自微软必应的高清壁纸")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if appState.useBingWallpaper {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Wallpaper Preview with Navigation
                        ZStack(alignment: .bottom) {
                            if let url = appState.wallpaperURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(height: 180)
                                .cornerRadius(8)
                                .clipped()
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.secondary.opacity(0.2))
                                    .frame(height: 180)
                                    .overlay { ProgressView() }
                            }
                            
                            // Navigation Overlay
                            HStack {
                                Button {
                                    if appState.wallpaperIndex < 7 {
                                        appState.fetchDailyWallpaper(index: appState.wallpaperIndex + 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.left.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.8))
                                        .background(Circle().fill(.black.opacity(0.3)))
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.wallpaperIndex >= 7)
                                .help("查看前一天的壁纸")
                                
                                Spacer()
                                
                                VStack(spacing: 2) {
                                    Text(appState.wallpaperIndex == 0 ? "今日精选" : "\(appState.wallpaperIndex) 天前")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                
                                Spacer()
                                
                                Button {
                                    if appState.wallpaperIndex > 0 {
                                        appState.fetchDailyWallpaper(index: appState.wallpaperIndex - 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.8))
                                        .background(Circle().fill(.black.opacity(0.3)))
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.wallpaperIndex <= 0)
                                .help("查看后一天的壁纸")
                            }
                            .padding()
                        }
                        
                        Divider()
                        
                        // Controls
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                            GridRow {
                                Text("模糊度")
                                    .foregroundStyle(.secondary)
                                Slider(value: $appState.wallpaperBlur, in: 0...50)
                            }
                            GridRow {
                                Text("透明度")
                                    .foregroundStyle(.secondary)
                                Slider(value: $appState.wallpaperOpacity, in: 0...1)
                            }
                        }
                        
                        Toggle("显示磨砂玻璃叠加层", isOn: $appState.showGlassOverlay)
                            .padding(.top, 4)
                            
                        HStack {
                            Spacer()
                            if appState.wallpaperIndex > 0 {
                                Button("回到今天") {
                                    appState.fetchDailyWallpaper(index: 0)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 3. AI Settings
struct AISettingsView: View {
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openaiApiKey") private var openaiApiKey = ""
    @AppStorage("openaiModel") private var openaiModel = "gpt-4o-mini"
    @AppStorage("ollamaHost") private var ollamaHost = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.2"
    @AppStorage("autoAnalyze") private var autoAnalyze = true
    
    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?
    
    var body: some View {
        SettingsScrollView {
            SettingsGroup(header: "服务提供商") {
                HStack {
                    Text("选择 AI 引擎")
                    Spacer()
                    Picker("", selection: $aiProvider) {
                        Text("OpenAI").tag("openai")
                        Text("本地 Ollama").tag("ollama")
                        Text("已禁用").tag("disabled")
                    }
                    .fixedSize()
                }
                
                Divider()
                
                Toggle("导入文件时自动分析", isOn: $autoAnalyze)
            }
            
            if aiProvider == "openai" {
                SettingsGroup(header: "OpenAI 配置") {
                    SettingsRow(title: "API Key") {
                        SecureField("sk-...", text: $openaiApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    SettingsRow(title: "模型名称") {
                        TextField("gpt-4o-mini", text: $openaiModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    HStack {
                        Spacer()
                        Link("获取 API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                }
            } else if aiProvider == "ollama" {
                SettingsGroup(header: "Ollama 配置") {
                    SettingsRow(title: "服务地址") {
                        TextField("http://localhost:11434", text: $ollamaHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    SettingsRow(title: "模型名称") {
                        TextField("llama3.2", text: $ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    HStack {
                        Spacer()
                        Link("下载 Ollama", destination: URL(string: "https://ollama.ai")!)
                            .font(.caption)
                    }
                }
            }
            
            if aiProvider != "disabled" {
                SettingsGroup(footer: "测试连接以确保配置正确。") {
                    HStack {
                        if let result = testResult {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(result.success ? .green : .red)
                        }
                        
                        Spacer()
                        
                        ThemeButton(isTesting ? "测试中..." : "测试连接") {
                            runTest()
                        }
                        .disabled(isTesting)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let service = AIServiceFactory.createService()
                let _ = try await service.testConnection()
                testResult = (true, "连接成功")
            } catch {
                testResult = (false, "连接失败")
            }
            isTesting = false
        }
    }
}

// MARK: - 4. Sync Settings
struct SyncSettingsView: View {
    @ObservedObject private var syncService = CloudSyncService.shared
    
    var body: some View {
        SettingsScrollView {
            SettingsGroup(header: "状态", footer: "FileFlow 使用您的私有 iCloud 数据库，数据仅在您的设备间同步。") {
                HStack(spacing: 16) {
                    Image(systemName: "icloud.square.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud 云端同步")
                            .font(.headline)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(syncService.isAvailable ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(syncService.isAvailable ? "服务正常" : "服务不可用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if syncService.isSyncing {
                        ProgressView()
                    } else {
                        ThemeButton("立即同步") {
                            Task { await syncService.syncNow() }
                        }
                        .disabled(!syncService.isAvailable)
                    }
                }
                .padding(.vertical, 8)
                
                if let error = syncService.syncError {
                    Divider()
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.top, 4)
                }
                
                Divider()
                
                SettingsRow(title: "上次同步时间") {
                    if let date = syncService.lastSyncTime {
                        Text(date.formatted())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("从未")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 5. About Settings
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.pulse, isActive: true)
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 10)
            
            VStack(spacing: 8) {
                Text("FileFlow")
                    .font(.system(size: 36, weight: .bold))
                
                Text("Version 1.0.0 (Beta)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.secondary.opacity(0.1)))
            }
            
            Text("基于 PARA 方法论的智能文件管理系统")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    AboutFeature(icon: "folder.fill", title: "PARA 架构")
                    AboutFeature(icon: "sparkles", title: "AI 智能")
                    AboutFeature(icon: "icloud.fill", title: "云同步")
                }
            }
            .padding(.top, 20)
            
            Spacer()
            
            Text("Created by Google DeepMind Team")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [.blue.opacity(0.05), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
        )
    }
}

struct AboutFeature: View {
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .frame(width: 80)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Helper Components

struct SettingsScrollView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            VStack {
                Spacer(minLength: 0)
                
                VStack(spacing: 20) {
                    content
                }
                .frame(maxWidth: 500)
                .padding(.vertical, 40)
                .padding(.horizontal)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: NSApplication.shared.windows.first?.frame.height ?? 600)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let header: String?
    let footer: String?
    let content: Content
    
    init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = header {
                Text(header)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            
            VStack(spacing: 0) { // Set spacing to 0 for dividers
                content
            }
            .padding(12)
            .background(.regularMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            
            if let footer = footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let content: Content
    
    init(icon: String? = nil, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            content
        }
        .padding(.vertical, 4)
    }
}

struct ThemeButton: View {
    let title: String
    let icon: String?
    let role: ButtonRole?
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.action = action
    }
    
    var body: some View {
        Button(role: role, action: action) {
            if let icon = icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
