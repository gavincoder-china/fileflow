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
    @State private var selectedUploadMode: UploadMode = .smart  // Current upload mode
    
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
                // Background is now global in RootView
                
                switch selectedSidebarItem {
                case .dropZone:
                    UnifiedHomeView(
                        selectedFileURL: $selectedFileURL,
                        pendingFileURLs: $pendingFileURLs,
                        onSearch: { query in
                            appState.searchQuery = query
                            selectedSidebarItem = .search
                        },
                        onFilesDropped: { mode in
                            selectedUploadMode = mode
                        }
                    )
                    .id("dropZone")
                case .category(let category):
                    CategoryView(category: category)
                        .id(category)
                case .tag(let tag):
                    TagFilesView(tag: tag)
                        .id(tag.id)
                case .search:
                    SearchView()
                        .id("search")
                case .graph:
                    TagGraphView()
                        .id("graph")
                case .tagManager:
                    TagManagerView()
                        .id("tagManager")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear) // Force clear detail background
        }
        .background(Color.clear) // Force clear NavigationSplitView background
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
            // Switch organizer view based on mode
            switch selectedUploadMode {
            case .smart:
                FileStackOrganizerView(
                    fileURLs: pendingFileURLs,
                    mode: .smart,
                    onComplete: {
                        pendingFileURLs.removeAll()
                        appState.refreshData()
                    },
                    onCancel: {
                        pendingFileURLs.removeAll()
                    }
                )
            case .manual:
                ManualBatchView(
                    fileURLs: pendingFileURLs,
                    onComplete: {
                        pendingFileURLs.removeAll()
                        appState.refreshData()
                    },
                    onCancel: {
                        pendingFileURLs.removeAll()
                    }
                )
            case .mirror:
                MirrorImportView(
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
        .scrollContentBackground(.hidden) // Ensure all detail views are transparent
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
    
    var body: some View {
        List {
            // Quick Actions
            Section("快速操作") {
                SidebarItemRow(
                    title: "拖拽整理",
                    icon: "square.and.arrow.down.fill",
                    isSelected: selectedItem == .dropZone,
                    color: .blue
                ) { selectedItem = .dropZone }
                
                SidebarItemRow(
                    title: "搜索",
                    icon: "magnifyingglass",
                    isSelected: selectedItem == .search,
                    color: .blue
                ) { selectedItem = .search }
                
                SidebarItemRow(
                    title: "知识图谱",
                    icon: "network",
                    isSelected: selectedItem == .graph,
                    color: .indigo
                ) { selectedItem = .graph }
            }
            .designRounded()
            
            // PARA Categories
            Section("分类") {
                ForEach(PARACategory.allCases) { category in
                    SidebarItemRow(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: selectedItem == .category(category),
                        color: category.color
                    ) { selectedItem = .category(category) }
                }
            }
            .designRounded()
            
            // Recent Tags - Collapsible
            Section {
                ForEach(appState.sidebarTags) { tag in
                    SidebarTagRow(
                        tag: tag,
                        isSelected: selectedItem == .tag(tag)
                    ) { selectedItem = .tag(tag) }
                }
                
                // Manage Tags Entry
                SidebarItemRow(
                    title: "管理所有标签...",
                    icon: "slider.horizontal.3",
                    isSelected: selectedItem == .tagManager,
                    color: .secondary
                ) { selectedItem = .tagManager }
                    
            } header: {
                HStack {
                    Text("常用标签")
                        .designRounded()
                    Spacer()
                    Button {
                        selectedItem = .tagManager
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 230)
    }
}

struct SidebarItemRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarSelection(isSelected: isSelected, color: color)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct SidebarTagRow: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 8)
                
                Text(tag.name.isEmpty ? "无名称" : tag.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(tag.usageCount)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? .white.opacity(0.2) : .primary.opacity(0.05))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarSelection(isSelected: isSelected, color: tag.swiftUIColor)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}




extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview
// Note: #Preview macro not supported in SwiftPM, use Xcode for previews
/*
#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
*/

// MARK: - URL Identifiable Extension
extension URL: @retroactive Identifiable {
    public var id: String { self.absoluteString }
}

// MARK: - Formatting Helpers
extension View {
    func designRounded() -> some View {
        self.fontDesign(.rounded)
    }
}

