//
//  TreemapView.swift
//  FileFlow
//
//  基于 Squarified Treemap 算法的磁盘空间可视化组件
//

import SwiftUI

// MARK: - Models

struct TreemapNode: Identifiable {
    let id = UUID()
    let name: String
    let value: Double // Size in bytes
    let color: Color
    var children: [TreemapNode]?
    
    var isLeaf: Bool { children == nil || children!.isEmpty }
}

struct TreemapRect: Identifiable {
    let id = UUID()
    let node: TreemapNode
    let rect: CGRect
}

// MARK: - Layout Algorithm

class TreemapLayout {
    
    /// Compute layout for nodes within a given bounds using Squarified algorithm
    static func computeLayout(nodes: [TreemapNode], containerSize: CGSize) -> [TreemapRect] {
        guard !nodes.isEmpty else { return [] }
        
        let totalValue = nodes.reduce(0) { $0 + $1.value }
        guard totalValue > 0 else { return [] }
        
        // Normalize values to area
        let pendingNodes = nodes.sorted { $0.value > $1.value }
        
        // Recursive layout
        var results: [TreemapRect] = []
        squarify(nodes: pendingNodes, x: 0, y: 0, width: containerSize.width, height: containerSize.height, totalValue: totalValue, results: &results)
        
        return results
    }
    
    private static func squarify(nodes: [TreemapNode], x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, totalValue: Double, results: inout [TreemapRect]) {
        if nodes.isEmpty { return }
        
        // Simple recursice slice-and-dice for MVP (simpler than full squarified but effective enough)
        // If width > height, split horizontally (vertical cuts)
        // If height > width, split vertically (horizontal cuts)
        
        let isHorizontalSplit = width > height
        
        // Split roughly in half by value
        let halfValue = totalValue / 2.0
        var currentSum: Double = 0
        var midIndex = 0
        
        for (i, node) in nodes.enumerated() {
            currentSum += node.value
            if currentSum >= halfValue {
                midIndex = i + 1
                break
            }
        }
        // Ensure at least one item in first group if multiple exist
        if midIndex == 0 && !nodes.isEmpty { midIndex = 1 }
        // Ensure at least one item in second group if possible
        if midIndex == nodes.count && nodes.count > 1 { midIndex = nodes.count - 1 }
        
        let firstGroup = Array(nodes.prefix(midIndex))
        let secondGroup = Array(nodes.suffix(from: midIndex))
        
        let firstGroupValue = firstGroup.reduce(0) { $0 + $1.value }
        let secondGroupValue = secondGroup.reduce(0) { $0 + $1.value }
        
        if isHorizontalSplit {
            // Cut vertically
            let firstWidth = width * CGFloat(firstGroupValue / totalValue)
            
            if firstGroup.count == 1 {
                results.append(TreemapRect(node: firstGroup[0], rect: CGRect(x: x, y: y, width: firstWidth, height: height)))
            } else {
                squarify(nodes: firstGroup, x: x, y: y, width: firstWidth, height: height, totalValue: firstGroupValue, results: &results)
            }
            
            if secondGroup.count > 0 {
                squarify(nodes: secondGroup, x: x + firstWidth, y: y, width: width - firstWidth, height: height, totalValue: secondGroupValue, results: &results)
            }
        } else {
            // Cut horizontally
            let firstHeight = height * CGFloat(firstGroupValue / totalValue)
            
            if firstGroup.count == 1 {
                results.append(TreemapRect(node: firstGroup[0], rect: CGRect(x: x, y: y, width: width, height: firstHeight)))
            } else {
                squarify(nodes: firstGroup, x: x, y: y, width: width, height: firstHeight, totalValue: firstGroupValue, results: &results)
            }
            
            if secondGroup.count > 0 {
                squarify(nodes: secondGroup, x: x, y: y + firstHeight, width: width, height: height - firstHeight, totalValue: secondGroupValue, results: &results)
            }
        }
    }
}

// MARK: - View

struct TreemapView: View {
    let rootNode: TreemapNode
    var onNodeClick: ((TreemapNode) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 0 && geo.size.height > 0 {
                let rects = TreemapLayout.computeLayout(nodes: rootNode.children ?? [], containerSize: geo.size)
                
                ZStack(alignment: .topLeading) {
                    ForEach(rects) { item in
                        TreemapCell(item: item)
                            .onTapGesture {
                                onNodeClick?(item.node)
                            }
                    }
                }
            }
        }
    }
}

struct TreemapCell: View {
    let item: TreemapRect
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(item.node.color.gradient)
            
            Rectangle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
            
            if isHovering {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
            }
            
            VStack(spacing: 2) {
                Text(item.node.name)
                    .font(.system(size: fontSize(for: item.rect), weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .lineLimit(1)
                
                if item.rect.height > 30 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.node.value), countStyle: .file))
                        .font(.system(size: fontSize(for: item.rect) * 0.8))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 1)
                }
            }
            .padding(4)
            .opacity(item.rect.width < 30 || item.rect.height < 20 ? 0 : 1)
        }
        .frame(width: item.rect.width, height: item.rect.height)
        .position(x: item.rect.midX, y: item.rect.midY)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hover
            }
        }
        .help("\(item.node.name)\n\(ByteCountFormatter.string(fromByteCount: Int64(item.node.value), countStyle: .file))")
    }
    
    private func fontSize(for rect: CGRect) -> CGFloat {
        let minDim = min(rect.width, rect.height)
        return max(8, min(14, minDim / 4))
    }
}

// MARK: - Preview Helper
struct DiskUsageView: View {
    @State private var rootNode: TreemapNode?
    @State private var loading = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("磁盘空间分布")
                    .font(.headline)
                Spacer()
                Button(action: loadData) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.regularMaterial)
            
            if loading {
                Spacer()
                ProgressView("计算中...")
                Spacer()
            } else if let root = rootNode {
                TreemapView(rootNode: root) { node in
                    print("Clicked \(node.name)")
                }
                .padding(1)
                .background(Color.black.opacity(0.1))
            } else {
                ContentUnavailableView("无数据", systemImage: "chart.bar")
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .task { loadData() }
    }
    
    private func loadData() {
        loading = true
        Task {
            // Emulate data loading from DatabaseManager
            // In real app: calculate size by category or file type
            let files = await DatabaseManager.shared.getAllFiles()
            
            // Group by Category
            var categoryNodes: [TreemapNode] = []
            
            for category in PARACategory.allCases {
                let catFiles = files.filter { $0.category == category }
                let size = catFiles.reduce(0) { $0 + Int64($1.fileSize) }
                
                if size > 0 {
                    // Group by subcategory or extension
                    var children: [TreemapNode] = []
                    let extGrouping = Dictionary(grouping: catFiles, by: { $0.fileExtension.lowercased() })
                    
                    for (ext, extFiles) in extGrouping {
                        let extSize = extFiles.reduce(0) { $0 + Double($1.fileSize) }
                        children.append(TreemapNode(name: ext.isEmpty ? "其他" : ext.uppercased(), value: extSize, color: category.color.opacity(0.8), children: nil))
                    }
                    
                    categoryNodes.append(TreemapNode(name: category.displayName, value: Double(size), color: category.color, children: children))
                }
            }
            
            let root = TreemapNode(name: "Root", value: categoryNodes.reduce(0) { $0 + $1.value }, color: .gray, children: categoryNodes)
            
            await MainActor.run {
                self.rootNode = root
                self.loading = false
            }
        }
    }
}
