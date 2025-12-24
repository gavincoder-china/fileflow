//
//  MoveFileSheet.swift
//  FileFlow
//
//  Created for Subfolder UX Enhancement
//

import SwiftUI

struct MoveFileSheet: View {
    let file: ManagedFile
    @Binding var isPresented: Bool
    let onMove: (PARACategory, String?) -> Void
    
    @State private var selectedCategory: PARACategory
    @State private var subcategoryInput: String = ""
    @State private var existingSubcategories: [String] = []
    @State private var isLoadingSubcategories = false
    
    // Animation state
    @State private var isFieldFocused: Bool = false
    
    init(file: ManagedFile, isPresented: Binding<Bool>, onMove: @escaping (PARACategory, String?) -> Void) {
        self.file = file
        self._isPresented = isPresented
        self.onMove = onMove
        self._selectedCategory = State(initialValue: file.category)
        self._subcategoryInput = State(initialValue: file.subcategory ?? "")
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header Info
                HStack(spacing: 16) {
                    RichFileIcon(path: file.newPath)
                        .frame(width: 48, height: 48)
                        .shadow(radius: 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("移动文件")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(file.newName.isEmpty ? file.originalName : file.newName)
                            .font(.title3)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top)
                
                // Form Area
                VStack(spacing: 20) {
                    // Category Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择分类")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(PARACategory.allCases) { category in
                                    CategoryPill(
                                        category: category,
                                        isSelected: selectedCategory == category,
                                        action: {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedCategory = category
                                                // Reset subcategory when changing category unless we want to keep the name
                                                // subcategoryInput = "" 
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Subcategory Input & Chips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("所属文件夹")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        TextField("输入或选择文件夹名称", text: $subcategoryInput)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.1))
                                    .stroke(Color.white.opacity(isFieldFocused ? 0.3 : 0.1), lineWidth: 1)
                            )
                            .font(.body)
                             // Focus handling if needed via FocusState in iOS 15+
                        
                        if isLoadingSubcategories {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !existingSubcategories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("快速选择")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                
                                ScrollView {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                        ForEach(existingSubcategories, id: \.self) { sub in
                                            Button {
                                                withAnimation {
                                                    subcategoryInput = sub
                                                }
                                            } label: {
                                                Text(sub)
                                                    .font(.caption)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        Capsule()
                                                            .fill(subcategoryInput == sub ? selectedCategory.color.opacity(0.2) : Color.white.opacity(0.05))
                                                    )
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(subcategoryInput == sub ? selectedCategory.color.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                                    )
                                                    .foregroundStyle(subcategoryInput == sub ? selectedCategory.color : .primary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(maxHeight: 120) // Limit height for chips
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding()
                .glass(cornerRadius: 24)
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("取消") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Button {
                        onMove(selectedCategory, subcategoryInput.isEmpty ? nil : subcategoryInput)
                        isPresented = false
                    } label: {
                        Text("确认移动")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedCategory.color)
                                    .shadow(color: selectedCategory.color.opacity(0.4), radius: 8, x: 0, y: 4)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCategory == file.category && (subcategoryInput == (file.subcategory ?? "")))
                }
                .padding(24)
            }
            .frame(width: 500, height: 500)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task(id: selectedCategory) {
            await loadSubcategories()
        }
    }
    
    private func loadSubcategories() async {
        isLoadingSubcategories = true
        // Simulate delay for smoother transition effect or actual IO
        try? await Task.sleep(nanoseconds: 100_000_000) 
        existingSubcategories = FileFlowManager.shared.getSubcategories(for: selectedCategory)
        isLoadingSubcategories = false
    }
}

struct CategoryPill: View {
    let category: PARACategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                Text(category.displayName)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? category.color.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? category.color : Color.white.opacity(0.1), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? category.color : .secondary)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}
