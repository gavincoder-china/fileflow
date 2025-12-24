import SwiftUI

/// A tree picker for selecting a target folder (category or nested subcategory)
struct FolderTreePicker: View {
    @Binding var selectedCategory: PARACategory
    @Binding var selectedSubcategoryId: UUID?
    
    @State private var allSubcategories: [Subcategory] = []
    @State private var expandedCategories: Set<PARACategory> = []
    @State private var expandedSubcategories: Set<UUID> = []
    @State private var isLoading = true
    
    // For creating new folders
    @State private var showingNewFolderInput = false
    @State private var newFolderName = ""
    @State private var newFolderParentCategory: PARACategory?
    @State private var newFolderParentSubId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择目标位置")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PARACategory.allCases) { category in
                        categoryRow(category)
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            
            if showingNewFolderInput {
                newFolderInputView
            }
        }
        .task {
            await loadSubcategories()
        }
    }
    
    // MARK: - Category Row
    @ViewBuilder
    private func categoryRow(_ category: PARACategory) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let isSelected = selectedCategory == category && selectedSubcategoryId == nil
        let childSubcategories = subcategories(for: category, parentId: nil)
        
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Expand/Collapse indicator
                if !childSubcategories.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedCategories.remove(category)
                                } else {
                                    expandedCategories.insert(category)
                                }
                            }
                        }
                } else {
                    Spacer().frame(width: 16)
                }
                
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                    .frame(width: 20)
                
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Spacer()
                
                // Add child folder button
                Button {
                    newFolderParentCategory = category
                    newFolderParentSubId = nil
                    showingNewFolderInput = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? category.color.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedCategory = category
                selectedSubcategoryId = nil
            }
            
            // Children (subcategories)
            if isExpanded {
                ForEach(childSubcategories) { sub in
                    subcategoryRow(sub, depth: 1)
                }
            }
        }
    }
    
    // MARK: - Subcategory Row
    @ViewBuilder
    private func subcategoryRow(_ subcategory: Subcategory, depth: Int) -> some View {
        let isExpanded = expandedSubcategories.contains(subcategory.id)
        let isSelected = selectedSubcategoryId == subcategory.id
        let childSubcategories = subcategories(for: subcategory.parentCategory, parentId: subcategory.id)
        let indent = CGFloat(depth) * 20
        
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Expand/Collapse indicator
                if !childSubcategories.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedSubcategories.remove(subcategory.id)
                                } else {
                                    expandedSubcategories.insert(subcategory.id)
                                }
                            }
                        }
                } else {
                    Spacer().frame(width: 16)
                }
                
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text(subcategory.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Spacer()
                
                // Add child folder button
                Button {
                    newFolderParentCategory = subcategory.parentCategory
                    newFolderParentSubId = subcategory.id
                    showingNewFolderInput = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, indent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? subcategory.parentCategory.color.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedCategory = subcategory.parentCategory
                selectedSubcategoryId = subcategory.id
            }
            
            // Nested children - use explicit type to avoid recursive opaque type inference
            if isExpanded {
                ForEach(childSubcategories) { child in
                    AnyView(subcategoryRow(child, depth: depth + 1))
                }
            }
        }
    }
    
    // MARK: - New Folder Input
    private var newFolderInputView: some View {
        HStack {
            TextField("新文件夹名称", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
            
            Button("创建") {
                createNewFolder()
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            
            Button("取消") {
                showingNewFolderInput = false
                newFolderName = ""
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helpers
    private func subcategories(for category: PARACategory, parentId: UUID?) -> [Subcategory] {
        allSubcategories.filter { sub in
            sub.parentCategory == category && sub.parentSubcategoryId == parentId
        }
    }
    
    private func loadSubcategories() async {
        isLoading = true
        allSubcategories = await DatabaseManager.shared.getAllSubcategories()
        isLoading = false
    }
    
    private func createNewFolder() {
        guard let category = newFolderParentCategory else { return }
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let newSub = Subcategory(
            name: trimmedName,
            parentCategory: category,
            parentSubcategoryId: newFolderParentSubId
        )
        
        Task {
            await DatabaseManager.shared.saveSubcategory(newSub)
            await loadSubcategories()
            
            // Auto-select the new folder
            await MainActor.run {
                selectedCategory = category
                selectedSubcategoryId = newSub.id
                showingNewFolderInput = false
                newFolderName = ""
                
                // Expand parents to show new folder
                expandedCategories.insert(category)
                if let parentId = newFolderParentSubId {
                    expandedSubcategories.insert(parentId)
                }
            }
        }
    }
}

// MARK: - Selection State
struct FolderSelection {
    var category: PARACategory
    var subcategoryId: UUID?
    
    /// Get the full path for display (e.g., "Projects/Web Design/Landing Pages")
    func displayPath(allSubcategories: [Subcategory]) -> String {
        guard let subId = subcategoryId,
              let subcategory = allSubcategories.first(where: { $0.id == subId }) else {
            return category.displayName
        }
        return category.displayName + "/" + subcategory.fullPath(allSubcategories: allSubcategories)
    }
}
