//
//  FileFlowApp.swift
//  FileFlow - 智能文件整理系统
//
//  基于 PARA 方法论的 macOS 原生智能文件整理应用
//  
//  设计理念：
//  1. 以文件系统为根基（类似 Obsidian Vault）
//  2. 文件移动而非复制，只保留一份
//  3. SQLite 作为辅助索引
//

import SwiftUI
import Combine

@main
struct FileFlowApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("文件整理") {
                Button("导入文件...") {
                    appState.showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("批量整理...") {
                    appState.showBatchMode = true
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Divider()
                
                Button("打开根目录") {
                    appState.openRootFolder()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button("更换根目录...") {
                    appState.showRootSelector = true
                }
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Root View (handles onboarding)
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding: Bool
    
    init() {
        // 检查是否已配置根目录
        _showOnboarding = State(initialValue: !FileFlowManager.shared.isRootConfigured)
    }
    
    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(onComplete: {
                    withAnimation {
                        showOnboarding = false
                    }
                    appState.refreshData()
                })
            } else {
                ZStack {
                    AuroraBackground()
                        .id(appState.wallpaperURL)
                    
                    ContentView()
                        .frame(minWidth: 900, minHeight: 600)
                        .scrollContentBackground(.hidden) // Ensure all scrolls are transparent
                }
            }
        }
        .sheet(isPresented: $appState.showRootSelector) {
            RootSelectorSheet()
                .environmentObject(appState)
        }
    }
}

// MARK: - Root Selector Sheet
struct RootSelectorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newPath: URL?
    
    private let fileManager = FileFlowManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("更换根目录")
                .font(.headline)
            
            Text("请注意：更换根目录后，之前目录中的文件不会自动移动")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Current Path
            VStack(alignment: .leading, spacing: 4) {
                Text("当前目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(fileManager.rootURL?.path ?? "未设置")
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
            }
            
            // New Path
            if let path = newPath {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(path.path)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Button("选择新目录...") {
                selectNewDirectory()
            }
            
            Spacer()
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                
                Spacer()
                
                Button("确认更换") {
                    if let path = newPath {
                        fileManager.rootURL = path
                        appState.refreshData()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPath == nil)
            }
        }
        .padding(24)
        .frame(width: 500, height: 350)
    }
    
    private func selectNewDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择新的根目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            newPath = url
        }
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var showFileImporter = false
    @Published var showBatchMode = false
    @Published var showRootSelector = false
    @Published var selectedCategory: PARACategory = .resources
    @Published var recentFiles: [ManagedFile] = []
    @Published var allTags: [Tag] = []
    @Published var sidebarTags: [Tag] = [] // Optimized list for sidebar
    @Published var searchQuery = ""
    @Published var statistics: (totalFiles: Int, totalSize: Int64, byCategory: [PARACategory: Int])?
    
    // 背景壁纸设置
    @Published var wallpaperURL: URL?
    
    @AppStorage("useBingWallpaper") var useBingWallpaper = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("wallpaperBlur") var wallpaperBlur: Double = 20.0 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("wallpaperOpacity") var wallpaperOpacity: Double = 0.5 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("showGlassOverlay") var showGlassOverlay = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("wallpaperIndex") var wallpaperIndex = 0 {
        willSet { objectWillChange.send() }
    }
    
    // 侧边栏标签配置
    @AppStorage("sidebarShowFavorites") var sidebarShowFavorites = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("sidebarTopTagsCount") var sidebarTopTagsCount = 20 {
        willSet { objectWillChange.send() }
    }
    
    // 文件夹监控
    @Published var monitoredFolder: URL? {
        didSet {
            // 保存设置
            if let url = monitoredFolder {
                do {
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmark, forKey: "monitoredFolderBookmark")
                } catch {
                    Logger.error("无法保存监控目录书签: \(error)")
                }
                directoryMonitor.startMonitoring(url: url)
            } else {
                UserDefaults.standard.removeObject(forKey: "monitoredFolderBookmark")
                directoryMonitor.stopMonitoring()
            }
        }
    }
    
    // 新文件通知
    @Published var pendingNewFiles: [URL] = []
    
    @Published var lastUpdateID = UUID()
    
    private let fileManager = FileFlowManager.shared
    private let database = DatabaseManager.shared
    private let directoryMonitor = DirectoryMonitorService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        if fileManager.isRootConfigured {
            loadInitialData()
        }
        
        setupMonitoring()
        
        if useBingWallpaper {
            fetchDailyWallpaper(index: wallpaperIndex)
        }
    }
    
    func fetchDailyWallpaper(index: Int? = nil) {
        let fetchIndex = index ?? wallpaperIndex
        Task {
            do {
                let url = try await WallpaperService.shared.fetchDailyWallpaperURL(index: fetchIndex)
                await MainActor.run {
                    self.wallpaperURL = url
                    if let idx = index {
                        self.wallpaperIndex = idx
                    }
                }
            } catch {
                Logger.error("Failed to fetch wallpaper at index \(fetchIndex): \(error)")
            }
        }
    }
    
    private func setupMonitoring() {
        // 恢复监控目录
        if let bookmarkData = UserDefaults.standard.data(forKey: "monitoredFolderBookmark") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    // 重新创建书签
                    let newBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(newBookmark, forKey: "monitoredFolderBookmark")
                }
                
                self.monitoredFolder = url
                // 注意：这里不需要手动调用 startMonitoring，因为 didSet 会触发
            } catch {
                Logger.error("无法恢复监控目录: \(error)")
                UserDefaults.standard.removeObject(forKey: "monitoredFolderBookmark")
            }
        }
        
        // 监听新文件
        directoryMonitor.$newFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (files: [URL]) in
                guard let self = self, !files.isEmpty else { return }
                self.pendingNewFiles.append(contentsOf: files)
            }
            .store(in: &cancellables)
    }

    func loadInitialData() {
        // Load recent files and tags from database
        Task { @MainActor in
            self.recentFiles = await database.getRecentFiles(limit: 20)
            let tags = await database.getAllTags()
            self.allTags = tags
            self.statistics = fileManager.getStatistics()
            
            // Optimized Sidebar Tags: Favorites + Top N Used (configurable)
            // Calculate strictly on MainActor to avoid threading issues
            var combinedTags: [Tag] = []
            var seenIds = Set<UUID>()
            
            // 1. Favorites (if enabled)
            if self.sidebarShowFavorites {
                let favorites = tags.filter { $0.isFavorite }
                for tag in favorites {
                    if seenIds.insert(tag.id).inserted {
                        combinedTags.append(tag)
                    }
                }
            }
            
            // 2. Top Used (Top N, configurable)
            let topUsed = tags.sorted { $0.usageCount > $1.usageCount }.prefix(self.sidebarTopTagsCount)
            for tag in topUsed {
                if seenIds.insert(tag.id).inserted {
                    combinedTags.append(tag)
                }
            }
            
            self.sidebarTags = combinedTags
            
            // Don't update ID here to avoid loops if called from init?
            // But refreshData calls this.
        }
    }
    
    func openRootFolder() {
        fileManager.openRootInFinder()
    }
    
    func refreshData() {
        loadInitialData()
        lastUpdateID = UUID()
    }
}
