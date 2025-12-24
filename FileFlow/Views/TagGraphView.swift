//
//  TagGraphView.swift
//  FileFlow
//
//  知识图谱视图 - 参考思维导图风格设计
//

import SwiftUI
import Combine

struct TagGraphView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var nodes: [GraphNode] = []
    @State private var links: [GraphLink] = []
    @State private var selectedNodeId: UUID?
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    // Simulation
    @State private var timer: Timer?
    
    // Detail sidebar
    @State private var selectedTag: Tag?
    @State private var associatedFiles: [ManagedFile] = []
    @State private var showingDetail = false
    
    // Hover state
    @State private var hoveredNodeId: UUID?
    
    // 预定义的美观配色方案
    private let colorPalette: [Color] = [
        Color(red: 0.22, green: 0.56, blue: 0.89),  // 蓝色
        Color(red: 0.10, green: 0.74, blue: 0.61),  // 青绿
        Color(red: 0.95, green: 0.61, blue: 0.07),  // 橙色
        Color(red: 0.91, green: 0.30, blue: 0.24),  // 红色
        Color(red: 0.61, green: 0.35, blue: 0.71),  // 紫色
        Color(red: 0.20, green: 0.60, blue: 0.86),  // 天蓝
        Color(red: 0.95, green: 0.77, blue: 0.06),  // 金黄
        Color(red: 0.18, green: 0.80, blue: 0.44),  // 绿色
        Color(red: 0.94, green: 0.50, blue: 0.50),  // 珊瑚红
        Color(red: 0.56, green: 0.27, blue: 0.68),  // 深紫
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            graphArea
            
            if showingDetail, let tag = selectedTag {
                detailSidebar(for: tag)
            }
        }
        .onAppear {
            loadGraphData()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: appState.allTags) { _, _ in
            loadGraphData()
        }
    }
    
    // MARK: - Graph Area
    
    private var graphArea: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedNodeId = nil
                            selectedTag = nil
                            showingDetail = false
                        }
                    }
                
                // 图谱画布
                graphCanvas(size: geometry.size)
                
                // 控制按钮
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        controlButtons
                    }
                }
                .padding(24)
            }
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { value in
                        lastOffset = offset
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(0.3, min(3.0, value))
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateHoverState(at: location)
                case .ended:
                    hoveredNodeId = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    scale = min(3.0, scale + 0.2)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(GraphControlButtonStyle())
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    scale = max(0.3, scale - 0.2)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(GraphControlButtonStyle())
            
            Button {
                withAnimation(.spring(response: 0.4)) {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(GraphControlButtonStyle())
        }
    }
    
    // MARK: - Graph Canvas
    
    private func graphCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            // 应用缩放和平移
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: offset.width / scale, y: offset.height / scale)
            
            // 绘制连接线（带标签）
            drawLinks(context: &context)
            
            // 绘制节点
            drawNodes(context: &context)
        }
    }
    
    // MARK: - Draw Links
    
    private func drawLinks(context: inout GraphicsContext) {
        for link in links {
            guard let startNode = nodes.first(where: { $0.id == link.source }),
                  let endNode = nodes.first(where: { $0.id == link.target }) else { continue }
            
            let isRelated = selectedNodeId != nil &&
                (link.source == selectedNodeId || link.target == selectedNodeId)
            let isHoverRelated = hoveredNodeId != nil &&
                (link.source == hoveredNodeId || link.target == hoveredNodeId)
            
            // 计算透明度
            var opacity: Double = 0.3
            if selectedNodeId != nil {
                opacity = isRelated ? 0.8 : 0.05
            }
            if isHoverRelated {
                opacity = max(opacity, 0.6)
            }
            
            // 计算起点和终点（从节点边缘开始）
            let dx = endNode.position.x - startNode.position.x
            let dy = endNode.position.y - startNode.position.y
            let dist = sqrt(dx * dx + dy * dy)
            
            guard dist > 0 else { continue }
            
            let startPoint = CGPoint(
                x: startNode.position.x + (dx / dist) * startNode.radius,
                y: startNode.position.y + (dy / dist) * startNode.radius
            )
            let endPoint = CGPoint(
                x: endNode.position.x - (dx / dist) * endNode.radius,
                y: endNode.position.y - (dy / dist) * endNode.radius
            )
            
            // 绘制直线（更简洁）
            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            let lineWidth: CGFloat = isHoverRelated || isRelated ? 2.5 : 1.5
            let lineColor = Color.gray.opacity(opacity)
            
            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            
            // 在连接线中间绘制关系权重（如果权重大于1）
            if link.weight > 1 && (isRelated || isHoverRelated || opacity > 0.2) {
                let midPoint = CGPoint(
                    x: (startPoint.x + endPoint.x) / 2,
                    y: (startPoint.y + endPoint.y) / 2
                )
                
                let labelText = Text("\(link.weight)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(opacity * 1.5))
                
                context.draw(labelText, at: midPoint, anchor: .center)
            }
        }
    }
    
    // MARK: - Draw Nodes
    
    private func drawNodes(context: inout GraphicsContext) {
        // 按大小排序，先画小的（这样大的会在上面）
        let sortedNodes = nodes.sorted { $0.radius < $1.radius }
        
        for node in sortedNodes {
            let isSelected = selectedNodeId == node.id
            let isHovered = hoveredNodeId == node.id
            
            let isRelated = selectedNodeId != nil && links.contains {
                ($0.source == selectedNodeId && $0.target == node.id) ||
                ($0.source == node.id && $0.target == selectedNodeId)
            }
            
            // 计算透明度
            var baseOpacity: Double = 1.0
            if selectedNodeId != nil && !isSelected && !isRelated {
                baseOpacity = 0.15
            }
            if isHovered {
                baseOpacity = 1.0
            }
            
            // 缩放效果
            let scaleFactor: CGFloat = isHovered ? 1.15 : (isSelected ? 1.1 : 1.0)
            let currentRadius = node.radius * scaleFactor
            
            let circleRect = CGRect(
                x: node.position.x - currentRadius,
                y: node.position.y - currentRadius,
                width: currentRadius * 2,
                height: currentRadius * 2
            )
            
            // 绘制阴影
            if isHovered || isSelected {
                context.drawLayer { shadowContext in
                    shadowContext.addFilter(.shadow(color: node.color.opacity(0.5), radius: 15))
                    shadowContext.fill(Path(ellipseIn: circleRect), with: .color(node.color.opacity(baseOpacity)))
                }
            }
            
            // 绘制节点圆形
            let gradient = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [
                    node.color.opacity(baseOpacity),
                    node.color.opacity(baseOpacity * 0.85)
                ]),
                center: CGPoint(x: node.position.x - currentRadius * 0.2, y: node.position.y - currentRadius * 0.2),
                startRadius: 0,
                endRadius: currentRadius * 1.5
            )
            
            context.fill(Path(ellipseIn: circleRect), with: gradient)
            
            // 高亮边框
            if isSelected || isHovered {
                context.stroke(
                    Path(ellipseIn: circleRect),
                    with: .color(.white.opacity(0.9)),
                    lineWidth: isHovered ? 3 : 2
                )
            }
            
            // 节点内文字（如果节点足够大）
            if currentRadius >= 20 || isSelected || isHovered {
                let textOpacity = baseOpacity
                
                // 根据背景颜色选择文字颜色
                let textColor: Color = getContrastTextColor(for: node.color)
                
                // 计算合适的字体大小
                let fontSize = min(currentRadius * 0.45, 16.0)
                let displayName = truncateName(node.name, maxLength: Int(currentRadius / 4))
                
                let text = Text(displayName)
                    .font(.system(size: max(fontSize, 10), weight: .semibold, design: .rounded))
                    .foregroundColor(textColor.opacity(textOpacity))
                
                context.draw(text, at: node.position, anchor: .center)
            }
            
            // 小节点：在外部显示名称
            if currentRadius < 20 && (isHovered || isSelected || isRelated) {
                let textColor: Color = colorScheme == .dark ? .white : .black
                let text = Text(node.name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(textColor.opacity(0.9))
                
                context.draw(text, at: CGPoint(x: node.position.x, y: node.position.y + currentRadius + 12), anchor: .top)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getContrastTextColor(for backgroundColor: Color) -> Color {
        // 简单的亮度检测
        let components = NSColor(backgroundColor).cgColor.components ?? [0, 0, 0]
        let brightness = (components[0] * 299 + components[1] * 587 + components[2] * 114) / 1000
        return brightness > 0.5 ? .black : .white
    }
    
    private func truncateName(_ name: String, maxLength: Int) -> String {
        if name.count <= max(maxLength, 4) {
            return name
        }
        return String(name.prefix(max(maxLength, 3))) + "…"
    }
    
    private func updateHoverState(at location: CGPoint) {
        let graphPoint = CGPoint(
            x: (location.x - offset.width) / scale,
            y: (location.y - offset.height) / scale
        )
        
        if let node = nodes.first(where: {
            let dx = $0.position.x - graphPoint.x
            let dy = $0.position.y - graphPoint.y
            return sqrt(dx * dx + dy * dy) <= $0.radius + 8
        }) {
            if hoveredNodeId != node.id {
                hoveredNodeId = node.id
            }
        } else {
            if hoveredNodeId != nil {
                hoveredNodeId = nil
            }
        }
        
        // 处理点击
        if hoveredNodeId != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    // MARK: - Detail Sidebar
    
    private func detailSidebar(for tag: Tag) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(tag.swiftUIColor)
                            .frame(width: 20, height: 20)
                            .shadow(color: tag.swiftUIColor.opacity(0.5), radius: 6)
                        
                        Text(tag.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    Text("\(associatedFiles.count) 个关联文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showingDetail = false
                        selectedNodeId = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // File List
            if associatedFiles.isEmpty {
                ContentUnavailableView("暂无关联文件", systemImage: "doc.text", description: Text("此标签尚未关联任何文件"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(associatedFiles) { file in
                            FileRow(file: file)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20)
        .padding(16)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
    
    // MARK: - File Row
    
    private struct FileRow: View {
        let file: ManagedFile
        @State private var isHovering = false
        
        var body: some View {
            HStack(spacing: 14) {
                RichFileIcon(path: file.newPath)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(file.subcategory ?? file.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(12)
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
            .cornerRadius(12)
            .onHover { isHovering = $0 }
            .onTapGesture {
                FileFlowManager.shared.revealInFinder(url: URL(fileURLWithPath: file.newPath))
            }
        }
    }
    
    // MARK: - Load Data
    
    private func loadGraphData() {
        Task {
            let tags = appState.allTags
            let relations = await DatabaseManager.shared.getAllFileTagPairs()
            
            var newNodes: [GraphNode] = []
            var newLinks: [GraphLink] = []
            
            // Build file-tag map
            var fileTags: [UUID: [UUID]] = [:]
            for rel in relations {
                fileTags[rel.fileId, default: []].append(rel.tagId)
            }
            
            // Create links based on co-occurrence
            var linkCounts: [String: Int] = [:]
            
            for (_, tagIds) in fileTags {
                let sortedTags = tagIds.sorted { $0.uuidString < $1.uuidString }
                if sortedTags.count < 2 { continue }
                
                for i in 0..<sortedTags.count {
                    for j in (i+1)..<sortedTags.count {
                        let key = "\(sortedTags[i])-\(sortedTags[j])"
                        linkCounts[key, default: 0] += 1
                    }
                }
            }
            
            for (key, count) in linkCounts {
                let parts = key.components(separatedBy: "-")
                if let id1 = UUID(uuidString: parts[0]), let id2 = UUID(uuidString: parts[1]) {
                    newLinks.append(GraphLink(source: id1, target: id2, weight: count))
                }
            }
            
            // Create nodes
            let center = CGPoint(x: 500, y: 400)
            for (index, tag) in tags.enumerated() {
                let angle = (2 * .pi * Double(index)) / Double(max(tags.count, 1))
                let distance = 200.0 + Double.random(in: -30...30)
                let initialPos = CGPoint(
                    x: center.x + CGFloat(cos(angle) * distance),
                    y: center.y + CGFloat(sin(angle) * distance)
                )
                
                // 使用预定义配色或标签自身颜色
                let nodeColor = Color(hex: tag.color) ?? colorPalette[index % colorPalette.count]
                
                // 根据使用次数计算半径（最小20，最大70）
                let radius = CGFloat(20 + min(tag.usageCount * 4, 50))
                
                newNodes.append(GraphNode(
                    id: tag.id,
                    name: tag.name,
                    color: nodeColor,
                    radius: radius,
                    position: initialPos
                ))
            }
            
            await MainActor.run {
                self.nodes = newNodes
                self.links = newLinks
                startSimulation()
            }
        }
    }
    
    // MARK: - Simulation
    
    private func startSimulation() {
        timer?.invalidate()
        var ticks = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            if ticks > 400 {
                timer?.invalidate()
                return
            }
            updateSimulation()
            ticks += 1
        }
    }
    
    private func updateSimulation() {
        let center = CGPoint(x: 500, y: 400)
        
        for i in 0..<nodes.count {
            var fx: CGFloat = 0
            var fy: CGFloat = 0
            
            // Center gravity
            let cdx = center.x - nodes[i].position.x
            let cdy = center.y - nodes[i].position.y
            fx += cdx * 0.008
            fy += cdy * 0.008
            
            // Node repulsion
            for j in 0..<nodes.count {
                if i == j { continue }
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = sqrt(distSq)
                
                let minDist = nodes[i].radius + nodes[j].radius + 30
                let force = 4000.0 / distSq + (dist < minDist ? (minDist - dist) * 0.5 : 0)
                fx += (dx / dist) * force
                fy += (dy / dist) * force
            }
            
            nodes[i].velocity.x = (nodes[i].velocity.x + fx) * 0.55
            nodes[i].velocity.y = (nodes[i].velocity.y + fy) * 0.55
        }
        
        // Link attraction
        for link in links {
            guard let i = nodes.firstIndex(where: { $0.id == link.source }),
                  let j = nodes.firstIndex(where: { $0.id == link.target }) else { continue }
            
            let dx = nodes[j].position.x - nodes[i].position.x
            let dy = nodes[j].position.y - nodes[i].position.y
            let dist = sqrt(dx * dx + dy * dy)
            let desiredDist: CGFloat = 150 + nodes[i].radius + nodes[j].radius
            
            guard dist > 0 else { continue }
            
            let force = (dist - desiredDist) * 0.03
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            
            nodes[i].velocity.x += fx
            nodes[i].velocity.y += fy
            nodes[j].velocity.x -= fx
            nodes[j].velocity.y -= fy
        }
        
        // Update positions
        for i in 0..<nodes.count {
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
        }
    }
}

// MARK: - Graph Node

struct GraphNode: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    var radius: CGFloat
    var position: CGPoint
    var velocity: CGPoint = .zero
}

// MARK: - Graph Link

struct GraphLink: Identifiable {
    var id: String { "\(source)-\(target)" }
    let source: UUID
    let target: UUID
    let weight: Int
}

// MARK: - Control Button Style

struct GraphControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.1), radius: 5)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}
