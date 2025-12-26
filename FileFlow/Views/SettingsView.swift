//
//  SettingsView.swift
//  FileFlow
//
//  应用设置界面 - macOS 风格重构版
//  完全对齐 macOS System Settings (Ventura+) 设计规范
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
            // Sidebar Column
            VStack(spacing: 0) {
                List(SettingsTab.allCases, selection: $selectedTab) { tab in
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(tab.color.gradient)
                            )
                        
                        Text(tab.rawValue)
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 4)
                    .tag(tab) // Explicit tag for selection to work
                }
                .listStyle(.sidebar)
            }
            .frame(width: 220)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Detail Content Column
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
        .frame(minWidth: 700, minHeight: 450)
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
        SettingsContainer(title: "通用") {
            SettingsGroup(header: "文件管理", footer: "当监控文件夹中出现新文件时，FileFlow 会自动提示您导入并分析。") {
                // File Path
                SettingsRow(label: "存储位置") {
                    HStack {
                        Text(fileFlowPath.isEmpty ? (FileFlowManager.shared.rootURL?.path ?? "未设置") : fileFlowPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        Button("更换...") {
                            appState.showRootSelector = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Divider()
                
                // Monitor
                SettingsRow(label: "自动监控") {
                    HStack {
                        if let url = appState.monitoredFolder {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(url.lastPathComponent)
                                    .foregroundStyle(.primary)
                            }
                            .help(url.path)
                            
                            Button {
                                appState.monitoredFolder = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("未启用")
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(appState.monitoredFolder == nil ? "选择文件夹..." : "更变...") {
                            selectMonitoredFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Divider()
                
                // Auto Rules
                SettingsRow(label: "自动归档规则") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .disabled(true)
                }
            }
            
            SettingsGroup(header: "维护") {
                SettingsRow(label: "重建索引", help: "修复搜索无法找到文件的问题") {
                    HStack {
                        if isRebuilding {
                            ProgressView().controlSize(.small)
                            Text(rebuildMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("执行重建") {
                            showRebuildAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRebuilding)
                    }
                }
                
                Divider()
                
                SettingsRow(label: "导出日志", help: "用于故障排查") {
                    Button("导出...") {
                        exportDiagnosticLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        SettingsContainer(title: "外观") {
            SettingsGroup(header: "显示") {
                SettingsRow(label: "外观模式") {
                    Picker("", selection: ThemeManager.shared.$currentTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                
                Divider()
                
                SettingsRow(label: "强调色") {
                    HStack(spacing: 12) {
                        ForEach(AppAccent.allCases) { accent in
                            Circle()
                                .fill(accent.color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .opacity(ThemeManager.shared.currentAccent == accent ? 1 : 0)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.2)) {
                                        ThemeManager.shared.currentAccent = accent
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            SettingsGroup(header: "每日壁纸") {
                SettingsRow(label: "使用 Bing 每日精选") {
                    Toggle("", isOn: $appState.useBingWallpaper)
                        .labelsHidden()
                }
                
                if appState.useBingWallpaper {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Wallpaper Preview with Navigation
                        ZStack(alignment: .bottom) {
                            if let url = appState.wallpaperURL {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(height: 200)
                                .clipped()
                                .cornerRadius(8)
                                .allowsHitTesting(false) // Ensure image doesn't block hits
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.tertiary)
                                    .frame(height: 200)
                                    .overlay { ProgressView() }
                                    .allowsHitTesting(false)
                            }
                            
                            // Navigation Overlay
                            HStack {
                                Button {
                                    if appState.wallpaperIndex < 7 {
                                        appState.fetchDailyWallpaper(index: appState.wallpaperIndex + 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .contentShape(Circle()) // Explicit hit shape
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.wallpaperIndex >= 7 || appState.isFetchingWallpaper)
                                .opacity(appState.wallpaperIndex >= 7 ? 0.5 : 1.0)
                                .help("查看前一天的壁纸")
                                
                                Spacer()
                                
                                VStack(spacing: 2) {
                                    if appState.isFetchingWallpaper {
                                        ProgressView()
                                            .controlSize(.small)
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Circle())
                                    } else {
                                        Text(appState.wallpaperIndex == 0 ? "今日精选" : "\(appState.wallpaperIndex) 天前")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    if appState.wallpaperIndex > 0 {
                                        appState.fetchDailyWallpaper(index: appState.wallpaperIndex - 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .contentShape(Circle()) // Explicit hit shape
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.wallpaperIndex <= 0 || appState.isFetchingWallpaper)
                                .opacity(appState.wallpaperIndex <= 0 ? 0.5 : 1.0)
                                .help("查看后一天的壁纸")
                            }
                            .padding(16)
                            .contentShape(Rectangle()) // Ensure HStack doesn't block hit testing in empty areas
                        }
                        
                        Divider()
                        
                        // Controls
                        VStack(spacing: 12) {
                            HStack {
                                Text("模糊度").font(.subheadline).foregroundStyle(.secondary)
                                Slider(value: $appState.wallpaperBlur, in: 0...50)
                            }
                            HStack {
                                Text("透明度").font(.subheadline).foregroundStyle(.secondary)
                                Slider(value: $appState.wallpaperOpacity, in: 0...1)
                            }
                        }
                        
                        Toggle("显示磨砂玻璃叠加层", isOn: $appState.showGlassOverlay)
                            .padding(.top, 4)
                    }
                    .padding(.top, 8)
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
        SettingsContainer(title: "智能服务") {
            SettingsGroup(header: "服务提供商") {
                SettingsRow(label: "AI 引擎") {
                    Picker("", selection: $aiProvider) {
                        Text("OpenAI").tag("openai")
                        Text("本地 Ollama").tag("ollama")
                        Text("已禁用").tag("disabled")
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                
                Divider()
                
                SettingsRow(label: "导入时自动分析") {
                    Toggle("", isOn: $autoAnalyze)
                        .labelsHidden()
                }
            }
            
            if aiProvider == "openai" {
                SettingsGroup(header: "OpenAI 配置") {
                    SettingsRow(label: "API Key") {
                        SecureField("sk-...", text: $openaiApiKey)
                            .textFieldStyle(.plain)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            .frame(width: 300)
                    }
                    
                    Divider()
                    
                    SettingsRow(label: "模型名称") {
                        TextField("gpt-4o-mini", text: $openaiModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                    
                    Divider()
                    
                    HStack {
                        Spacer()
                        Link("获取 API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            } else if aiProvider == "ollama" {
                SettingsGroup(header: "Ollama 配置") {
                    SettingsRow(label: "服务地址") {
                        TextField("http://localhost:11434", text: $ollamaHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    SettingsRow(label: "模型名称") {
                        TextField("llama3.2", text: $ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    HStack {
                        Spacer()
                        Link("下载 Ollama", destination: URL(string: "https://ollama.ai")!)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            if aiProvider != "disabled" {
                SettingsGroup(footer: "测试连接以确保 API 配置正确。") {
                    SettingsRow(label: "连接状态") {
                        HStack {
                            if let result = testResult {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(result.success ? .green : .red)
                            }
                            
                            Spacer()
                            
                            Button(isTesting ? "测试中..." : "测试连接") {
                                runTest()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isTesting)
                        }
                    }
                }
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
        SettingsContainer(title: "云同步") {
            SettingsGroup(header: "iCloud 状态", footer: "FileFlow 使用您的私有 iCloud 数据库，数据仅在您的设备间同步。") {
                HStack(spacing: 20) {
                    Image(systemName: "icloud.square.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue.gradient)
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iCloud 云端同步")
                            .font(.title3.bold())
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(syncService.isAvailable ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(syncService.isAvailable ? "服务正常" : "服务不可用")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if syncService.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    } else {
                        Button("立即同步") {
                            Task { await syncService.syncNow() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(!syncService.isAvailable)
                    }
                }
                .padding(.vertical, 12)
                
                if let error = syncService.syncError {
                    Divider()
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.top, 4)
                }
                
                Divider()
                
                SettingsRow(label: "上次同步时间") {
                    Group {
                        if let date = syncService.lastSyncTime {
                            Text(date.formatted())
                        } else {
                            Text("从未")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 5. About Settings
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)
            
            // App Icon
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundStyle(.blue.gradient)
                .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
                .padding(.bottom, 24)
            
            // App Name & Version
            Text("FileFlow")
                .font(.system(size: 32, weight: .bold))
                .padding(.bottom, 8)
            
            Text("Version 1.0.0 (Beta)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                .padding(.bottom, 32)
            
            // Features Grid
            HStack(spacing: 40) {
                AboutFeatureItem(icon: "folder.fill", title: "PARA 架构")
                AboutFeatureItem(icon: "sparkles", title: "AI 智能")
                AboutFeatureItem(icon: "icloud.fill", title: "云同步")
            }
            .padding(.bottom, 40)
            
            Spacer()
            
            // Copyright
            Text("Designed by Google DeepMind Team")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct AboutFeatureItem: View {
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Helper Components

struct SettingsContainer<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Large Title like System Settings
                Text(title)
                    .font(.largeTitle.bold())
                    .padding(.bottom, 10)
                
                content
            }
            .padding(40)
            .frame(maxWidth: 600, alignment: .leading) // Constrain width for readability
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
                    .padding(.leading, 12)
            }
            
            VStack(spacing: 0) {
                content
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor)) // White-ish background
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            
            if let footer = footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let help: String?
    let content: Content
    
    init(label: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.help = help
        self.content = content()
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                if let help = help {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, alignment: .leading) // Fixed label width for easier scanning
            
            Spacer()
            
            content
        }
        .padding(.vertical, 6)
    }
}
