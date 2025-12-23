//
//  FileOrganizeViewModel.swift
//  FileFlow
//
//  文件整理视图模型
//

import Foundation
import SwiftUI

@MainActor
class FileOrganizeViewModel: ObservableObject {
    // File Info
    @Published var file: ManagedFile
    let fileURL: URL
    
    // Tags
    @Published var selectedTags: [Tag] = []
    @Published var suggestedTags: [String] = []
    @Published var recentTags: [Tag] = []
    
    // Category
    @Published var selectedCategory: PARACategory = .resources {
        didSet {
            loadSubcategories()
            updateGeneratedFileName()
        }
    }
    @Published var selectedSubcategory: String?
    @Published var availableSubcategories: [String] = []
    
    // AI Analysis
    @Published var isAnalyzing = false
    @Published var aiSummary: String?
    
    // Notes
    @Published var notes = ""
    
    // Generated File Name
    @Published var generatedFileName = ""
    
    // State
    @Published var isSaving = false
    
    private let fileManager = FileFlowManager.shared
    private let database = DatabaseManager.shared
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        
        // Get file info
        let info = FileFlowManager.shared.getFileInfo(at: fileURL)
        
        self.file = ManagedFile(
            originalName: fileURL.lastPathComponent,
            originalPath: fileURL.path,
            category: .resources,
            fileSize: info?.size ?? 0,
            fileType: info?.type ?? ""
        )
        
        // 初始化时不调用异步操作，改由视图的 .task 调用
    }
    
    // MARK: - Load Data
    func loadInitialData() async {
        // Load recent tags
        recentTags = await database.getAllTags().prefix(10).map { $0 }
        
        // Load subcategories
        loadSubcategories()
        
        // Update file name
        updateGeneratedFileName()
        
        // Start AI analysis if available
        await analyzeWithAI()
    }
    
    func loadSubcategories() {
        availableSubcategories = fileManager.getSubcategories(for: selectedCategory)
    }
    
    // MARK: - Tag Management
    func addTag(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Check if already added
        if selectedTags.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            return
        }
        
        // Check if exists in recent tags
        if let existingTag = recentTags.first(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            selectedTags.append(existingTag)
        } else {
            // Create new tag with random color
            let newTag = Tag(name: trimmedName, color: TagColors.random())
            selectedTags.append(newTag)
        }
        
        // Remove from suggested
        suggestedTags.removeAll { $0.lowercased() == trimmedName.lowercased() }
        
        updateGeneratedFileName()
    }
    
    func selectTag(_ tag: Tag) {
        if !selectedTags.contains(where: { $0.id == tag.id }) {
            selectedTags.append(tag)
            updateGeneratedFileName()
        }
    }
    
    func removeTag(_ tag: Tag) {
        selectedTags.removeAll { $0.id == tag.id }
        updateGeneratedFileName()
    }
    
    // MARK: - Subcategory
    func createSubcategory(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        _ = fileManager.createSubcategory(name: trimmedName, in: selectedCategory)
        
        // Save to database
        let subcategory = Subcategory(name: trimmedName, parentCategory: selectedCategory)
        Task {
            await database.saveSubcategory(subcategory)
        }
        
        // Reload and select
        loadSubcategories()
        selectedSubcategory = trimmedName
    }
    
    // MARK: - File Name Generation
    func updateGeneratedFileName() {
        generatedFileName = fileManager.generateNewFileName(for: file, tags: selectedTags)
    }
    
    // MARK: - AI Analysis
    // MARK: - AI Analysis
    func analyzeWithAI() async {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai"
        if provider == "disabled" {
            return
        }
        
        isAnalyzing = true
        
        do {
            // 1. Extract content
            let content = try await DocumentContentExtractor.extractText(from: fileURL)
            
            // 2. Create service
            let service = AIServiceFactory.createService()
            
            // 3. Analyze
            let result = try await service.analyzeFile(content: content, fileName: file.originalName)
            
            // 4. Update UI
            await MainActor.run {
                self.aiSummary = result.summary
                
                // Add new tags
                for tagName in result.suggestedTags {
                    self.addTag(name: tagName)
                }
                
                // Set category if high confidence
                if result.confidence > 0.7 {
                    self.selectedCategory = result.suggestedCategory
                    
                    if let sub = result.suggestedSubcategory, !sub.isEmpty {
                        // Check if subcategory exists, if not create it
                        if !self.availableSubcategories.contains(sub) {
                            self.createSubcategory(name: sub)
                        }
                        self.selectedSubcategory = sub
                    }
                }
                
                self.isAnalyzing = false
            }
            
        } catch {
            print("AI Analysis failed: \(error.localizedDescription)")
            await MainActor.run {
                self.aiSummary = "AI 分析失败: \(error.localizedDescription)"
                self.isAnalyzing = false
            }
        }
    }
    
    // MARK: - Save File
    func saveFile() async {
        isSaving = true
        
        do {
            // Save tags to database
            for tag in selectedTags {
                await database.saveTag(tag)
            }
            
            // Move and rename file
            let newURL = try fileManager.moveAndRenameFile(
                from: fileURL,
                to: selectedCategory,
                subcategory: selectedSubcategory,
                newName: generatedFileName,
                tags: selectedTags
            )
            
            // Update file record
            var updatedFile = file
            updatedFile.newName = generatedFileName
            updatedFile.newPath = newURL.path
            updatedFile.category = selectedCategory
            updatedFile.subcategory = selectedSubcategory
            updatedFile.tags = selectedTags
            updatedFile.summary = aiSummary
            updatedFile.notes = notes
            
            // Save to database
            await database.saveFile(updatedFile, tags: selectedTags)
            
            // Propagate tags to related files
            await TagPropagationService.shared.propagateTags(from: updatedFile, tags: selectedTags)
            
        } catch {
            print("Error saving file: \(error)")
        }
        
        isSaving = false
    }
}
