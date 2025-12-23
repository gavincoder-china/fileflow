//
//  TagPropagationService.swift
//  FileFlow
//
//  Created by AutoAgent on 2025/12/23.
//

import Foundation

class TagPropagationService {
    static let shared = TagPropagationService()
    
    private init() {}
    
    /// Propagate tags to related files (same basename in same folder)
    func propagateTags(from sourceFile: ManagedFile, tags: [Tag]) async {
        guard !tags.isEmpty else { return }
        
        let category = sourceFile.category
        let subcategory = sourceFile.subcategory
        
        // 1. Get candidates
        let candidates = await DatabaseManager.shared.getFiles(category: category, subcategory: subcategory)
        
        // 2. Identify Basename
        let sourceBaseName = (sourceFile.newName as NSString).deletingPathExtension
        
        // 3. Filter Siblings
        let siblings = candidates.filter { file in
            // Must have same basename
            let baseName = (file.newName as NSString).deletingPathExtension
            // Must not be the source file itself
            return baseName == sourceBaseName && file.id != sourceFile.id
        }
        
        if siblings.isEmpty { return }
        
        print("🔗 Propagating \(tags.count) tags to \(siblings.count) siblings of \(sourceBaseName)")
        
        // 4. Apply Tags
        for sibling in siblings {
            for tag in tags {
                await DatabaseManager.shared.saveFileTagRelation(fileId: sibling.id, tagId: tag.id)
                await DatabaseManager.shared.incrementTagUsage(tag.id)
            }
        }
    }
}
