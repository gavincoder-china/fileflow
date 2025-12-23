import SwiftUI
import AppKit

struct RichFileIcon: View {
    let path: String
    
    @State private var icon: NSImage?
    
    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Placeholder while loading
                Image(systemName: "doc")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
        }
        .task(id: path) {
            // Load icon asynchronously to avoid blocking the UI
            let nsIcon = NSWorkspace.shared.icon(forFile: path)
            self.icon = nsIcon
        }
    }
}

