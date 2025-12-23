//
//  RuleEngine.swift
//  FileFlow
//
//  Created by AutoAgent on 2025/12/23.
//

import Foundation

class RuleEngine {
    static let shared = RuleEngine()
    
    private init() {}
    
    /// Evaluate rules against a file and return actions to be performed
    func evaluate(file: ManagedFile, rules: [AutoRule]) -> [AutoRule] {
        var matchedRules: [AutoRule] = []
        
        for rule in rules where rule.isEnabled {
            if matches(rule: rule, file: file) {
                matchedRules.append(rule)
            }
        }
        
        return matchedRules
    }
    
    private func matches(rule: AutoRule, file: ManagedFile) -> Bool {
        if rule.conditions.isEmpty { return false }
        
        let results = rule.conditions.map { check(condition: $0, file: file) }
        
        switch rule.matchType {
        case .all:
            return !results.contains(false)
        case .any:
            return results.contains(true)
        }
    }
    
    private func check(condition: RuleCondition, file: ManagedFile) -> Bool {
        let fileValue:String
        
        switch condition.field {
        case .fileName:
            fileValue = file.displayName
        case .fileExtension:
            fileValue = file.fileExtension
        case .fileSize:
            // Convert bytes to KB for comparison consistency with UI label "KB"
            let kbSize = Double(file.fileSize) / 1024.0
            fileValue = String(format: "%.0f", kbSize)
        }
        
        return compare(value: fileValue, conditionValue: condition.value, operator: condition.operator, field: condition.field)
    }
    
    private func compare(value: String, conditionValue: String, operator op: RuleOperator, field: RuleConditionField) -> Bool {
        // Numeric comparison for File Size
        if field == .fileSize {
            guard let numValue = Double(value), let numCondition = Double(conditionValue) else {
                return false
            }
            switch op {
            case .greaterThan: return numValue > numCondition
            case .lessThan: return numValue < numCondition
            case .equals: return abs(numValue - numCondition) < 0.1
            default: return false
            }
        }
        
        // String comparison for others
        let v = value.lowercased()
        let c = conditionValue.lowercased()
        
        switch op {
        case .contains: return v.contains(c)
        case .equals: return v == c
        case .startsWith: return v.hasPrefix(c)
        case .endsWith: return v.hasSuffix(c)
        case .greaterThan, .lessThan: return false // Invalid for strings
        }
    }
    
    /// Execute actions on a file
    func execute(rules: [AutoRule], on file: ManagedFile) async {
        // Aggregate actions from all matched rules
        let actions = rules.flatMap { $0.actions }
        if actions.isEmpty { return }
        
        print("🤖 RuleEngine executing \(actions.count) actions on \(file.displayName)")
        
        for action in actions {
            await performAction(action, on: file)
        }
    }
    
    private func performAction(_ action: RuleAction, on file: ManagedFile) async {
        switch action.type {
        case .move:
            // TargetValue format expectation: "Category/Subcategory" or just "Category"
            let components = action.targetValue.split(separator: "/")
            if let categoryName = components.first,
               let category = PARACategory(rawValue: String(categoryName)) {
                
                let subcategory = components.count > 1 ? String(components[1]) : nil
                
                // Call FileFlowManager to move
                do {
                    // Note: We need to define moveFile logic that accepts strings or use existing logic
                    // For now, let's assume we update the DB record and move file on disk if possible
                    // Ideally FileFlowManager exposes a method for this.
                    try await FileFlowManager.shared.moveFile(file, to: category, subcategory: subcategory)
                    print("✅ Rule Action: Moved to \(category.rawValue)")
                } catch {
                    print("❌ Rule Action Failed (Move): \(error)")
                }
            }
            
        case .addTag:
            let tagName = action.targetValue
            // Find or create tag
            let existingTags = await DatabaseManager.shared.searchTags(matching: tagName)
            let tag: Tag
            if let existing = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                tag = existing
            } else {
                tag = Tag(name: tagName, color: TagColors.random())
                await DatabaseManager.shared.saveTag(tag)
            }
            
            // Link tag to file
            await DatabaseManager.shared.saveFileTagRelation(fileId: file.id, tagId: tag.id)
             // Also add the tag to the file object in memory if we were modifying it, but here we just update DB.
             // But FileFlowManager might need to refresh UI.
            print("✅ Rule Action: Added tag \(tagName)")
            
        case .delete:
            // TODO: Move to Trash or Delete
             do {
                 let fileManager = FileManager.default
                 try fileManager.removeItem(atPath: file.newPath)
                 await DatabaseManager.shared.deleteFile(file.id) // Need to expose deleteFile
                 print("✅ Rule Action: Deleted file")
             } catch {
                 print("❌ Rule Action Failed (Delete): \(error)")
             }
        }
    }
}
