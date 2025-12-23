//
//  DatabaseManager.swift
//  FileFlow
//
//  SQLite 数据库管理器 - 存储文件记录、标签、历史等
//  
//  设计理念：
//  数据库文件存储在根目录的 .fileflow 文件夹中
//  这样即使用户更换根目录，数据也会跟随
//

import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private var currentDbPath: String?
    
    // Serial queue for thread-safe database operations
    private let dbQueue = DispatchQueue(label: "com.fileflow.database", qos: .userInitiated)
    
    // SQLITE_TRANSIENT tells SQLite to make its own copy of the string
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private init() {
        openDatabase()
    }
    
    deinit {
        sqlite3_close(db)
    }

    
    // MARK: - Database Path
    
    private var dbURL: URL? {
        guard let rootURL = FileFlowManager.shared.rootURL else {
            // 如果根目录未配置，使用临时路径
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let metadataFolder = documentsURL.appendingPathComponent(".fileflow")
            
            // 确保文件夹存在
            if !FileManager.default.fileExists(atPath: metadataFolder.path) {
                try? FileManager.default.createDirectory(at: metadataFolder, withIntermediateDirectories: true)
            }
            
            return metadataFolder.appendingPathComponent("fileflow.db")
        }
        
        // 数据库存储在根目录的 .fileflow 文件夹中
        let metadataFolder = rootURL.appendingPathComponent(".fileflow")
        
        // 确保文件夹存在
        if !FileManager.default.fileExists(atPath: metadataFolder.path) {
            try? FileManager.default.createDirectory(at: metadataFolder, withIntermediateDirectories: true)
        }
        
        return metadataFolder.appendingPathComponent("fileflow.db")
    }
    
    // MARK: - Open Database
    
    func openDatabase() {
        guard let dbPath = dbURL?.path else { return }
        
        // 如果数据库路径变了，重新打开
        if currentDbPath != dbPath {
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
            
            if sqlite3_open(dbPath, &db) == SQLITE_OK {
                currentDbPath = dbPath
                createTables()
            } else {
                print("Error opening database at \(dbPath)")
            }
        }
    }
    
    /// 当根目录变更时调用
    func reloadDatabase() {
        currentDbPath = nil
        openDatabase()
    }
    
    // MARK: - Migration
    private func checkAndMigrate() {
        let sql = "PRAGMA table_info(tags);"
        var stmt: OpaquePointer?
        var hasIsFavorite = false
        var hasParentId = false
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    let columnName = String(cString: name)
                    if columnName == "is_favorite" {
                        hasIsFavorite = true
                    }
                    if columnName == "parent_id" {
                        hasParentId = true
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        if !hasIsFavorite {
            print("⚠️ Migrating database: Adding is_favorite column to tags")
            executeSQL("ALTER TABLE tags ADD COLUMN is_favorite INTEGER DEFAULT 0;")
        }
        
        if !hasParentId {
            print("⚠️ Migrating database: Adding parent_id column to tags")
            executeSQL("ALTER TABLE tags ADD COLUMN parent_id TEXT;")
        }
    }


    // MARK: - Create Tables
    private func createTables() {
        checkAndMigrate()
        
        let createFilesTable = """
        CREATE TABLE IF NOT EXISTS files (
            id TEXT PRIMARY KEY,
            original_name TEXT NOT NULL,
            new_name TEXT NOT NULL,
            original_path TEXT NOT NULL,
            current_path TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            category TEXT NOT NULL,
            subcategory TEXT,
            summary TEXT,
            notes TEXT,
            file_size INTEGER,
            file_type TEXT,
            created_at TEXT,
            imported_at TEXT,
            modified_at TEXT
        );
        """
        
        let createTagsTable = """
        CREATE TABLE IF NOT EXISTS tags (
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            color TEXT NOT NULL,
            usage_count INTEGER DEFAULT 0,
            is_favorite INTEGER DEFAULT 0,
            parent_id TEXT,
            created_at TEXT,
            last_used_at TEXT,
            FOREIGN KEY (parent_id) REFERENCES tags(id)
        );
        """

        
        let createFileTagsTable = """
        CREATE TABLE IF NOT EXISTS file_tags (
            file_id TEXT,
            tag_id TEXT,
            PRIMARY KEY (file_id, tag_id),
            FOREIGN KEY (file_id) REFERENCES files(id),
            FOREIGN KEY (tag_id) REFERENCES tags(id)
        );
        """
        
        let createSubcategoriesTable = """
        CREATE TABLE IF NOT EXISTS subcategories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parent_category TEXT NOT NULL,
            created_at TEXT,
            UNIQUE(name, parent_category)
        );
        """
        
        let createEmbeddingsTable = """
        CREATE TABLE IF NOT EXISTS file_embeddings (
            file_id TEXT PRIMARY KEY,
            embedding BLOB NOT NULL,
            provider TEXT NOT NULL,
            created_at TEXT,
            FOREIGN KEY (file_id) REFERENCES files(id)
        );
        """
        
        let createRulesTable = """
        CREATE TABLE IF NOT EXISTS rules (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_enabled INTEGER DEFAULT 1,
            match_type TEXT NOT NULL,
            created_at TEXT
        );
        """
        
        let createRuleConditionsTable = """
        CREATE TABLE IF NOT EXISTS rule_conditions (
            id TEXT PRIMARY KEY,
            rule_id TEXT NOT NULL,
            field TEXT NOT NULL,
            operator TEXT NOT NULL,
            value TEXT NOT NULL,
            FOREIGN KEY (rule_id) REFERENCES rules(id) ON DELETE CASCADE
        );
        """
        
        let createRuleActionsTable = """
        CREATE TABLE IF NOT EXISTS rule_actions (
            id TEXT PRIMARY KEY,
            rule_id TEXT NOT NULL,
            type TEXT NOT NULL,
            target_value TEXT NOT NULL,
            FOREIGN KEY (rule_id) REFERENCES rules(id) ON DELETE CASCADE
        );
        """
        
        executeSQL(createFilesTable)
        executeSQL(createTagsTable)
        executeSQL(createFileTagsTable)
        executeSQL(createSubcategoriesTable)
        executeSQL(createEmbeddingsTable)
        executeSQL(createRulesTable)
        executeSQL(createRuleConditionsTable)
        executeSQL(createRuleActionsTable)
        
        // Create indexes
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_category ON files(category);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_imported_at ON files(imported_at);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_relative_path ON files(relative_path);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);")
    }

    
    private func executeSQL(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL Error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }
    // MARK: - Tag Operations
    func saveTag(_ tag: Tag) async {
        dbQueue.sync {
            openDatabase() // 确保数据库已打开
            
            let sql = """
            INSERT OR REPLACE INTO tags (id, name, color, usage_count, is_favorite, parent_id, created_at, last_used_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Use local variables to ensure string lifetime
                let idString = tag.id.uuidString
                let nameString = tag.name
                let colorString = tag.color
                let createdAtString = ISO8601DateFormatter().string(from: tag.createdAt)
                let lastUsedAtString = ISO8601DateFormatter().string(from: tag.lastUsedAt)
                
                sqlite3_bind_text(stmt, 1, idString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, nameString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, colorString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 4, Int32(tag.usageCount))
                sqlite3_bind_int(stmt, 5, tag.isFavorite ? 1 : 0)
                
                // Bind parent_id (nullable)
                if let parentId = tag.parentId {
                    sqlite3_bind_text(stmt, 6, parentId.uuidString, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                sqlite3_bind_text(stmt, 7, createdAtString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 8, lastUsedAtString, -1, SQLITE_TRANSIENT)
                
                let result = sqlite3_step(stmt)
                if result != SQLITE_DONE {
                    print("❌ Tag save failed: \(result)")
                }
            }
            sqlite3_finalize(stmt)
        }
    }


    
    func toggleTagFavorite(_ tag: Tag) async {
        var updatedTag = tag
        updatedTag.isFavorite.toggle()
        await saveTag(updatedTag)
    }
    
    func deleteTag(_ tag: Tag) async {
        dbQueue.sync {
            openDatabase()
            
            // 1. Delete file-tag relations
            let deleteRelationsSql = "DELETE FROM file_tags WHERE tag_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteRelationsSql, -1, &stmt, nil) == SQLITE_OK {
                let idString = tag.id.uuidString
                sqlite3_bind_text(stmt, 1, idString, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            // 2. Delete the tag itself
            let deleteTagSql = "DELETE FROM tags WHERE id = ?;"
            if sqlite3_prepare_v2(db, deleteTagSql, -1, &stmt, nil) == SQLITE_OK {
                let idString = tag.id.uuidString
                sqlite3_bind_text(stmt, 1, idString, -1, SQLITE_TRANSIENT)
                let result = sqlite3_step(stmt)
                if result == SQLITE_DONE {
                    print("✅ Deleted tag: \(tag.name)")
                } else {
                    print("❌ Failed to delete tag: \(result)")
                }
            }
            sqlite3_finalize(stmt)
        }
    }

    
    func renameTag(oldTag: Tag, newName: String) async throws {
        openDatabase()
        print("🔄 Renaming tag \(oldTag.name) to \(newName)")
        
        // 1. Update Tag Name in DB
        var updatedTag = oldTag
        updatedTag.name = newName
        await saveTag(updatedTag)
        
        // 2. Find all affected files
        let files = await getFilesWithTag(oldTag)
        print("Found \(files.count) files to rename")
        
        let fileManager = FileManager.default
        
        for file in files {
             // Calculate new filename
            let oldName = file.newName.isEmpty ? file.originalName : file.newName
            
            // Replaces #OldTag with #NewTag
            // Safer logic: Split by # to avoid partial matches (e.g. #Art vs #Artificial)
            var newFileName = oldName
            if let index = oldName.firstIndex(of: "#") {
                let prefix = oldName[..<index]
                let tagsPartWithExt = oldName[index...]
                
                // Remove extension for checking
                let ext = (oldName as NSString).pathExtension
                let tagsPart = (String(tagsPartWithExt) as NSString).deletingPathExtension // #Tag1#Tag2
                
                let tags = tagsPart.split(separator: "#").map { String($0) }
                let newTags = tags.map { $0 == oldTag.name ? newName : $0 }
                
                if tags != newTags {
                     let newTagsString = newTags.isEmpty ? "" : "#" + newTags.joined(separator: "#")
                     newFileName = String(prefix) + newTagsString + (ext.isEmpty ? "" : "." + ext)
                }
            }
            
            if newFileName == oldName { continue } // No change needed
            
            let oldURL = URL(fileURLWithPath: file.newPath)
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFileName)
            
            do {
                // Rename on disk
                try fileManager.moveItem(at: oldURL, to: newURL)
                print("✅ Renamed file on disk: \(newFileName)")
                
                // Update File Record
                var newFile = file
                newFile.newName = newFileName
                newFile.newPath = newURL.path
                newFile.modifiedAt = Date()
                
                // Refresh tags for this file (now containing the renamed tag from DB)
                let tags = await getTagsForFile(fileId: file.id)
                
                await saveFile(newFile, tags: tags)
                
            } catch {
                print("❌ Error renaming file: \(error)")
                // Continue to next file (best effort)
            }
        }
    }

    func getAllTags() async -> [Tag] {
        openDatabase()
        
        let sql = "SELECT * FROM tags ORDER BY usage_count DESC, last_used_at DESC;"
        var tags: [Tag] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let tag = parseTag(from: stmt) {
                    tags.append(tag)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return tags
    }
    
    func searchTags(matching query: String) async -> [Tag] {
        openDatabase()
        
        let sql = "SELECT * FROM tags WHERE name LIKE ? ORDER BY usage_count DESC LIMIT 10;"
        var tags: [Tag] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let searchPattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, searchPattern, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let tag = parseTag(from: stmt) {
                    tags.append(tag)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return tags
    }
    
    // MARK: - Similar Tag Detection
    
    /// Tag merge suggestion
    struct TagMergeSuggestion: Identifiable {
        let id = UUID()
        let tag1: Tag
        let tag2: Tag
        let similarity: Double
        
        var suggestedName: String {
            // Keep the higher usage count tag's name
            tag1.usageCount >= tag2.usageCount ? tag1.name : tag2.name
        }
    }
    
    /// Find similar tags that might be duplicates
    func findSimilarTags(threshold: Double = 0.7) async -> [TagMergeSuggestion] {
        let allTags = await getAllTags()
        var suggestions: [TagMergeSuggestion] = []
        
        for i in 0..<allTags.count {
            for j in (i+1)..<allTags.count {
                let tag1 = allTags[i]
                let tag2 = allTags[j]
                
                let similarity = stringSimilarity(tag1.name.lowercased(), tag2.name.lowercased())
                
                if similarity >= threshold {
                    suggestions.append(TagMergeSuggestion(
                        tag1: tag1,
                        tag2: tag2,
                        similarity: similarity
                    ))
                }
            }
        }
        
        return suggestions.sorted { $0.similarity > $1.similarity }
    }
    
    /// Merge two tags: move all files from tag2 to tag1, then delete tag2
    func mergeTags(_ keep: Tag, into remove: Tag) async {
        // 1. Get all files with the tag to remove
        let files = await getFilesWithTag(remove)
        
        // 2. Add the kept tag to each file
        for file in files {
            await saveFileTagRelation(fileId: file.id, tagId: keep.id)
        }
        
        // 3. Delete the removed tag
        await deleteTag(remove)
    }
    
    /// Calculate string similarity using Levenshtein distance
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count
        
        if len1 == 0 || len2 == 0 {
            return len1 == len2 ? 1.0 : 0.0
        }
        
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: len2 + 1), count: len1 + 1)
        
        for i in 0...len1 { matrix[i][0] = i }
        for j in 0...len2 { matrix[0][j] = j }
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        let distance = Double(matrix[len1][len2])
        let maxLen = Double(max(len1, len2))
        
        return 1.0 - (distance / maxLen)
    }

    
    func incrementTagUsage(_ tagId: UUID) async {
        openDatabase()
        
        let sql = "UPDATE tags SET usage_count = usage_count + 1, last_used_at = ? WHERE id = ?;"
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let dateString = ISO8601DateFormatter().string(from: Date())
            let tagIdString = tagId.uuidString
            sqlite3_bind_text(stmt, 1, dateString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, tagIdString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    private func parseTag(from stmt: OpaquePointer?) -> Tag? {
        guard let stmt = stmt else { return nil }
        
        guard let idStr = sqlite3_column_text(stmt, 0),
              let nameStr = sqlite3_column_text(stmt, 1),
              let colorStr = sqlite3_column_text(stmt, 2) else {
            return nil
        }
        
        let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
        let name = String(cString: nameStr)
        let color = String(cString: colorStr)
        let usageCount = Int(sqlite3_column_int(stmt, 3))
        let isFavorite = sqlite3_column_int(stmt, 4) != 0
        
        // Read parent_id (nullable, column 5)
        var parentId: UUID? = nil
        if let parentIdStr = sqlite3_column_text(stmt, 5) {
            parentId = UUID(uuidString: String(cString: parentIdStr))
        }
        
        var tag = Tag(id: id, name: name, color: color, usageCount: usageCount, isFavorite: isFavorite, parentId: parentId)
        
        // Columns shifted: created_at is now 6, last_used_at is 7
        if let createdAtStr = sqlite3_column_text(stmt, 6) {
            tag.createdAt = ISO8601DateFormatter().date(from: String(cString: createdAtStr)) ?? Date()
        }
        if let lastUsedAtStr = sqlite3_column_text(stmt, 7) {
            tag.lastUsedAt = ISO8601DateFormatter().date(from: String(cString: lastUsedAtStr)) ?? Date()
        }
        
        return tag
    }

    
    // MARK: - File Operations
    func saveFile(_ file: ManagedFile, tags: [Tag]) async {
        dbQueue.sync {
            openDatabase()
            
            // 计算相对路径
            let relativePath = calculateRelativePath(for: file.newPath)
            
            let sql = """
            INSERT OR REPLACE INTO files 
            (id, original_name, new_name, original_path, current_path, relative_path, category, subcategory, summary, notes, file_size, file_type, created_at, imported_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let formatter = ISO8601DateFormatter()
                
                // Use local variables to ensure string lifetime during binding
                let idString = file.id.uuidString
                let originalNameString = file.originalName
                let newNameString = file.newName
                let originalPathString = file.originalPath
                let newPathString = file.newPath
                let categoryString = file.category.rawValue
                let fileTypeString = file.fileType
                let createdAtString = formatter.string(from: file.createdAt)
                let importedAtString = formatter.string(from: file.importedAt)
                let modifiedAtString = formatter.string(from: file.modifiedAt)
                
                sqlite3_bind_text(stmt, 1, idString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, originalNameString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, newNameString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, originalPathString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, newPathString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 6, relativePath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 7, categoryString, -1, SQLITE_TRANSIENT)
                
                if let subcategory = file.subcategory {
                    sqlite3_bind_text(stmt, 8, subcategory, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }
                
                if let summary = file.summary {
                    sqlite3_bind_text(stmt, 9, summary, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }
                
                if let notes = file.notes {
                    sqlite3_bind_text(stmt, 10, notes, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 10)
                }
                sqlite3_bind_int64(stmt, 11, file.fileSize)
                sqlite3_bind_text(stmt, 12, fileTypeString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 13, createdAtString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 14, importedAtString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 15, modifiedAtString, -1, SQLITE_TRANSIENT)
                
                let result = sqlite3_step(stmt)
                if result != SQLITE_DONE {
                    print("❌ File save failed: \(result)")
                }
            }
            sqlite3_finalize(stmt)
        }
        
        
        // Clear existing tags
        let fileIdStr = file.id.uuidString
        executeSQL("DELETE FROM file_tags WHERE file_id = '\(fileIdStr)';")
        
        // Save file-tag relationships (outside dbQueue.sync to avoid nested calls)
        for tag in tags {
            await saveFileTagRelation(fileId: file.id, tagId: tag.id)
            await incrementTagUsage(tag.id)
        }
    }

    
    private func calculateRelativePath(for absolutePath: String) -> String {
        guard let rootPath = FileFlowManager.shared.rootURL?.path else {
            return absolutePath
        }
        
        if absolutePath.hasPrefix(rootPath) {
            return String(absolutePath.dropFirst(rootPath.count + 1)) // +1 for the trailing /
        }
        return absolutePath
    }
    
    func saveFileTagRelation(fileId: UUID, tagId: UUID) async {
        dbQueue.sync {
            let sql = "INSERT OR IGNORE INTO file_tags (file_id, tag_id) VALUES (?, ?);"
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Use local variables to ensure string lifetime
                let fileIdString = fileId.uuidString
                let tagIdString = tagId.uuidString
                
                sqlite3_bind_text(stmt, 1, fileIdString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, tagIdString, -1, SQLITE_TRANSIENT)
                
                let result = sqlite3_step(stmt)
                if result != SQLITE_DONE {
                    print("❌ File-tag relation save failed: \(result)")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func updateTags(fileId: UUID, tags: [Tag]) async {
        let fileIdStr = fileId.uuidString
        executeSQL("DELETE FROM file_tags WHERE file_id = '\(fileIdStr)';")
        
        for tag in tags {
            await saveFileTagRelation(fileId: fileId, tagId: tag.id)
            await incrementTagUsage(tag.id)
        }
    }
    
    func deleteFile(_ fileId: UUID) async {
        dbQueue.sync {
            openDatabase()
            let id = fileId.uuidString
            executeSQL("DELETE FROM files WHERE id = '\(id)';")
            executeSQL("DELETE FROM file_tags WHERE file_id = '\(id)';")
            executeSQL("DELETE FROM file_embeddings WHERE file_id = '\(id)';")
        }
    }

    
    func getRecentFiles(limit: Int) async -> [ManagedFile] {
        openDatabase()
        
        let sql = "SELECT * FROM files ORDER BY imported_at DESC LIMIT ?;"
        var files: [ManagedFile] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if var file = parseFile(from: stmt) {
                    // Load tags for this file
                    let fileId = file.id
                    file.tags = await self.getTagsForFile(fileId: fileId)
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return files
    }
    
    /// Get all files for a specific category (not relying on search query)
    func getFilesForCategory(_ category: PARACategory) async -> [ManagedFile] {
        openDatabase()
        
        let sql = """
        SELECT * FROM files
        WHERE category = ?
        ORDER BY imported_at DESC;
        """
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let categoryString = category.rawValue
            sqlite3_bind_text(stmt, 1, categoryString, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if var file = parseFile(from: stmt) {
                    let fileId = file.id
                    file.tags = await self.getTagsForFile(fileId: fileId)
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return files
    }
    
    /// Get files for category and specific subcategory (for efficient propagation lookup)
    func getFiles(category: PARACategory, subcategory: String?) async -> [ManagedFile] {
        openDatabase()
        
        var sql = "SELECT * FROM files WHERE category = ?"
        if subcategory != nil {
            sql += " AND subcategory = ?"
        } else {
            sql += " AND (subcategory IS NULL OR subcategory = '')"
        }
        sql += " ORDER BY imported_at DESC;"
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, category.rawValue, -1, SQLITE_TRANSIENT)
            if let sub = subcategory {
                sqlite3_bind_text(stmt, 2, sub, -1, SQLITE_TRANSIENT)
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let file = parseFile(from: stmt) {
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        return files
    }
    
    func getFile(byPath path: String) async -> ManagedFile? {
        openDatabase()
        
        let sql = "SELECT * FROM files WHERE current_path = ? OR original_path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var file: ManagedFile?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, path, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                file = parseFile(from: stmt)
                if var f = file {
                    f.tags = await getTagsForFile(fileId: f.id)
                    file = f
                }
            }
        }
        sqlite3_finalize(stmt)
        return file
    }
    
    /// Get all file-tag pairs for graph generation
    func getAllFileTagPairs() async -> [(fileId: UUID, tagId: UUID)] {
        openDatabase()
        
        let sql = "SELECT file_id, tag_id FROM file_tags;"
        var pairs: [(fileId: UUID, tagId: UUID)] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let fileIdStr = sqlite3_column_text(stmt, 0),
                   let tagIdStr = sqlite3_column_text(stmt, 1) {
                    let fileId = UUID(uuidString: String(cString: fileIdStr)) ?? UUID()
                    let tagId = UUID(uuidString: String(cString: tagIdStr)) ?? UUID()
                    pairs.append((fileId, tagId))
                }
            }
        }
        sqlite3_finalize(stmt)
        return pairs
    }
    
    /// Get all files that have a specific tag
    func getFilesWithTag(_ tag: Tag) async -> [ManagedFile] {
        openDatabase()
        
        let sql = """
        SELECT f.* FROM files f
        JOIN file_tags ft ON f.id = ft.file_id
        WHERE ft.tag_id = ?
        ORDER BY f.imported_at DESC;
        """
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let tagIdString = tag.id.uuidString
            sqlite3_bind_text(stmt, 1, tagIdString, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if var file = parseFile(from: stmt) {
                    let fileId = file.id
                    file.tags = await self.getTagsForFile(fileId: fileId)
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return files
    }
    
    func searchFiles(query: String, category: PARACategory? = nil, tags: [Tag] = []) async -> [ManagedFile] {
        openDatabase()
        
        var sql = """
        SELECT DISTINCT f.* FROM files f
        LEFT JOIN file_tags ft ON f.id = ft.file_id
        LEFT JOIN tags t ON ft.tag_id = t.id
        WHERE (f.new_name LIKE ? OR f.summary LIKE ? OR f.notes LIKE ? OR t.name LIKE ?)
        """
        
        if let category = category {
            sql += " AND f.category = '\(category.rawValue)'"
        }
        
        sql += " ORDER BY f.imported_at DESC LIMIT 100;"
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let searchPattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, searchPattern, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let file = parseFile(from: stmt) {
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return files
    }
    
    func getTagsForFile(fileId: UUID) async -> [Tag] {
        let sql = """
        SELECT t.* FROM tags t
        JOIN file_tags ft ON t.id = ft.tag_id
        WHERE ft.file_id = ?;
        """
        var tags: [Tag] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let fileIdString = fileId.uuidString
            sqlite3_bind_text(stmt, 1, fileIdString, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let tag = parseTag(from: stmt) {
                    tags.append(tag)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return tags
    }
    
    private func parseFile(from stmt: OpaquePointer?) -> ManagedFile? {
        guard let stmt = stmt else { return nil }
        
        guard let idStr = sqlite3_column_text(stmt, 0),
              let originalNameStr = sqlite3_column_text(stmt, 1),
              let newNameStr = sqlite3_column_text(stmt, 2),
              let originalPathStr = sqlite3_column_text(stmt, 3),
              let currentPathStr = sqlite3_column_text(stmt, 4),
              let categoryStr = sqlite3_column_text(stmt, 6) else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        
        var file = ManagedFile(
            id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
            originalName: String(cString: originalNameStr),
            originalPath: String(cString: originalPathStr),
            category: PARACategory(rawValue: String(cString: categoryStr)) ?? .resources
        )
        
        file.newName = String(cString: newNameStr)
        file.newPath = String(cString: currentPathStr)
        
        if let subcategoryStr = sqlite3_column_text(stmt, 7) {
            file.subcategory = String(cString: subcategoryStr)
        }
        if let summaryStr = sqlite3_column_text(stmt, 8) {
            file.summary = String(cString: summaryStr)
        }
        if let notesStr = sqlite3_column_text(stmt, 9) {
            file.notes = String(cString: notesStr)
        }
        
        file.fileSize = sqlite3_column_int64(stmt, 10)
        
        if let fileTypeStr = sqlite3_column_text(stmt, 11) {
            file.fileType = String(cString: fileTypeStr)
        }
        if let createdAtStr = sqlite3_column_text(stmt, 12) {
            file.createdAt = formatter.date(from: String(cString: createdAtStr)) ?? Date()
        }
        if let importedAtStr = sqlite3_column_text(stmt, 13) {
            file.importedAt = formatter.date(from: String(cString: importedAtStr)) ?? Date()
        }
        if let modifiedAtStr = sqlite3_column_text(stmt, 14) {
            file.modifiedAt = formatter.date(from: String(cString: modifiedAtStr)) ?? Date()
        }
        
        return file
    }
    
    // MARK: - Subcategory Operations
    func saveSubcategory(_ subcategory: Subcategory) async {
        openDatabase()
        
        let sql = """
        INSERT OR IGNORE INTO subcategories (id, name, parent_category, created_at)
        VALUES (?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let idString = subcategory.id.uuidString
            let nameString = subcategory.name
            let parentString = subcategory.parentCategory.rawValue
            let createdAtString = ISO8601DateFormatter().string(from: subcategory.createdAt)
            sqlite3_bind_text(stmt, 1, idString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, nameString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, parentString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, createdAtString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    func getSubcategories(for category: PARACategory) async -> [Subcategory] {
        openDatabase()
        
        let sql = "SELECT * FROM subcategories WHERE parent_category = ? ORDER BY name;"
        var subcategories: [Subcategory] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let categoryString = category.rawValue
            sqlite3_bind_text(stmt, 1, categoryString, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idStr = sqlite3_column_text(stmt, 0),
                   let nameStr = sqlite3_column_text(stmt, 1) {
                    let subcategory = Subcategory(
                        id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                        name: String(cString: nameStr),
                        parentCategory: category
                    )
                    subcategories.append(subcategory)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return subcategories
    }
    
    // MARK: - Rebuild Index
    
    /// 扫描根目录并重建索引（用于数据恢复）
    func rebuildIndex() async {
        openDatabase()
        
        // Clear existing data
        executeSQL("DELETE FROM file_tags;")
        executeSQL("DELETE FROM files;")
        
        // Scan all files
        let files = FileFlowManager.shared.scanAllFiles()
        
        for fileURL in files {
            // Get file info
            guard let info = FileFlowManager.shared.getFileInfo(at: fileURL) else { continue }
            
            // Determine category from path
            let relativePath = fileURL.path.replacingOccurrences(of: FileFlowManager.shared.baseURL.path + "/", with: "")
            let components = relativePath.components(separatedBy: "/")
            
            guard let categoryFolder = components.first,
                  let category = PARACategory.allCases.first(where: { $0.folderName == categoryFolder }) else {
                continue
            }
            
            // Get subcategory if present
            var subcategory: String? = nil
            if components.count > 2 {
                subcategory = components[1]
            }
            
            // Get Finder tags
            let finderTags = FileFlowManager.shared.getFinderTags(from: fileURL)
            
            // Create file record
            var file = ManagedFile(
                originalName: fileURL.lastPathComponent,
                originalPath: fileURL.path,
                category: category,
                subcategory: subcategory,
                fileSize: info.size
            )
            file.newName = fileURL.lastPathComponent
            file.newPath = fileURL.path
            file.createdAt = info.created
            file.modifiedAt = info.modified
            
            // Create tags
            var tags: [Tag] = []
            for tagName in finderTags {
                let tag = Tag(name: tagName, color: TagColors.random())
                await saveTag(tag)
                tags.append(tag)
            }
            
            // Save file
            await saveFile(file, tags: tags)
        }
    }
    func truncateAllTables() {
        openDatabase()
        
        // Disable foreign keys temporarily
        sqlite3_exec(db, "PRAGMA foreign_keys = OFF;", nil, nil, nil)
        
        let tables = ["files", "tags", "file_tags", "subcategories", "file_embeddings"]
        for table in tables {
            let sql = "DELETE FROM \(table);"
            sqlite3_exec(db, sql, nil, nil, nil)
        }
        
        // Re-enable foreign keys
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }
    
    // MARK: - Embedding Operations
    
    /// Save file embedding to database
    func saveFileEmbedding(fileId: UUID, embedding: [Float], provider: String) async {
        dbQueue.sync {
            openDatabase()
            
            let sql = """
            INSERT OR REPLACE INTO file_embeddings (file_id, embedding, provider, created_at)
            VALUES (?, ?, ?, ?);
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let fileIdString = fileId.uuidString
                let createdAt = ISO8601DateFormatter().string(from: Date())
                
                // Convert [Float] to Data (BLOB)
                let embeddingData = embedding.withUnsafeBufferPointer { buffer in
                    Data(buffer: buffer)
                }
                
                sqlite3_bind_text(stmt, 1, fileIdString, -1, SQLITE_TRANSIENT)
                embeddingData.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(embeddingData.count), SQLITE_TRANSIENT)
                }
                sqlite3_bind_text(stmt, 3, provider, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, createdAt, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("❌ Embedding save failed")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Get all file embeddings for similarity search
    func getAllFileEmbeddings() async -> [(fileId: UUID, embedding: [Float])] {
        openDatabase()
        
        let sql = "SELECT file_id, embedding FROM file_embeddings;"
        var results: [(fileId: UUID, embedding: [Float])] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let fileIdStr = sqlite3_column_text(stmt, 0) else { continue }
                let fileId = UUID(uuidString: String(cString: fileIdStr)) ?? UUID()
                
                // Read BLOB as [Float]
                if let blobPtr = sqlite3_column_blob(stmt, 1) {
                    let blobSize = Int(sqlite3_column_bytes(stmt, 1))
                    let floatCount = blobSize / MemoryLayout<Float>.size
                    
                    let buffer = blobPtr.assumingMemoryBound(to: Float.self)
                    let embedding = Array(UnsafeBufferPointer(start: buffer, count: floatCount))
                    
                    results.append((fileId, embedding))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return results
    }
    
    /// Get embedding for specific file
    func getFileEmbedding(fileId: UUID) async -> [Float]? {
        openDatabase()
        
        let sql = "SELECT embedding FROM file_embeddings WHERE file_id = ?;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, fileId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let blobPtr = sqlite3_column_blob(stmt, 0) {
                    let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                    let floatCount = blobSize / MemoryLayout<Float>.size
                    
                    let buffer = blobPtr.assumingMemoryBound(to: Float.self)
                    let embedding = Array(UnsafeBufferPointer(start: buffer, count: floatCount))
                    
                    sqlite3_finalize(stmt)
                    return embedding
                }
            }
        }
        sqlite3_finalize(stmt)
        return nil
    }
    
    // MARK: - Auto Rule Operations
    func saveRule(_ rule: AutoRule) async {
        dbQueue.sync {
            openDatabase()
            
            // 1. Insert Rule
            let ruleSql = "INSERT OR REPLACE INTO rules (id, name, is_enabled, match_type, created_at) VALUES (?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, ruleSql, -1, &stmt, nil) == SQLITE_OK {
                let id = rule.id.uuidString
                let name = rule.name
                let enabled = rule.isEnabled ? 1 : 0
                let matchType = rule.matchType.rawValue
                let createdAt = ISO8601DateFormatter().string(from: rule.createdAt)
                
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 3, Int32(enabled))
                sqlite3_bind_text(stmt, 4, matchType, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, createdAt, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            // 2. Delete existing conditions/actions
            executeSQL("DELETE FROM rule_conditions WHERE rule_id = '\(rule.id.uuidString)';")
            executeSQL("DELETE FROM rule_actions WHERE rule_id = '\(rule.id.uuidString)';")
            
            // 3. Insert Conditions
            let condSql = "INSERT INTO rule_conditions (id, rule_id, field, operator, value) VALUES (?, ?, ?, ?, ?);"
            for cond in rule.conditions {
                if sqlite3_prepare_v2(db, condSql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, cond.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, rule.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, cond.field.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 4, cond.operator.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 5, cond.value, -1, SQLITE_TRANSIENT)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
            
            // 4. Insert Actions
            let actSql = "INSERT INTO rule_actions (id, rule_id, type, target_value) VALUES (?, ?, ?, ?);"
            for action in rule.actions {
                if sqlite3_prepare_v2(db, actSql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, action.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, rule.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, action.type.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 4, action.targetValue, -1, SQLITE_TRANSIENT)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
    }
    
    func getAllRules() async -> [AutoRule] {
        openDatabase()
        
        let sql = "SELECT * FROM rules ORDER BY created_at DESC;"
        var rules: [AutoRule] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idStr = sqlite3_column_text(stmt, 0),
                   let nameStr = sqlite3_column_text(stmt, 1),
                   let matchTypeStr = sqlite3_column_text(stmt, 3) {
                    let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
                    let name = String(cString: nameStr)
                    let isEnabled = sqlite3_column_int(stmt, 2) != 0
                    let matchType = RuleMatchType(rawValue: String(cString: matchTypeStr)) ?? .all
                    
                    var rule = AutoRule(id: id, name: name, isEnabled: isEnabled, matchType: matchType)
                    rules.append(rule)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        // Load Details for each rule
        for i in 0..<rules.count {
            rules[i].conditions = await getConditions(for: rules[i].id)
            rules[i].actions = await getActions(for: rules[i].id)
        }
        
        return rules
    }
    
    // Helper to get conditions
    private func getConditions(for ruleId: UUID) async -> [RuleCondition] {
        let sql = "SELECT * FROM rule_conditions WHERE rule_id = ?;"
        var list: [RuleCondition] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, ruleId.uuidString, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idStr = sqlite3_column_text(stmt, 0),
                   let fieldStr = sqlite3_column_text(stmt, 2),
                   let opStr = sqlite3_column_text(stmt, 3),
                   let valStr = sqlite3_column_text(stmt, 4) {
                       let field = RuleConditionField(rawValue: String(cString: fieldStr)) ?? .fileName
                       let op = RuleOperator(rawValue: String(cString: opStr)) ?? .contains
                       list.append(RuleCondition(
                           id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                           field: field,
                           operator: op,
                           value: String(cString: valStr)
                       ))
                   }
            }
        }
        sqlite3_finalize(stmt)
        return list
    }
    
    // Helper to get actions
    private func getActions(for ruleId: UUID) async -> [RuleAction] {
        let sql = "SELECT * FROM rule_actions WHERE rule_id = ?;"
        var list: [RuleAction] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, ruleId.uuidString, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idStr = sqlite3_column_text(stmt, 0),
                   let typeStr = sqlite3_column_text(stmt, 2),
                   let valStr = sqlite3_column_text(stmt, 3) {
                       let type = RuleActionType(rawValue: String(cString: typeStr)) ?? .addTag
                       list.append(RuleAction(
                           id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                           type: type,
                           targetValue: String(cString: valStr)
                       ))
                   }
            }
        }
        sqlite3_finalize(stmt)
        return list
    }
    
    func deleteRule(_ ruleId: UUID) async {
        dbQueue.sync {
            openDatabase()
            let id = ruleId.uuidString
            executeSQL("DELETE FROM rules WHERE id = '\(id)';")
            executeSQL("DELETE FROM rule_conditions WHERE rule_id = '\(id)';")
            executeSQL("DELETE FROM rule_actions WHERE rule_id = '\(id)';")
        }
    }
}
