//
//  ContentView.swift
//  FileFlow
//
//  主界面视图
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebarItem: SidebarItem = .dropZone
    @State private var selectedFileURL: URL?  // 用于驱动 sheet
    @State private var pendingFileURLs: [URL] = []  // 待处理的文件队列
    
    enum SidebarItem: Hashable {
        case dropZone
        case category(PARACategory)
        case tag(Tag)
        case search
        case graph
        case tagManager
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedSidebarItem)
                .background(.ultraThinMaterial) // Sidebar translucency
        } detail: {
            ZStack {
                // Global animated background
                AuroraBackground()
                
                switch selectedSidebarItem {
                case .dropZone:
                    MainDropZoneView(
                        selectedFileURL: $selectedFileURL,
                        pendingFileURLs: $pendingFileURLs
                    )
                case .category(let category):
                    CategoryView(category: category)
                case .tag(let tag):
                    TagFilesView(tag: tag)
                case .search:
                    SearchView()
                case .graph:
                    TagGraphView()
                case .tagManager:
                    TagManagerView()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !appState.pendingNewFiles.isEmpty {
                NewFilesToast(count: appState.pendingNewFiles.count) {
                    // Import pending new files
                    let newFiles = appState.pendingNewFiles
                    appState.pendingNewFiles.removeAll()
                    
                    pendingFileURLs.append(contentsOf: newFiles)
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: Binding(
            get: { !pendingFileURLs.isEmpty },
            set: { if !$0 { pendingFileURLs.removeAll() } }
        )) {
            FileStackOrganizerView(
                fileURLs: pendingFileURLs,
                onComplete: {
                    pendingFileURLs.removeAll()
                    appState.refreshData()
                },
                onCancel: {
                    pendingFileURLs.removeAll()
                }
            )
        }
        .fileImporter(
            isPresented: $appState.showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                // Add to pending queue, which triggers the sheet automatically
                pendingFileURLs.append(contentsOf: urls)
            }
        }
        .sheet(isPresented: $appState.showBatchMode) {
            BatchOrganizeView()
                .environmentObject(appState)
        }
    }
}

// MARK: - New Files Toast
struct NewFilesToast: View {
    let count: Int
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: count)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("发现 \(count) 个新文件")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Text("点击开始整理")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
            
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue.gradient)
                .shadow(radius: 10)
        }
        .frame(width: 300)
        .onTapGesture(perform: action)
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedItem: ContentView.SidebarItem
    
    private var displayedTags: [Tag] {
        let favorites = appState.allTags.filter { $0.isFavorite }
        if favorites.isEmpty {
            // Fallback: Show top 5 used tags if no favorites
            return Array(appState.allTags.sorted { $0.usageCount > $1.usageCount }.prefix(5))
        }
        return favorites
    }
    
    var body: some View {
        List(selection: $selectedItem) {
            // Quick Actions
            Section("快速操作") {
                Label("拖拽整理", systemImage: "square.and.arrow.down.fill")
                    .tag(ContentView.SidebarItem.dropZone)
                
                Label("搜索", systemImage: "magnifyingglass")
                    .tag(ContentView.SidebarItem.search)
                
                Label("知识图谱", systemImage: "network")
                    .tag(ContentView.SidebarItem.graph)
            }
            
            // PARA Categories
            Section("分类") {
                ForEach(PARACategory.allCases) { category in
                    Label(category.displayName, systemImage: category.icon)
                        .foregroundStyle(category.color)
                        .tag(ContentView.SidebarItem.category(category))
                }
            }
            
            // Recent Tags - Collapsible
            Section {
                ForEach(displayedTags) { tag in
                    HStack {
                        Circle()
                            .fill(tag.swiftUIColor)
                            .frame(width: 8, height: 8)
                        Text(tag.name.isEmpty ? "无名称" : tag.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(tag.usageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(ContentView.SidebarItem.tag(tag))
                }
                
                // Show more/less button
                if appState.allTags.filter({ $0.isFavorite }).isEmpty && appState.allTags.count > 5 {
                    // Only show "More" hint if we are in fallback mode
                    HStack {
                        Spacer()
                        Text("仅显示前5个常用标签")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            } header: {
                HStack {
                    Text("常用标签")
                    Spacer()
                    Button {
                        selectedItem = .tagManager
                    } label: {
                        Image(systemName: "slider.horizontal.3") // Manage icon
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}


// MARK: - Main Drop Zone View
// MARK: - Main Drop Zone View
struct MainDropZoneView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedFileURL: URL?
    @Binding var pendingFileURLs: [URL]
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FileFlow")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("智能文件整理系统")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(32)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Drop Zone
                    DropZoneCard(isTargeted: $isTargeted)
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            handleDrop(providers: providers)
                            return true
                        }
                    
                    // Recent Files
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("最近整理")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Button("查看全部") {
                                // TODO: Navigate
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.horizontal, 4)
                        
                        if appState.recentFiles.isEmpty {
                            ContentUnavailableView(
                                "暂无文件",
                                systemImage: "doc.on.doc",
                                description: Text("拖拽文件到上方区域开始整理")
                            )
                            .frame(height: 150)
                            .glass()
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(appState.recentFiles.prefix(10)) { file in
                                    RecentFileRow(file: file)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // 优先尝试作为 File URL 加载
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    guard let data = data,
                          let path = String(data: data, encoding: .utf8),
                          let url = URL(string: path) else {
                        print("❌ Failed to decode file URL: \(String(describing: error))")
                        return
                    }
                    
                    Task { @MainActor in
                        // Add to queue
                        if !self.pendingFileURLs.contains(url) {
                            self.pendingFileURLs.append(url)
                            print("✅ Dropped file: \(url.lastPathComponent)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Drop Zone Card
// MARK: - Drop Zone Card
struct DropZoneCard: View {
    @Binding var isTargeted: Bool
    
    var body: some View {
        ZStack {
            // MARK: Ghost Cards (Stack Effect)
            // Left tilted card
            RoundedRectangle(cornerRadius: 24)
                .stroke(isTargeted ? .blue.opacity(0.3) : .clear, lineWidth: 2)
                .background(isTargeted ? .blue.opacity(0.05) : .clear)
                .glass(cornerRadius: 24, material: .ultraThin)
                .frame(height: 220)
                .rotationEffect(.degrees(isTargeted ? -6 : 0))
                .offset(x: isTargeted ? -20 : 0, y: isTargeted ? 10 : 0)
                .opacity(isTargeted ? 1 : 0)
                .scaleEffect(0.9)
            
            // Right tilted card
            RoundedRectangle(cornerRadius: 24)
                .stroke(isTargeted ? .blue.opacity(0.3) : .clear, lineWidth: 2)
                .background(isTargeted ? .blue.opacity(0.05) : .clear)
                .glass(cornerRadius: 24, material: .ultraThin)
                .frame(height: 220)
                .rotationEffect(.degrees(isTargeted ? 6 : 0))
                .offset(x: isTargeted ? 20 : 0, y: isTargeted ? 10 : 0)
                .opacity(isTargeted ? 1 : 0)
                .scaleEffect(0.9)
            
            // MARK: Main Card
            ZStack {
                // Animated border/glow when targeted
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        isTargeted ? Color.blue.opacity(0.8) : Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: isTargeted ? [] : [10, 5])
                    )
                    .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
                    .shadow(color: isTargeted ? .blue.opacity(0.3) : .clear, radius: 15)
                
                VStack(spacing: 20) {
                    ZStack {
                        // Icon Background
                        Circle()
                            .fill(isTargeted ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.05))
                            .frame(width: 80, height: 80)
                            .scaleEffect(isTargeted ? 1.1 : 1.0)
                        
                        // Icon
                        Image(systemName: isTargeted ? "square.stack.3d.down.right.fill" : "arrow.down.doc")
                            .font(.system(size: 36))
                            .foregroundStyle(isTargeted ? .blue : .secondary)
                            .symbolEffect(.bounce, value: isTargeted)
                    }
                    
                    VStack(spacing: 6) {
                        Text(isTargeted ? "松手即可批量导入" : "将文件拖拽到此处")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(isTargeted ? .blue : .primary)
                        
                        Text(isTargeted ? "支持多文件同时上传" : "或点击开启文件选择器")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .glass(cornerRadius: 24, material: .regular)
            .offset(y: isTargeted ? -10 : 0) // Lift up effect
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Trigger file import (Parent view handles this usually via fileImporter binding, but here onTapGesture is placeholder? 
            // Actually ContentView .onTapGesture on the container usually triggers it, need to verify bubble up)
            // But let's keep consistent.
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isTargeted)
    }
}

// MARK: - Recent File Row
struct RecentFileRow: View {
    let file: ManagedFile
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            RichFileIcon(path: file.newPath)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.newName.isEmpty ? file.originalName : file.newName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .allowsTightening(true)
                
                HStack(spacing: 10) {
                    Label(file.category.displayName, systemImage: file.category.icon)
                        .font(.caption)
                        .foregroundStyle(file.category.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(file.category.color.opacity(0.1))
                        .cornerRadius(6)
                    
                    ForEach(file.tags.prefix(3)) { tag in
                        Text("#\(tag.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Meta
            VStack(alignment: .trailing, spacing: 4) {
                Text(file.importedAt.timeAgo())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                if isHovering {
                    Button {
                        FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
                    } label: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .padding(12)
        .glass(cornerRadius: 16, material: .ultraThin, shadowRadius: isHovering ? 4 : 0)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Date Extension
extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}

// MARK: - URL Identifiable Extension
extension URL: @retroactive Identifiable {
    public var id: String { self.absoluteString }
}

