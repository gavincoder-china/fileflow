import SwiftUI

struct FileStackOrganizerView: View {
    let fileURLs: [URL]
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @StateObject private var session = BatchSessionManager()
    @State private var currentIndex = 0
    @State private var processedIDs: Set<URL> = []
    
    @Environment(\.dismiss) private var dismiss
    
    // Auto Process State
    @State private var isAutoProcessing = false
    @State private var autoProcessProgress = 0.0
    @State private var autoProcessStatus = ""
    
    var body: some View {
        ZStack {
            AuroraBackground()
                .blur(radius: 20)
                .ignoresSafeArea()
            
            if isAutoProcessing {
                // Auto Processing UI
                VStack(spacing: 24) {
                    ProgressView(value: autoProcessProgress, total: Double(fileURLs.count - currentIndex)) {
                        Text(autoProcessStatus)
                            .font(.headline)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 300)
                    .padding()
                    .glass(cornerRadius: 16)
                    
                    Button("取消") {
                        isAutoProcessing = false
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text("待整理文件 \(currentIndex + 1)/\(fileURLs.count)")
                                .font(.headline)
                            Text("剩余 \(fileURLs.count - currentIndex - 1) 个文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Auto Process Button
                        if currentIndex < fileURLs.count {
                            Button {
                                startAutoProcess()
                            } label: {
                                Label("AI 一键处理剩余", systemImage: "sparkles")
                                    .font(.subheadline)
                            }
                            .buttonStyle(GlassButtonStyle())
                            .padding(.trailing, 8)
                        }
                        
                        Button {
                            onCancel()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    
                    // Card Stack
                    ZStack {
                        // Background placeholder when finished
                        if currentIndex >= fileURLs.count {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.green)
                                Text("全部完成")
                                    .font(.title)
                            }
                            .transition(.opacity)
                        }
                        
                        // Cards
                        // Show only next few cards for performance + visual
                        ForEach(visibleIndices(), id: \.self) { index in
                            let url = fileURLs[index]
                            let isTop = index == currentIndex
                            let order = index - currentIndex
                            
                            // Calculate transformation
                            let scale = 1.0 - (Double(order) * 0.05)
                            let yOffset = Double(order) * 15.0
                            let opacity = 1.0 - (Double(order) * 0.2)
                            
                            Group {
                                if isTop {
                                    if let vm = session.viewModel(for: url) {
                                        SingleFileCardView(
                                            viewModel: vm,
                                            onSave: {
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                    processedIDs.insert(url)
                                                    currentIndex += 1
                                                    checkCompletion()
                                                }
                                            },
                                            onSkip: {
                                                withAnimation {
                                                    currentIndex += 1
                                                    checkCompletion()
                                                }
                                            }
                                        )
                                        .transition(.asymmetric(
                                            insertion: .identity,
                                            removal: .offset(x: 500, y: 100).combined(with: .opacity)
                                        ))
                                    } else {
                                        ProgressView()
                                    }
                                } else {
                                    // Ghost Card
                                    GhostFileCard(url: url)
                                }
                            }
                            .zIndex(Double(fileURLs.count - index)) // Higher index = Lower Z (Background)
                            .scaleEffect(scale)
                            .offset(y: yOffset)
                            .opacity(opacity)
                            .allowsHitTesting(isTop) // Only top card interactive
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 700, height: 800)
        .onAppear {
            session.prepare(urls: fileURLs)
        }
    }
    
    private func checkCompletion() {
        if currentIndex >= fileURLs.count {
            // Allow closure animation to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete()
                dismiss()
            }
        }
    }
    
    private func visibleIndices() -> [Int] {
        let maxVisible = 3
        let start = currentIndex
        let end = min(currentIndex + maxVisible, fileURLs.count)
        if start >= end { return [] }
        return Array(start..<end).reversed() // Paint back to front
    }
    
    private func startAutoProcess() {
        isAutoProcessing = true
        autoProcessStatus = "准备处理..."
        
        Task {
            let remaining = fileURLs[currentIndex...]
            var processed = 0.0
            
            for url in remaining {
                autoProcessStatus = "正在处理: \(url.lastPathComponent)"
                
                if let vm = session.viewModel(for: url) {
                    // Wait for analysis if needed
                    while vm.isAnalyzing {
                        autoProcessStatus = "等待 AI 分析: \(url.lastPathComponent)"
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s poll
                    }
                    
                    if !vm.generatedFileName.isEmpty {
                       await vm.saveFile()
                    }
                }
                
                processed += 1
                autoProcessProgress = processed
            }
            
            await MainActor.run {
                onComplete()
                dismiss()
            }
        }
    }
}

// MARK: - Batch Session Manager
@MainActor
class BatchSessionManager: ObservableObject {
    @Published var viewModels: [URL: FileOrganizeViewModel] = [:]
    
    func prepare(urls: [URL]) {
        for url in urls {
            if viewModels[url] == nil {
                let vm = FileOrganizeViewModel(fileURL: url)
                viewModels[url] = vm
                
                // Start parallel analysis immediately
                Task {
                    await vm.loadInitialData()
                }
            }
        }
    }
    
    func viewModel(for url: URL) -> FileOrganizeViewModel? {
        return viewModels[url]
    }
}

// MARK: - Single File Card Wrapper
struct SingleFileCardView: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    let onSave: () -> Void
    let onSkip: () -> Void
    
    @State private var showingSubcategoryInput = false
    @State private var newSubcategoryName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                FileOrganizeFormView(
                    viewModel: viewModel,
                    showingSubcategoryInput: $showingSubcategoryInput,
                    newSubcategoryName: $newSubcategoryName
                )
            }
            
            // Footer
            HStack {
                Button("跳过") {
                    onSkip()
                }
                .buttonStyle(GlassButtonStyle())
                
                Spacer()
                
                Button("保存并处理下一个") {
                    Task {
                        await viewModel.saveFile()
                        onSave() // Trigger transition
                    }
                }
                .buttonStyle(GlassButtonStyle(isActive: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isSaving)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .background(.ultraThinMaterial) // Card background
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 32)
    }
}

// MARK: - Ghost Card
struct GhostFileCard: View {
    let url: URL
    
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding()
            Spacer()
        }
        .frame(height: 600) // Approx height match
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 32)
    }
}
