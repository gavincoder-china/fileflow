//
//  SubcategoryGridView.swift
//  FileFlow
//
//  Created for Subfolder UX Enhancement
//

import SwiftUI

struct SubcategoryGridView: View {
    let category: PARACategory
    let subcategories: [String]
    let onSelect: (String) -> Void
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    let onMerge: (String) -> Void
    
    @State private var hoveredSubcategory: String?
    
    // Adaptive columns for responsive grid
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("文件夹", systemImage: "folder.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(subcategories, id: \.self) { subcategory in
                    Button {
                        onSelect(subcategory)
                    } label: {
                        VStack(spacing: 12) {
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(category.color.opacity(0.1))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .stroke(category.color.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(category.color.gradient)
                                    .shadow(color: category.color.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            
                            // Name
                            Text(subcategory)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40, alignment: .top) // Fixed height for alignment
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(hoveredSubcategory == subcategory ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(hoveredSubcategory == subcategory ? 0.3 : 0.1), lineWidth: 1)
                        )
                        .scaleEffect(hoveredSubcategory == subcategory ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3), value: hoveredSubcategory)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredSubcategory = isHovering ? subcategory : nil
                    }
                    .contextMenu {
                        Button {
                            onRename(subcategory)
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        
                        Button {
                            onMerge(subcategory)
                        } label: {
                            Label("合并到...", systemImage: "arrow.triangle.merge")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            onDelete(subcategory)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(24)
        .glass(cornerRadius: 24)
    }
}
