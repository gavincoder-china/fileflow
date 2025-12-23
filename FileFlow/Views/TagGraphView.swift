
import SwiftUI
import Combine

struct TagGraphView: View {
    @EnvironmentObject var appState: AppState
    @State private var nodes: [GraphNode] = []
    @State private var links: [GraphLink] = []
    @State private var selectedNodeId: UUID?
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    // Simulation parameters
    @State private var timer: Timer?
    @State private var simulationRunning = true
    
    // Selected tag for detail view
    @State private var selectedTag: Tag?
    @State private var associatedFiles: [ManagedFile] = []
    @State private var showingDetail = false
    
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
        .onChange(of: appState.allTags) { _ in
            loadGraphData()
        }
    }
    
    // MARK: - Sub-views
    
    private var graphArea: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            selectedNodeId = nil
                            selectedTag = nil
                            showingDetail = false
                        }
                    }
                
                graphCanvas
            }
            .drawingGroup()
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        handleTap(at: value.location)
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var graphCanvas: some View {
        Canvas { context, size in
            drawLinks(context: context)
            drawNodes(context: context)
        }
    }
    
    private func drawLinks(context: GraphicsContext) {
        for link in links {
            guard let startNode = nodes.first(where: { $0.id == link.source }),
                  let endNode = nodes.first(where: { $0.id == link.target }) else { continue }
            
            var path = Path()
            path.move(to: startNode.position)
            path.addLine(to: endNode.position)
            
            let isRelated = selectedNodeId != nil && 
                (link.source == selectedNodeId || link.target == selectedNodeId)
            let opacity = selectedNodeId == nil ? 0.3 : (isRelated ? 0.8 : 0.05)
            let lineWidth = CGFloat(link.weight) * 0.5 + 0.5
            
            context.stroke(path, with: .color(.gray.opacity(opacity)), lineWidth: lineWidth)
        }
    }
    
    private func drawNodes(context: GraphicsContext) {
        for node in nodes {
            let isSelected = selectedNodeId == node.id
            let isRelated = selectedNodeId != nil && links.contains { 
                ($0.source == selectedNodeId && $0.target == node.id) ||
                ($0.source == node.id && $0.target == selectedNodeId)
            }
            let opacity = selectedNodeId == nil ? 1.0 : (isSelected || isRelated ? 1.0 : 0.2)
            
            let circleRect = CGRect(
                x: node.position.x - node.radius,
                y: node.position.y - node.radius,
                width: node.radius * 2,
                height: node.radius * 2
            )
            
            context.fill(Path(ellipseIn: circleRect), with: .color(node.color.opacity(opacity)))
            
            if isSelected {
                context.stroke(Path(ellipseIn: circleRect), with: .color(.white), lineWidth: 2)
            }
            
            if node.radius > 15 || isSelected || isRelated {
                let textColor: Color = opacity < 0.5 ? .secondary : .primary
                let text = Text(node.name)
                    .font(.system(size: isSelected ? 14 : 10, weight: .medium))
                    .foregroundColor(textColor)
                context.draw(text, at: CGPoint(x: node.position.x, y: node.position.y + node.radius + 8), anchor: .top)
            }
        }
    }
    
    private func detailSidebar(for tag: Tag) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: 12, height: 12)
                Text(tag.name)
                    .font(.title3)
                    .bold()
                Spacer()
                Button {
                    withAnimation {
                        showingDetail = false
                        selectedNodeId = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Text("\(associatedFiles.count) 个关联文件")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            List(associatedFiles) { file in
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(file.category.color)
                    VStack(alignment: .leading) {
                        Text(file.displayName)
                            .lineLimit(1)
                        Text(file.subcategory ?? "无子分类")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .trailing))
    }
    
    // MARK: - Helpers
    
    private func handleTap(at location: CGPoint) {
        if let tappedNode = nodes.first(where: {
            let dx = $0.position.x - location.x
            let dy = $0.position.y - location.y
            return sqrt(dx*dx + dy*dy) <= $0.radius + 10
        }) {
            handleNodeTap(tappedNode)
        } else {
            withAnimation {
                selectedNodeId = nil
                selectedTag = nil
                showingDetail = false
            }
        }
    }
    
    private func handleNodeTap(_ node: GraphNode) {
        withAnimation {
            selectedNodeId = node.id
            if let tag = appState.allTags.first(where: { $0.id == node.id }) {
                selectedTag = tag
                showingDetail = true
                
                // Load files
                Task {
                    associatedFiles = await DatabaseManager.shared.getFilesWithTag(tag)
                }
            }
        }
        
        // Push node to center? optional
    }
    
    private func loadGraphData() {
        Task {
            let tags = appState.allTags
            let relations = await DatabaseManager.shared.getAllFileTagPairs()
            
            // Build Graph
            var newNodes: [GraphNode] = []
            var newLinks: [GraphLink] = []
            
            // Map [FileID: [TagID]]
            var fileTags: [UUID: [UUID]] = [:]
            for rel in relations {
                fileTags[rel.fileId, default: []].append(rel.tagId)
            }
            
            // Create Links based on co-occurrence
            var linkCounts: [String: Int] = [:] // "ID1-ID2" -> Count
            
            for (_, tagIds) in fileTags {
                let sortedTags = tagIds.sorted { $0.uuidString < $1.uuidString }
                if sortedTags.count < 2 { continue }
                
                for i in 0..<sortedTags.count {
                    for j in (i+1)..<sortedTags.count {
                        let id1 = sortedTags[i]
                        let id2 = sortedTags[j]
                        let key = "\(id1)-\(id2)"
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
            
            // Create Nodes with initial random positions
            let center = CGPoint(x: 500, y: 400) // approximate center
            for tag in tags {
                let angle = Double.random(in: 0...2 * .pi)
                let distance = Double.random(in: 0...100)
                let initialPos = CGPoint(
                    x: center.x + CGFloat(cos(angle) * distance),
                    y: center.y + CGFloat(sin(angle) * distance)
                )
                
                newNodes.append(GraphNode(
                    id: tag.id,
                    name: tag.name,
                    color: Color(hex: tag.color) ?? .blue,
                    radius: CGFloat(15 + min(tag.usageCount * 2, 40)), // Size based on usage
                    position: initialPos
                ))
            }
            
            // Update State
            await MainActor.run {
                self.nodes = newNodes
                self.links = newLinks
                startSimulation()
            }
        }
    }
    
    private func startSimulation() {
        timer?.invalidate()
        var ticks = 0
        
        // Simple force simulation
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            if ticks > 300 { // Stop after some time
                timer?.invalidate()
                return
            }
            
            updateSimulation()
            ticks += 1
        }
    }
    
    private func updateSimulation() {
        let center = CGPoint(x: 500, y: 400) // Assume 1000x800 canvas 
        // Need GeometryReader to get real center, but for now fixed is okay or use relative logic
        // Repulsion
        for i in 0..<nodes.count {
            var fx: CGFloat = 0
            var fy: CGFloat = 0
            
            // Center Gravity (weak)
            let dx = center.x - nodes[i].position.x
            let dy = center.y - nodes[i].position.y
            fx += dx * 0.01
            fy += dy * 0.01
            
            // Node Repulsion
            for j in 0..<nodes.count {
                if i == j { continue }
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let distSq = dx*dx + dy*dy
                if distSq < 1 { continue }
                let dist = sqrt(distSq)
                
                let force = 2000.0 / distSq // Inverse square law
                fx += (dx / dist) * force
                fy += (dy / dist) * force
            }
            
            // Link Attraction
            // This is slow O(N*M), better iterate links
            nodes[i].velocity.x = (nodes[i].velocity.x + fx) * 0.5 // Damping
            nodes[i].velocity.y = (nodes[i].velocity.y + fy) * 0.5
        }
        
        // Apply Link constraints
        for link in links {
            guard let i = nodes.firstIndex(where: { $0.id == link.source }),
                  let j = nodes.firstIndex(where: { $0.id == link.target }) else { continue }
            
            let dx = nodes[j].position.x - nodes[i].position.x
            let dy = nodes[j].position.y - nodes[i].position.y
            let dist = sqrt(dx*dx + dy*dy)
            let desiredDist: CGFloat = 100.0
            
            if dist == 0 { continue }
            
            let force = (dist - desiredDist) * 0.05
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
            
            // Bounds (optional)
        }
    }
}

struct GraphNode: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    var radius: CGFloat
    var position: CGPoint
    var velocity: CGPoint = .zero
}

struct GraphLink: Identifiable {
    var id: String { "\(source)-\(target)" }
    let source: UUID
    let target: UUID
    let weight: Int
}
