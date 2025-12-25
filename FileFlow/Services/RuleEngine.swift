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
        case .lastAccessDays:
            // Calculate days since last access
            let days = Calendar.current.dateComponents([.day], from: file.lastAccessedAt, to: Date()).day ?? 0
            fileValue = String(days)
        case .lifecycleStage:
            fileValue = file.lifecycleStage.rawValue
        case .currentCategory:
            fileValue = file.category.rawValue
        case .createdDaysAgo:
            // Calculate days since creation
            let days = Calendar.current.dateComponents([.day], from: file.createdAt, to: Date()).day ?? 0
            fileValue = String(days)
        }
        
        return compare(value: fileValue, conditionValue: condition.value, operator: condition.operator, field: condition.field)
    }
    
    private func compare(value: String, conditionValue: String, operator op: RuleOperator, field: RuleConditionField) -> Bool {
        // Numeric comparison for numeric fields
        if field.isNumeric {
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
        
        Logger.rule("Executing \(actions.count) actions on \(file.displayName)")
        
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
                    try await FileFlowManager.shared.moveFile(file, to: category, subcategory: subcategory)
                    Logger.success("Rule Action: Moved to \(category.rawValue)")
                } catch {
                    Logger.error("Rule Action Failed (Move): \(error)")
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
            Logger.info("Rule Action: Added tag \(tagName)")
            
        case .delete:
            // Move to Trash instead of permanent delete (safer, recoverable)
            do {
                let fileURL = URL(fileURLWithPath: file.newPath)
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL)
                await DatabaseManager.shared.deleteFile(file.id)
                Logger.info("Rule Action: Moved file to Trash")
            } catch {
                Logger.error("Rule Action Failed (Delete): \(error)")
            }
         }
     }
     
     // MARK: - High-Level Rule Application
     
     /// Apply all enabled rules to a specific file
     func applyRules(to file: ManagedFile) async {
         // Reload file to get latest state/path
         guard let currentFile = await DatabaseManager.shared.getFile(byPath: file.newPath) else { return }
         
         let allRules = await DatabaseManager.shared.getAllRules()
         let matched = evaluate(file: currentFile, rules: allRules)
         
         if !matched.isEmpty {
             Logger.rule("Applying \(matched.count) rules to \(currentFile.displayName)")
             await execute(rules: matched, on: currentFile)
         }
     }
}
