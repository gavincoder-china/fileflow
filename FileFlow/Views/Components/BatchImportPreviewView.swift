//
//  BatchImportPreviewView.swift
//  FileFlow
//
//  批量导入预览视图
//  提供预览模式、批量标签、进度显示和撤销功能
//

import SwiftUI

// MARK: - Batch Import Preview View
struct BatchImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BatchImportViewModel
    
    init(files: [URL]) {
        _viewModel = StateObject(wrappedValue: BatchImportViewModel(urls: files))
    }
    
    var body: some View {
        ZStack {
            AuroraBackground()
                .blur(radius: 20)
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                if viewModel.isProcessing {
                    progressView
                } else if viewModel.showResults {
                    resultsView
                } else {
                    previewContent
                }
                
                // Footer
                footerView
            }
        }
        .frame(width: 900, height: 700)
        .task {
            await viewModel.prepareFiles()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("批量导入预览")
                    .font(.title2.bold())
                Text("\(viewModel.items.count) 个文件待处理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Options Menu
            Menu {
                Toggle("启用 AI 分析", isOn: $viewModel.options.enableAIAnalysis)
                Toggle("记住来源路径", isOn: $viewModel.options.rememberSourcePath)
                
                Divider()
                
                Menu("冲突处理") {
                    ForEach(ConflictResolution.allCases) { resolution in
                        Button {
                            viewModel.options.conflictResolution = resolution
                        } label: {
                            HStack {
                                Image(systemName: resolution.icon)
                                Text(resolution.displayName)
                                if viewModel.options.conflictResolution == resolution {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Menu("重复处理") {
                    ForEach(DuplicateHandling.allCases) { handling in
                        Button {
                            viewModel.options.duplicateHandling = handling
                        } label: {
                            HStack {
                                Image(systemName: handling.icon)
                                Text(handling.displayName)
                                if viewModel.options.duplicateHandling == handling {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Preview Content
    private var previewContent: some View {
        VStack(spacing: 16) {
            // Batch Tags Input
            batchTagsInput
            
            // File List
            List {
                ForEach($viewModel.items) { $item in
                    ImportFileItemRow(item: $item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Batch Tags Input
    private var batchTagsInput: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.blue)
            
            TextField("批量添加标签 (逗号分隔)", text: $viewModel.batchTagsInput)
                .textFieldStyle(.plain)
            
            if !viewModel.batchTagsInput.isEmpty {
                Button {
                    viewModel.batchTagsInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Progress View
    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView(value: viewModel.progress.percentage)
                .progressViewStyle(.linear)
                .frame(width: 400)
            
            Text(viewModel.progress.displayText)
                .font(.headline)
            
            Text(viewModel.progress.currentFileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Results View
    private var resultsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: viewModel.hasErrors ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(viewModel.hasErrors ? .orange : .green)
            
            Text("导入完成")
                .font(.title.bold())
            
            HStack(spacing: 32) {
                StatBadge(label: "成功", value: viewModel.session?.successCount ?? 0, color: .green)
                StatBadge(label: "跳过", value: viewModel.session?.skippedCount ?? 0, color: .yellow)
                StatBadge(label: "失败", value: viewModel.session?.failedCount ?? 0, color: .red)
            }
            
            if viewModel.session?.canUndo == true {
                Button {
                    Task { await viewModel.undoImport() }
                } label: {
                    Label("撤销此次导入", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            // Select All / None
            Button {
                viewModel.toggleSelectAll()
            } label: {
                Text(viewModel.allSelected ? "取消全选" : "全选")
            }
            .buttonStyle(.bordered)
            
            Text("\(viewModel.selectedCount) 个已选")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if viewModel.showResults {
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button {
                    Task { await viewModel.executeImport() }
                } label: {
                    Label("开始导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedCount == 0 || viewModel.isProcessing)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Import File Item Row
struct ImportFileItemRow: View {
    @Binding var item: ImportFileItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
            
            // Status Icon
            statusIcon
            
            // File Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(item.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !item.suggestedTags.isEmpty {
                        ForEach(item.suggestedTags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Category Picker
            Picker("", selection: $item.selectedCategory) {
                ForEach(PARACategory.allCases) { category in
                    Label(category.displayName, systemImage: category.icon)
                        .tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(item.isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusBorderColor, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .analyzing:
            ProgressView()
                .scaleEffect(0.6)
        case .duplicate:
            Image(systemName: "doc.on.doc.fill")
                .foregroundStyle(.purple)
        case .conflict:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        default:
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
        }
    }
    
    private var statusBorderColor: Color {
        switch item.status {
        case .duplicate: return .purple.opacity(0.3)
        case .conflict: return .orange.opacity(0.3)
        default: return .clear
        }
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ViewModel
@MainActor
class BatchImportViewModel: ObservableObject {
    @Published var items: [ImportFileItem] = []
    @Published var options = ImportOptions.default
    @Published var batchTagsInput = ""
    @Published var progress = ImportProgress()
    @Published var isProcessing = false
    @Published var showResults = false
    @Published var session: BatchImportSession?
    @Published var results: [ImportResult] = []
    
    private let sourceURLs: [URL]
    
    var selectedCount: Int {
        items.filter { $0.isSelected }.count
    }
    
    var allSelected: Bool {
        items.allSatisfy { $0.isSelected }
    }
    
    var hasErrors: Bool {
        (session?.failedCount ?? 0) > 0
    }
    
    init(urls: [URL]) {
        self.sourceURLs = urls
    }
    
    func prepareFiles() async {
        // Create items
        items = sourceURLs.map { ImportFileItem(url: $0) }
        
        // Calculate hashes
        progress.phase = .hashing
        progress.total = items.count
        items = await BatchImportService.shared.calculateHashes(for: items) { current, total in
            Task { @MainActor in
                self.progress.current = current
            }
        }
        
        // Detect duplicates
        items = await BatchImportService.shared.detectDuplicates(items: items)
        
        // AI Analysis (if enabled)
        if options.enableAIAnalysis {
            progress.phase = .analyzing
            items = await BatchImportService.shared.analyzeFiles(items: items) { current, total, fileName in
                Task { @MainActor in
                    self.progress.current = current
                    self.progress.currentFileName = fileName
                }
            }
        }
        
        progress.phase = .complete
    }
    
    func toggleSelectAll() {
        let newValue = !allSelected
        for i in 0..<items.count {
            items[i].isSelected = newValue
        }
    }
    
    func executeImport() async {
        isProcessing = true
        progress = ImportProgress()
        progress.phase = .importing
        progress.total = selectedCount
        
        // Parse batch tags
        options.applyBatchTags = batchTagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let result = await BatchImportService.shared.executeImport(
            items: items,
            options: options
        ) { current, total, fileName in
            Task { @MainActor in
                self.progress.current = current
                self.progress.currentFileName = fileName
            }
        }
        
        session = result.session
        results = result.results
        isProcessing = false
        showResults = true
    }
    
    func undoImport() async {
        guard let session = session else { return }
        
        isProcessing = true
        let result = await BatchImportService.shared.undoSession(session)
        isProcessing = false
        
        Logger.success("Undo complete: \(result.success) files removed, \(result.failed) failed")
    }
}
