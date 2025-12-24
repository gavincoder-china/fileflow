//
//  CategoryFolderSidebar.swift
//  FileFlow
//
//  Created for Eagle-style Layout
//

import SwiftUI

struct CategoryFolderSidebar: View {
    let category: PARACategory
    let subcategories: [String]
    @Binding var selectedSubcategory: String?
    @Binding var searchText: String
    
    // Actions
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    let onMerge: (String) -> Void
    let onFileDrop: (ManagedFile, String?) -> Void // file, target subcategory (nil = root)
    
    var filteredSubcategories: [String] {
        if searchText.isEmpty {
            return subcategories
        }
        return subcategories.filter { $0.localizedStandardContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文件、文件夹或标签", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            // List
            ScrollView {
                VStack(spacing: 4) {
                    // "All" Item (Drop to root)
                    DropTargetFolder(
                        name: "全部文件",
                        icon: "square.grid.2x2",
                        isSelected: selectedSubcategory == nil,
                        action: { selectedSubcategory = nil },
                        onFileDrop: { file in onFileDrop(file, nil) }
                    )
                    
                    if filteredSubcategories.isEmpty && !subcategories.isEmpty && !searchText.isEmpty {
                        Text("无匹配文件夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    } else {
                        ForEach(filteredSubcategories, id: \.self) { sub in
                            DropTargetFolder(
                                name: sub,
                                icon: "folder",
                                isSelected: selectedSubcategory == sub,
                                action: { selectedSubcategory = sub },
                                onFileDrop: { file in onFileDrop(file, sub) }
                            )
                            .contextMenu {
                                Button {
                                    onRename(sub)
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                
                                Button {
                                    onMerge(sub)
                                } label: {
                                    Label("合并到...", systemImage: "arrow.triangle.merge")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    onDelete(sub)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5)) // Subtle background
    }
}

struct FolderSidebarItem: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Binding var isDropTarget: Bool // Passed from parent's dropDestination isTargeted
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? icon + ".fill" : icon)
                    .font(isDropTarget ? .title3 : .body) // Icon grows when drop target
                    .foregroundStyle(isDropTarget ? .blue : (isSelected ? .white : .secondary))
                
                Text(name)
                    .font(isDropTarget ? .body.weight(.semibold) : .body.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(isDropTarget ? .blue : (isSelected ? .white : .primary))
                
                Spacer()
                
                // Drop indicator icon
                if isDropTarget {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isDropTarget ? 10 : 8) // Slight padding increase
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDropTarget 
                        ? Color.blue.opacity(0.15) // Accent highlight when dropping
                        : (isSelected ? Color.blue : (isHovering ? Color.primary.opacity(0.05) : Color.clear)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDropTarget ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 2)
            )
            .shadow(color: isDropTarget ? Color.blue.opacity(0.3) : Color.clear, radius: 8)
            .scaleEffect(isDropTarget ? 1.03 : 1.0) // Slight scale up
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDropTarget)
    }
}

// MARK: - Drop Target Folder Wrapper
// Combines FolderSidebarItem with drop handling
struct DropTargetFolder: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    let onFileDrop: (ManagedFile) -> Void
    
    @State private var isDropTarget = false
    
    var body: some View {
        FolderSidebarItem(
            name: name,
            icon: icon,
            isSelected: isSelected,
            action: action,
            isDropTarget: $isDropTarget
        )
        .dropDestination(for: ManagedFile.self, action: { files, _ in
            guard let file = files.first else { return false }
            onFileDrop(file)
            return true
        }, isTargeted: { targeted in
            isDropTarget = targeted
        })
    }
}
