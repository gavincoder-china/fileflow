import SwiftUI

// MARK: - Flow Layout (Layout Protocol)
// MARK: - Flow Layout (Layout Protocol)
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    
    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flow(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flow(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    
    private func flow(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var points: [CGPoint] = []
        var finalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                // New row
                currentX = 0
                currentY += rowMaxHeight + spacing
                rowMaxHeight = 0
            }
            
            points.append(CGPoint(x: currentX, y: currentY))
            
            rowMaxHeight = max(rowMaxHeight, size.height)
            currentX += size.width + spacing
            finalWidth = max(finalWidth, currentX - spacing)
        }
        
        // Add last row height (if any items existed)
        let totalHeight = subviews.isEmpty ? 0 : currentY + rowMaxHeight
        return (CGSize(width: finalWidth, height: totalHeight), points)
    }
}
