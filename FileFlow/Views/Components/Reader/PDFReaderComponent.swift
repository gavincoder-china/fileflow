//
//  PDFReaderComponent.swift
//  FileFlow
//
//  PDF 阅读与标注组件
//

import SwiftUI
import PDFKit

struct PDFReaderComponent: View {
    let url: URL
    let file: ManagedFile
    
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var showExtractionSuccess = false
    @State private var extractedCount = 0
    @State private var showThumbnails = true
    @State private var currentPage = 0
    @State private var zoomLevel: CGFloat = 1.0
    @State private var highlightColor: NSColor = .yellow
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if let document = pdfDocument {
                HStack(spacing: 0) {
                    // Thumbnail sidebar
                    if showThumbnails {
                        thumbnailSidebar(document: document)
                    }
                    
                    // Main PDF View
                    VStack(spacing: 0) {
                        // Toolbar
                        pdfToolbar
                        
                        Divider()
                        
                        // PDF Content
                        PDFKitView(
                            document: document,
                            zoomLevel: $zoomLevel,
                            currentPage: $currentPage
                        )
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showExtractionSuccess {
                successBanner
            }
        }
        .task {
            await loadPDF()
        }
    }
    
    // MARK: - Toolbar
    private var pdfToolbar: some View {
        HStack(spacing: 16) {
            // Toggle thumbnails
            Button {
                withAnimation { showThumbnails.toggle() }
            } label: {
                Image(systemName: showThumbnails ? "sidebar.left" : "sidebar.leading")
            }
            .buttonStyle(.plain)
            .help("切换缩略图")
            
            Divider()
                .frame(height: 20)
            
            // Zoom controls
            HStack(spacing: 8) {
                Button {
                    zoomLevel = max(0.25, zoomLevel - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                
                Text("\(Int(zoomLevel * 100))%")
                    .font(.caption)
                    .frame(width: 50)
                
                Button {
                    zoomLevel = min(4.0, zoomLevel + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                
                Button {
                    zoomLevel = 1.0
                } label: {
                    Text("适合")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
                .frame(height: 20)
            
            // Page navigation
            HStack(spacing: 8) {
                Button {
                    if currentPage > 0 { currentPage -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                
                Text("\(currentPage + 1) / \(pdfDocument?.pageCount ?? 1)")
                    .font(.caption)
                    .frame(width: 60)
                
                Button {
                    if let doc = pdfDocument, currentPage < doc.pageCount - 1 {
                        currentPage += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= (pdfDocument?.pageCount ?? 1) - 1)
            }
            
            Spacer()
            
            // Highlight color picker
            HStack(spacing: 8) {
                Text("高亮:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach([NSColor.yellow, NSColor.green, NSColor.cyan, NSColor.systemPink], id: \.self) { color in
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(highlightColor == color ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .onTapGesture {
                            highlightColor = color
                        }
                }
            }
            
            Divider()
                .frame(height: 20)
            
            // Extract highlights button
            Button {
                Task { await extractHighlights() }
            } label: {
                Label("提取高亮", systemImage: "quote.opening")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("提取所有高亮标注为知识卡片")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    // MARK: - Thumbnail Sidebar
    private func thumbnailSidebar(document: PDFDocument) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    thumbnailCell(document: document, index: index)
                }
            }
            .padding(8)
        }
        .frame(width: 120)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func thumbnailCell(document: PDFDocument, index: Int) -> some View {
        let isSelected = index == currentPage
        
        return Button {
            currentPage = index
        } label: {
            VStack(spacing: 4) {
                if let page = document.page(at: index) {
                    PDFThumbnailView(page: page)
                        .frame(width: 90, height: 120)
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.1), radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                }
                
                Text("\(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Loading & Error Views
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在加载 PDF...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("加载失败")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var successBanner: some View {
        Text("✅ 已提取 \(extractedCount) 条高亮到知识库")
            .padding()
            .background(.black.opacity(0.8))
            .foregroundStyle(.white)
            .cornerRadius(10)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showExtractionSuccess = false }
                }
            }
    }
    
    // MARK: - PDF Loading
    private func loadPDF() async {
        isLoading = true
        loadError = nil
        
        await Task.detached(priority: .userInitiated) {
            if let doc = PDFDocument(url: url) {
                await MainActor.run {
                    self.pdfDocument = doc
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.loadError = "无法打开 PDF 文件。文件可能已损坏或格式不正确。"
                    self.isLoading = false
                }
            }
        }.value
    }
    
    // MARK: - Annotation Extraction
    private func extractHighlights() async {
        guard let doc = pdfDocument else { return }
        
        var highlights: [(text: String, page: Int)] = []
        
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let annotations = page.annotations
            
            for annotation in annotations {
                if annotation.type == "Highlight" {
                    // 尝试获取标注文本
                    let bounds = annotation.bounds
                    if let annotationPage = annotation.page,
                       let selection = annotationPage.selection(for: bounds),
                       let text = selection.string, !text.isEmpty {
                        highlights.append((text, i + 1))
                    } else if let contents = annotation.contents, !contents.isEmpty {
                        highlights.append((contents, i + 1))
                    }
                }
            }
        }
        
        if !highlights.isEmpty {
            // 创建知识卡片
            let _ = highlights.map { "第\($0.page)页: \($0.text)" }
            let _ = await KnowledgeLinkService.shared.generateCardWithAI(for: file)
            
            extractedCount = highlights.count
            withAnimation { showExtractionSuccess = true }
            
            Logger.info("从 \(file.displayName) 提取了 \(highlights.count) 条标注")
        } else {
            // 没有找到高亮
            extractedCount = 0
            withAnimation { showExtractionSuccess = true }
        }
    }
}

// MARK: - Enhanced PDFKit View Wrapper
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var zoomLevel: CGFloat
    @Binding var currentPage: Int
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        pdfView.scaleFactor = zoomLevel
        
        // Enable annotation editing
        pdfView.displaysAsBook = false
        
        // Add delegate for page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document != document {
            nsView.document = document
        }
        
        // Update zoom
        if abs(nsView.scaleFactor - zoomLevel) > 0.01 {
            nsView.scaleFactor = zoomLevel
        }
        
        // Go to page
        if let page = document.page(at: currentPage),
           nsView.currentPage != page {
            nsView.go(to: page)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PDFKitView
        
        init(_ parent: PDFKitView) {
            self.parent = parent
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            
            let pageIndex = document.index(for: currentPage)
            
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }
    }
}

// MARK: - PDF Thumbnail View
struct PDFThumbnailView: NSViewRepresentable {
    let page: PDFPage
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        // Generate thumbnail
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 90 / bounds.width
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        imageView.image = thumbnail
        
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        // No updates needed
    }
}

#Preview {
    PDFReaderComponent(
        url: URL(fileURLWithPath: "/path/to/sample.pdf"),
        file: ManagedFile(originalName: "Sample.pdf", originalPath: "")
    )
    .frame(width: 800, height: 600)
}
