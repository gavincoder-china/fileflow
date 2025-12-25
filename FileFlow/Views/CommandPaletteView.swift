//
//  CommandPaletteView.swift
//  FileFlow
//
//  万能命令面板 - 类似 VS Code 的 Cmd+Shift+P
//

import SwiftUI

// MARK: - Command Model

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let category: CommandCategory
    let keywords: [String]
    let action: () -> Void
    
    enum CommandCategory: String, CaseIterable {
        case navigation = "导航"
        case file = "文件"
        case view = "视图"
        case tools = "工具"
        case settings = "设置"
        
        var color: Color {
            switch self {
            case .navigation: return .blue
            case .file: return .green
            case .view: return .purple
            case .tools: return .orange
            case .settings: return .gray
            }
        }
    }
    
    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        let lowercased = query.lowercased()
        return title.lowercased().contains(lowercased) ||
               keywords.contains { $0.lowercased().contains(lowercased) }
    }
}

// MARK: - Command Palette View

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    private var filteredCommands: [PaletteCommand] {
        let all = buildCommands()
        if searchText.isEmpty { return all }
        return all.filter { $0.matches(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                
                TextField("输入命令或搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelected()
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("ESC")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(16)
            .background(.regularMaterial)
            
            Divider()
            
            // Command List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                            CommandRow(
                                command: command,
                                isSelected: index == selectedIndex
                            )
                            .id(index)
                            .onTapGesture {
                                selectedIndex = index
                                executeSelected()
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            Divider()
            
            // Footer
            HStack {
                Text("↑↓ 选择")
                Text("⏎ 执行")
                Text("ESC 退出")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .frame(width: 600)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }
    
    private func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        let command = filteredCommands[selectedIndex]
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            command.action()
        }
    }
    
    // MARK: - Build Commands
    
    private func buildCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []
        
        // Navigation
        commands.append(PaletteCommand(
            title: "前往首页",
            icon: "house.fill",
            category: .navigation,
            keywords: ["home", "主页", "dashboard"],
            action: { /* Navigate to home */ }
        ))
        
        for category in PARACategory.allCases {
            commands.append(PaletteCommand(
                title: "前往 \(category.displayName)",
                icon: category.icon,
                category: .navigation,
                keywords: [category.rawValue, "goto"],
                action: { appState.selectedCategory = category }
            ))
        }
        
        // File Actions
        commands.append(PaletteCommand(
            title: "导入文件...",
            icon: "plus.circle.fill",
            category: .file,
            keywords: ["import", "upload", "添加", "上传"],
            action: { appState.showFileImporter = true }
        ))
        
        commands.append(PaletteCommand(
            title: "批量整理模式",
            icon: "square.stack.3d.up.fill",
            category: .file,
            keywords: ["batch", "bulk", "批量"],
            action: { appState.showBatchMode = true }
        ))
        
        // View
        commands.append(PaletteCommand(
            title: "刷新数据",
            icon: "arrow.clockwise",
            category: .view,
            keywords: ["refresh", "reload", "刷新"],
            action: { appState.refreshData() }
        ))
        
        // Tools
        commands.append(PaletteCommand(
            title: "知识图谱",
            icon: "point.3.connected.trianglepath.dotted",
            category: .tools,
            keywords: ["graph", "tags", "标签", "关系"],
            action: { /* Navigate to graph */ }
        ))
        
        commands.append(PaletteCommand(
            title: "活动日历",
            icon: "calendar",
            category: .tools,
            keywords: ["calendar", "activity", "日历"],
            action: { /* Navigate to calendar */ }
        ))
        
        commands.append(PaletteCommand(
            title: "时间胶囊",
            icon: "hourglass",
            category: .tools,
            keywords: ["capsule", "future", "胶囊"],
            action: { /* Navigate to capsule */ }
        ))
        
        commands.append(PaletteCommand(
            title: "立即同步到 iCloud",
            icon: "icloud.and.arrow.up",
            category: .tools,
            keywords: ["sync", "cloud", "同步"],
            action: {
                Task { await CloudSyncService.shared.syncNow() }
            }
        ))
        
        // Settings
        commands.append(PaletteCommand(
            title: "打开设置",
            icon: "gearshape.fill",
            category: .settings,
            keywords: ["settings", "preferences", "设置", "偏好"],
            action: {
                // Open app settings - currently a placeholder
                // Settings are accessed via the app menu
            }
        ))
        
        commands.append(PaletteCommand(
            title: "切换深色/浅色模式",
            icon: "moon.fill",
            category: .settings,
            keywords: ["dark", "light", "theme", "主题"],
            action: {
                let current = ThemeManager.shared.currentTheme
                ThemeManager.shared.currentTheme = current == .dark ? .light : .dark
            }
        ))
        
        return commands
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .font(.title3)
                .foregroundStyle(command.category.color)
                .frame(width: 28)
            
            Text(command.title)
                .font(.body)
            
            Spacer()
            
            Text(command.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(command.category.color.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    CommandPaletteView()
        .environmentObject(AppState())
        .frame(width: 700, height: 500)
        .background(Color.black.opacity(0.5))
}
