import SwiftUI
import AppKit

// Global icon cache to prevent repeated disk I/O
private actor IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    
    func getIcon(for path: String) -> NSImage? {
        return cache[path]
    }
    
    func setIcon(_ icon: NSImage, for path: String) {
        cache[path] = icon
    }
}

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
            // Check cache first
            if let cached = await IconCache.shared.getIcon(for: path) {
                self.icon = cached
                return
            }
            
            // Load icon on background thread to avoid blocking UI
            let loadedIcon = await Task.detached(priority: .userInitiated) {
                return NSWorkspace.shared.icon(forFile: path)
            }.value
            
            // Cache the result
            await IconCache.shared.setIcon(loadedIcon, for: path)
            
            // Update UI on main thread
            await MainActor.run {
                self.icon = loadedIcon
            }
        }
    }
}
