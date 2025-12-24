import SwiftUI
import UniformTypeIdentifiers

struct UnifiedHomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedFileURL: URL?
    @Binding var pendingFileURLs: [URL]
    
    // Callbacks
    var onSearch: (String) -> Void = { _ in }
    var onFilesDropped: (UploadMode) -> Void = { _ in } // Called after files are added to pendingFileURLs
    
    // State
    @State private var searchText = ""
    @State private var isTargeted = false
    @State private var isHoveringUpload = false
    @State private var selectedMode: UploadMode = .smart
    
    var body: some View {
        ZStack {
            // Background Gradient (Subtle)
            AuroraBackground()
                .opacity(0.3)
                .blur(radius: 60)
            
            ScrollView {
                VStack(spacing: 48) {
                    
                    // MARK: - Hero Section
                    VStack(spacing: 32) {
                        // Greeting or Title
                        VStack(spacing: 8) {
                            Text(greetingText())
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("今天想整理些什么？")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                        
                        // Hero Search & Upload Bar
                        HeroSearchBar(
                            searchText: $searchText,
                            isTargeted: $isTargeted,
                            onCommit: {
                                if !searchText.isEmpty {
                                    onSearch(searchText)
                                }
                            },
                            onUpload: {
                                appState.showFileImporter = true
                            },
                            onDrop: { providers in
                                handleDrop(providers: providers)
                            }
                        )
                        .frame(maxWidth: 700)
                        
                        // Mode Selector Pills
                        HStack(spacing: 12) {
                            ForEach(UploadMode.allCases) { mode in
                                ModeSelectorPill(
                                    mode: mode,
                                    isSelected: selectedMode == mode
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedMode = mode
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Dashboard Grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 24)], spacing: 24) {
                        
                        // Recent Files Card
                        DashboardCard(title: "最近整理", icon: "clock.arrow.circlepath") {
                            if appState.recentFiles.isEmpty {
                                ContentUnavailableView("暂无最近文件", systemImage: "doc.on.doc")
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(appState.recentFiles.prefix(5)) { file in
                                        RecentFileCompactRow(file: file)
                                    }
                                }
                            }
                        }
                        
                        // Popular Tags Card
                        DashboardCard(title: "常用标签", icon: "star.fill") {
                            if appState.sidebarTags.isEmpty {
                                ContentUnavailableView("暂无标签", systemImage: "tag.slash")
                            } else {
                                FlowLayout(spacing: 10) {
                                    ForEach(appState.sidebarTags.prefix(10)) { tag in
                                        TagManagerChip(
                                            tag: tag,
                                            isFavoriteSection: false,
                                            onToggleFavorite: {}, // Read-only here
                                            onRename: {},
                                            onDelete: {}
                                        )
                                        .scaleEffect(0.9) // Slightly smaller
                                    }
                                }
                            }
                        }
                        
                        // Quick Folders (PARA)
                        DashboardCard(title: "快速访问", icon: "folder.fill") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(PARACategory.allCases) { category in
                                    Button {
                                        // Navigate to category
                                    } label: {
                                        HStack {
                                            Image(systemName: category.icon)
                                                .foregroundStyle(category.color)
                                            Text(category.displayName)
                                                .font(.headline)
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(category.color.opacity(0.1))
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: 1200)
                }
                .padding(.bottom, 60)
            }
        }
    }
    
    private func greetingText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            let urls: [URL] = await withTaskGroup(of: URL?.self) { group in
                for provider in providers {
                    group.addTask {
                        return await withCheckedContinuation { continuation in
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                continuation.resume(returning: url)
                            }
                        }
                    }
                }
                var results: [URL] = []
                for await url in group {
                    if let url = url { results.append(url) }
                }
                return results
            }
            
            await MainActor.run {
                let uniqueNewURLs = urls.filter { !self.pendingFileURLs.contains($0) }
                if !uniqueNewURLs.isEmpty {
                    self.pendingFileURLs.append(contentsOf: uniqueNewURLs)
                    // Notify parent with the selected mode
                    self.onFilesDropped(self.selectedMode)
                }
            }
        }
    }
}

// MARK: - Components

struct HeroSearchBar: View {
    @Binding var searchText: String
    @Binding var isTargeted: Bool
    var onCommit: () -> Void
    var onUpload: () -> Void
    var onDrop: ([NSItemProvider]) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Search Icon / Drop Indicator
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(isTargeted ? .blue : .secondary)
                .symbolEffect(.bounce, value: isTargeted)
            
            // Input Field
            TextField(isTargeted ? "松手上传文件..." : "搜索文件、标签或拖拽上传...", text: $searchText)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(onCommit)
            
            // Upload Button
            Button(action: onUpload) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.blue.gradient))
                    .shadow(color: .blue.opacity(0.3), radius: 5)
            }
            .buttonStyle(.plain)
             // Keyboard shortcut for upload?
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(isTargeted ? Color.blue : .white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
        }
        .scaleEffect(isTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            onDrop(providers)
            return true
        }
        .onTapGesture {
            isFocused = true
        }
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String // SF Symbol
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            
            content
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }
}

struct RecentFileCompactRow: View {
    let file: ManagedFile
    
    var body: some View {
        HStack(spacing: 12) {
            RichFileIcon(path: file.newPath)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.newName.isEmpty ? file.originalName : file.newName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(file.importedAt.timeAgo())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
    }
}

struct QuickActionPill: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mode Selector Pill
struct ModeSelectorPill: View {
    let mode: UploadMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mode.shortDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? mode.color.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? mode.color : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
            )
            .foregroundStyle(isSelected ? mode.color : .primary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

