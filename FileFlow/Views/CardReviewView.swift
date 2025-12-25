//
//  CardReviewView.swift
//  FileFlow
//
//  Standalone Knowledge Card Review Page
//

import SwiftUI

struct CardReviewView: View {
    @EnvironmentObject var appState: AppState
    @State private var allCards: [KnowledgeCard] = []
    @State private var displayedCards: [KnowledgeCard] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var showAnswer = false
    @State private var isGenerating = false
    @State private var generationProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentFileName: String = ""
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var generationMessage: String? = nil  // For status messages
    @State private var isProgressMinimized = false  // For minimized progress bar
    
    // Modes and Filters
    @State private var viewMode: ViewMode = .browse
    @State private var selectedCategory: PARACategory? = nil
    @State private var selectedTag: Tag? = nil
    @State private var showFilters = false
    
    enum ViewMode: String, CaseIterable {
        case browse = "全部浏览"
        case review = "待复习"
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Minimized Progress Bar (at top)
                if isGenerating && isProgressMinimized {
                    minimizedProgressBar
                }
                
                // Header
                headerView
                
                Divider()
                
                // Filter Bar
                filterBar
                
                Divider()
                
                // Content
                contentView
            }
            
            // Full Progress Overlay (centered)
            if isGenerating && !isProgressMinimized && generationMessage == nil {
                generationOverlay
            }
            
            // Completion/Message Overlay
            if isGenerating && generationMessage != nil {
                generationOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadCards()
        }
    }
    
    // MARK: - Minimized Progress Bar
    private var minimizedProgressBar: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
            
            Text("生成中: \(generationProgress.current)/\(generationProgress.total)")
                .font(.caption.bold())
            
            if !currentFileName.isEmpty {
                Text("• \(currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isProgressMinimized = false
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("展开")
            
            Button {
                cancelGeneration()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("取消生成")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Generation Progress Overlay
    private var generationOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Card
            VStack(spacing: 0) {
                // Header with gradient
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                        Text("AI 卡片生成")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    
                    Spacer()
                    
                    // X button = minimize (hide popup, keep running)
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isProgressMinimized = true
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("最小化 (后台继续运行)")
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                // Content
                VStack(spacing: 20) {
                    if let message = generationMessage {
                        // Completion State
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(Color.green)
                            }
                            
                            Text(message)
                                .font(.title3.weight(.medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Progress State
                        VStack(spacing: 16) {
                            // Animated icon
                            ZStack {
                                Circle()
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                                    .frame(width: 70, height: 70)
                                
                                Circle()
                                    .trim(from: 0, to: generationProgress.total > 0 ? CGFloat(generationProgress.current) / CGFloat(generationProgress.total) : 0.1)
                                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 70, height: 70)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.3), value: generationProgress.current)
                                
                                if generationProgress.total > 0 {
                                    Text("\(Int(Double(generationProgress.current) / Double(generationProgress.total) * 100))%")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.blue)
                                } else {
                                    ProgressView()
                                }
                            }
                            
                            Text("正在分析文件并生成知识卡片")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            if generationProgress.total > 0 {
                                HStack(spacing: 4) {
                                    Text("\(generationProgress.current)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.blue)
                                    Text("/")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                    Text("\(generationProgress.total)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            if !currentFileName.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .font(.caption)
                                    Text(currentFileName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(20)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 24)
                
                Divider()
                
                // Footer
                Button {
                    cancelGeneration()
                } label: {
                    Text(generationMessage != nil ? "完成" : "取消生成")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(generationMessage != nil ? Color.blue : Color.red)
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 15)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isGenerating)
    }
    
    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        isProgressMinimized = false
        currentFileName = ""
        generationProgress = (0, 0)
        generationMessage = nil
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("📖 知识卡片")
                    .font(.title2.bold())
                Text("浏览和复习您的知识卡片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Stats
            HStack(spacing: 12) {
                Text("\(allCards.count) 张卡片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.1)))
                
                let needReviewCount = allCards.filter { $0.needsReview }.count
                if needReviewCount > 0 {
                    Text("\(needReviewCount) 待复习")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange))
                }
            }
            
            // Progress indicator
            if !displayedCards.isEmpty {
                Text("\(currentIndex + 1) / \(displayedCards.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.blue)
            }
            
            // Generate button with options
            Menu {
                Button {
                    generationTask = Task { await generateCards(category: nil, tag: nil) }
                } label: {
                    Label("生成最近文件 (50个)", systemImage: "clock")
                }
                
                Divider()
                
                Menu("按分类生成") {
                    ForEach(PARACategory.allCases) { cat in
                        Button {
                            generationTask = Task { await generateCards(category: cat, tag: nil) }
                        } label: {
                            Label(cat.displayName, systemImage: cat.icon)
                        }
                    }
                }
                
                Menu("按标签生成") {
                    ForEach(appState.sidebarTags.prefix(15)) { tag in
                        Button {
                            generationTask = Task { await generateCards(category: nil, tag: tag) }
                        } label: {
                            HStack {
                                Circle().fill(tag.swiftUIColor).frame(width: 8, height: 8)
                                Text(tag.name)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Regenerate section
                Menu("🔄 重新生成") {
                    Button {
                        generationTask = Task { await generateCards(category: nil, tag: nil, forceRegenerate: true) }
                    } label: {
                        Label("重新生成最近文件", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Divider()
                    
                    ForEach(PARACategory.allCases) { cat in
                        Button {
                            generationTask = Task { await generateCards(category: cat, tag: nil, forceRegenerate: true) }
                        } label: {
                            Label("重新生成: \(cat.displayName)", systemImage: cat.icon)
                        }
                    }
                }
            } label: {
                Label("生成卡片", systemImage: "sparkles")
            }
            .menuStyle(.borderlessButton)
            .disabled(isGenerating)
            
            Button {
                Task { await loadCards() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
    }
    
    // MARK: - Filter Bar
    private var filterBar: some View {
        HStack(spacing: 16) {
            // Mode Picker
            Picker("模式", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .onChange(of: viewMode) { _, _ in
                applyFilters()
            }
            
            Divider().frame(height: 20)
            
            // Category Filter
            Menu {
                Button("全部分类") {
                    selectedCategory = nil
                    applyFilters()
                }
                Divider()
                ForEach(PARACategory.allCases) { cat in
                    Button {
                        selectedCategory = cat
                        applyFilters()
                    } label: {
                        Label(cat.displayName, systemImage: cat.icon)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: selectedCategory?.icon ?? "folder")
                    Text(selectedCategory?.displayName ?? "分类筛选")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(selectedCategory != nil ? Color.blue.opacity(0.1) : Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            
            // Tag Filter
            Menu {
                Button("全部标签") {
                    selectedTag = nil
                    applyFilters()
                }
                Divider()
                ForEach(appState.sidebarTags.prefix(20)) { tag in
                    Button {
                        selectedTag = tag
                        applyFilters()
                    } label: {
                        HStack {
                            Circle().fill(tag.swiftUIColor).frame(width: 8, height: 8)
                            Text(tag.name)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "tag")
                    Text(selectedTag?.name ?? "标签筛选")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(selectedTag != nil ? Color.green.opacity(0.1) : Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            
            // Clear filters
            if selectedCategory != nil || selectedTag != nil {
                Button {
                    selectedCategory = nil
                    selectedTag = nil
                    applyFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.02))
    }
    
    // MARK: - Content
    @ViewBuilder
    private var contentView: some View {
        if isGenerating {
            generationProgressView
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedCards.isEmpty {
            emptyStateView
        } else {
            cardDisplayView
        }
    }
    
    private var generationProgressView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            if generationProgress.total > 0 {
                VStack(spacing: 8) {
                    Text("正在生成知识卡片...")
                        .font(.headline)
                    Text("\(generationProgress.current) / \(generationProgress.total)")
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(Color.blue)
                    ProgressView(value: Double(generationProgress.current), total: Double(generationProgress.total))
                        .frame(width: 200)
                }
            }
            
            Text("AI 正在分析文件内容并生成知识卡片")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: allCards.isEmpty ? "sparkles" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(allCards.isEmpty ? Color.blue : Color.green)
            
            Text(allCards.isEmpty ? "还没有知识卡片" : (viewMode == .review ? "没有需要复习的卡片" : "没有符合条件的卡片"))
                .font(.title2.bold())
            
            Text(allCards.isEmpty ? "点击「生成卡片」按钮开始" : (viewMode == .review ? "所有卡片都已复习过" : "尝试调整筛选条件"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if allCards.isEmpty {
                Button {
                    Task { await generateCards() }
                } label: {
                    Label("生成知识卡片", systemImage: "sparkles")
                        .font(.headline)
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var cardDisplayView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Card
            let card = displayedCards[currentIndex]
            VStack(spacing: 20) {
                // Title
                Text(card.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                
                // Summary (Front)
                Text(card.summary)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                
                if showAnswer {
                    Divider()
                    
                    // Key Points (Answer)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关键点")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(card.keyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(point)
                                    .font(.body)
                            }
                        }
                    }
                    .padding()
                    
                    // Keywords
                    if !card.keywords.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(card.keywords, id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 600)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            )
            
            Spacer()
            
            // Actions
            HStack(spacing: 20) {
                // Navigation
                Button {
                    withAnimation {
                        if currentIndex > 0 {
                            currentIndex -= 1
                            showAnswer = false
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)
                .foregroundStyle(currentIndex == 0 ? Color.secondary : Color.blue)
                
                if !showAnswer {
                    Button {
                        withAnimation { showAnswer = true }
                    } label: {
                        Label("显示答案", systemImage: "eye")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    // Rate buttons
                    HStack(spacing: 16) {
                        rateButton(icon: "xmark.circle.fill", label: "再看一遍", color: .red, quality: .again)
                        rateButton(icon: "hand.thumbsdown.fill", label: "有点难", color: .orange, quality: .hard)
                        rateButton(icon: "hand.thumbsup.fill", label: "记住了", color: .green, quality: .good)
                        rateButton(icon: "star.fill", label: "太简单", color: .blue, quality: .easy)
                    }
                }
                
                Button {
                    withAnimation {
                        if currentIndex < displayedCards.count - 1 {
                            currentIndex += 1
                            showAnswer = false
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= displayedCards.count - 1)
                .foregroundStyle(currentIndex >= displayedCards.count - 1 ? Color.secondary : Color.blue)
            }
            .padding(.bottom, 32)
        }
        .padding(24)
    }
    
    private func rateButton(icon: String, label: String, color: Color, quality: ReviewQuality) -> some View {
        Button {
            markReviewed(quality: quality)
        } label: {
            VStack {
                Image(systemName: icon)
                    .font(.title)
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(color)
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Data Loading
    private func loadCards() async {
        isLoading = true
        allCards = await KnowledgeLinkService.shared.getAllCards()
        applyFilters()
        currentIndex = 0
        showAnswer = false
        isLoading = false
    }
    
    private func applyFilters() {
        var filtered = allCards
        
        // Mode filter
        if viewMode == .review {
            filtered = filtered.filter { $0.needsReview }
        }
        
        // Category filter (need to get file info)
        // Note: KnowledgeCard only has fileId, so we filter by checking file metadata
        if let category = selectedCategory {
            Task {
                var categoryFiltered: [KnowledgeCard] = []
                for card in filtered {
                    if let file = await getFile(for: card.fileId), file.category == category {
                        categoryFiltered.append(card)
                    }
                }
                await MainActor.run {
                    displayedCards = categoryFiltered
                    currentIndex = 0
                }
            }
            return
        }
        
        // Tag filter
        if let tag = selectedTag {
            Task {
                var tagFiltered: [KnowledgeCard] = []
                for card in filtered {
                    if let file = await getFile(for: card.fileId), file.tags.contains(where: { $0.id == tag.id }) {
                        tagFiltered.append(card)
                    }
                }
                await MainActor.run {
                    displayedCards = tagFiltered
                    currentIndex = 0
                }
            }
            return
        }
        
        displayedCards = filtered
        currentIndex = min(currentIndex, max(0, displayedCards.count - 1))
    }
    
    private func getFile(for fileId: UUID) async -> ManagedFile? {
        let files = await DatabaseManager.shared.getRecentFiles(limit: 500)
        return files.first { $0.id == fileId }
    }
    
    private func generateCards(category: PARACategory? = nil, tag: Tag? = nil, forceRegenerate: Bool = false) async {
        isGenerating = true
        generationProgress = (0, 0)
        currentFileName = ""
        generationMessage = nil
        
        // Fetch files based on filter
        var allFiles: [ManagedFile] = []
        
        if let category = category {
            // Get files for specific category
            allFiles = await DatabaseManager.shared.getFilesForCategory(category)
        } else if let tag = tag {
            // Get files with specific tag
            let allRecentFiles = await DatabaseManager.shared.getRecentFiles(limit: 200)
            allFiles = allRecentFiles.filter { file in
                file.tags.contains { $0.id == tag.id }
            }
        } else {
            // Default: recent files
            allFiles = await DatabaseManager.shared.getRecentFiles(limit: 50)
        }
        
        // Filter files - skip existing cards check if force regenerating
        var filesToProcess: [ManagedFile] = []
        if forceRegenerate {
            // Process all files (regenerate even existing cards)
            filesToProcess = allFiles
        } else {
            // Only process files without cards
            for file in allFiles {
                if await KnowledgeLinkService.shared.getCard(for: file.id) == nil {
                    filesToProcess.append(file)
                }
            }
        }
        
        if filesToProcess.isEmpty {
            await loadCards()
            // Show message instead of immediately closing
            generationMessage = forceRegenerate ? "没有找到可处理的文件" : "所有文件都已生成卡片\n没有新文件需要处理"
            return
        }
        
        generationProgress = (0, filesToProcess.count)
        
        // Process files with cancellation support
        for (index, file) in filesToProcess.enumerated() {
            // Check if cancelled
            if Task.isCancelled {
                break
            }
            
            // Update UI
            await MainActor.run {
                currentFileName = file.displayName
                generationProgress = (index, filesToProcess.count)
            }
            
            // Generate card
            _ = await KnowledgeLinkService.shared.generateCardWithAI(for: file, forceRegenerate: forceRegenerate)
            
            // Update progress
            await MainActor.run {
                generationProgress = (index + 1, filesToProcess.count)
            }
            
            // Small delay to avoid API rate limiting
            if index < filesToProcess.count - 1 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            }
        }
        
        await loadCards()
        
        // Show completion message
        let completedCount = generationProgress.current
        generationMessage = "生成完成！\n成功创建 \(completedCount) 张卡片"
        currentFileName = ""
    }
    
    private func markReviewed(quality: ReviewQuality) {
        guard currentIndex < displayedCards.count else { return }
        
        let card = displayedCards[currentIndex]
        Task {
            await KnowledgeLinkService.shared.markCardReviewed(card.id)
        }
        
        withAnimation {
            showAnswer = false
            if currentIndex < displayedCards.count - 1 {
                currentIndex += 1
            } else {
                Task { await loadCards() }
            }
        }
    }
    
    enum ReviewQuality {
        case again, hard, good, easy
    }
}

#Preview {
    CardReviewView()
        .environmentObject(AppState())
        .frame(width: 900, height: 700)
}
