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

actor DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private var currentDbPath: String?
    
    // Actor handles serialization, no queue needed
    
    // SQLITE_TRANSIENT tells SQLite to make its own copy of the string
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private init() {
         // Database will be opened lazily when accessed
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
                enableWALMode()
                createTables()
            } else {
                Logger.error("Failed to open database at \(dbPath)")
            }
        }
    }
    
    // MARK: - Enable WAL Mode
    
    /// 启用 WAL 模式和性能优化
    /// WAL (Write-Ahead Logging) 提供更好的并发性和性能
    private func enableWALMode() {
        // WAL mode for better concurrency
        executeSQL("PRAGMA journal_mode = WAL;")
        
        // Synchronous NORMAL for better performance (still safe with WAL)
        executeSQL("PRAGMA synchronous = NORMAL;")
        
        // Page size optimization
        executeSQL("PRAGMA page_size = 4096;")
        
        // Cache size (negative = KB, ~8MB)
        executeSQL("PRAGMA cache_size = -8000;")
        
        // Memory-mapped I/O for faster reads (256MB)
        executeSQL("PRAGMA mmap_size = 268435456;")
        
        // Enable foreign keys
        executeSQL("PRAGMA foreign_keys = ON;")
        
        // Temp store in memory
        executeSQL("PRAGMA temp_store = MEMORY;")
        
        Logger.success("SQLite WAL mode enabled with performance pragmas")
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
            Logger.database("Migrating: Adding is_favorite column to tags")
            executeSQL("ALTER TABLE tags ADD COLUMN is_favorite INTEGER DEFAULT 0;")
        }
        
        if !hasParentId {
            Logger.database("Migrating: Adding parent_id column to tags")
            executeSQL("ALTER TABLE tags ADD COLUMN parent_id TEXT;")
        }
        
        // Check subcategories table for parent_subcategory_id column
        checkAndMigrateSubcategories()
    }
    
    private func checkAndMigrateSubcategories() {
        let sql = "PRAGMA table_info(subcategories);"
        var stmt: OpaquePointer?
        var hasParentSubcategoryId = false
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    let columnName = String(cString: name)
                    if columnName == "parent_subcategory_id" {
                        hasParentSubcategoryId = true
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        if !hasParentSubcategoryId {
            Logger.database("Migrating: Adding parent_subcategory_id column to subcategories")
            executeSQL("ALTER TABLE subcategories ADD COLUMN parent_subcategory_id TEXT;")
        }
        
        // Migrate lifecycle columns
        checkAndMigrateLifecycle()
    }
    
    // MARK: - Lifecycle Migration
    private func checkAndMigrateLifecycle() {
        let sql = "PRAGMA table_info(files);"
        var stmt: OpaquePointer?
        var hasLifecycleStage = false
        var hasLastAccessedAt = false
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    let columnName = String(cString: name)
                    if columnName == "lifecycle_stage" {
                        hasLifecycleStage = true
                    }
                    if columnName == "last_accessed_at" {
                        hasLastAccessedAt = true
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        if !hasLifecycleStage {
            Logger.database("Migrating: Adding lifecycle_stage column to files")
            executeSQL("ALTER TABLE files ADD COLUMN lifecycle_stage TEXT DEFAULT 'active';")
        }
        
        if !hasLastAccessedAt {
            Logger.database("Migrating: Adding last_accessed_at column to files")
            executeSQL("ALTER TABLE files ADD COLUMN last_accessed_at TEXT;")
            // Set initial value to imported_at for existing files
            executeSQL("UPDATE files SET last_accessed_at = imported_at WHERE last_accessed_at IS NULL;")
        }
        
        // Create file_transitions table if not exists
        createTransitionsTable()
    }
    
    private func createTransitionsTable() {
        let createTransitionsTable = """
        CREATE TABLE IF NOT EXISTS file_transitions (
            id TEXT PRIMARY KEY,
            file_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            from_category TEXT NOT NULL,
            to_category TEXT NOT NULL,
            from_subcategory TEXT,
            to_subcategory TEXT,
            reason TEXT NOT NULL,
            notes TEXT,
            triggered_at TEXT NOT NULL,
            is_automatic INTEGER NOT NULL DEFAULT 0,
            confirmed_by_user INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (file_id) REFERENCES files(id)
        );
        """
        executeSQL(createTransitionsTable)
        
        // Create indexes for transitions
        executeSQL("CREATE INDEX IF NOT EXISTS idx_transitions_file ON file_transitions(file_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_transitions_date ON file_transitions(triggered_at);")
        
        Logger.database("File transitions table ready")
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
            parent_subcategory_id TEXT,
            created_at TEXT,
            UNIQUE(name, parent_category, parent_subcategory_id),
            FOREIGN KEY (parent_subcategory_id) REFERENCES subcategories(id)
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
        
        // Lifecycle performance indexes
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_lifecycle ON files(lifecycle_stage);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_last_accessed ON files(last_accessed_at);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_category_lifecycle ON files(category, lifecycle_stage);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_files_subcategory ON files(subcategory);")
    }

    
    private func executeSQL(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                Logger.error("SQL Error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }
    // MARK: - Tag Operations
    func saveTag(_ tag: Tag) async {
            openDatabase() // 确保数据库已打开
            
            let sql = """
            INSERT INTO tags (id, name, color, usage_count, is_favorite, parent_id, created_at, last_used_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                color = excluded.color,
                usage_count = excluded.usage_count,
                is_favorite = excluded.is_favorite,
                parent_id = excluded.parent_id,
                created_at = excluded.created_at,
                last_used_at = excluded.last_used_at;
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
                    Logger.error("Tag save failed: \(result)")
                }
            }
            sqlite3_finalize(stmt)
        }



    
    func toggleTagFavorite(_ tag: Tag) async {
        openDatabase()
        
        // 直接使用 UPDATE 语句切换 is_favorite 状态，确保更新成功
        let newFavoriteValue: Int32 = tag.isFavorite ? 0 : 1
        let sql = "UPDATE tags SET is_favorite = ? WHERE id = ?;"
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let idString = tag.id.uuidString
            sqlite3_bind_int(stmt, 1, newFavoriteValue)
            sqlite3_bind_text(stmt, 2, idString, -1, SQLITE_TRANSIENT)
            
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE {
                let changesCount = sqlite3_changes(db)
                if changesCount > 0 {
                    Logger.database("Tag favorite toggled: \(tag.name) -> \(newFavoriteValue == 1 ? "favorite" : "unfavorite")")
                } else {
                    Logger.error("Toggle favorite failed: No rows updated for tag \(tag.name)")
                }
            } else {
                Logger.error("Toggle favorite SQL failed with result: \(result)")
            }
        } else {
            Logger.error("Failed to prepare toggle favorite SQL")
        }
        sqlite3_finalize(stmt)
    }
    
    func deleteTag(_ tag: Tag) async {
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
                Logger.success("Deleted tag: \(tag.name)")
            } else {
                Logger.error("Failed to delete tag: \(result)")
            }
        }
        sqlite3_finalize(stmt)
    }

    
    func renameTag(oldTag: Tag, newName: String) async throws {
        openDatabase()
        Logger.database("Renaming tag \(oldTag.name) to \(newName)")
        
        // 1. Update Tag Name in DB
        var updatedTag = oldTag
        updatedTag.name = newName
        await saveTag(updatedTag)
        
        // 2. Find all affected files
        let files = await getFilesWithTag(oldTag)
        Logger.debug("Found \(files.count) files to rename")
        
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
                Logger.fileOperation("Renamed on disk", path: newFileName)
                
                // Update File Record
                var newFile = file
                newFile.newName = newFileName
                newFile.newPath = newURL.path
                newFile.modifiedAt = Date()
                
                // Refresh tags for this file (now containing the renamed tag from DB)
                let tags = await getTagsForFile(fileId: file.id)
                
                await saveFile(newFile, tags: tags)
                
            } catch {
                Logger.error("Error renaming file: \(error)")
                // Continue to next file (best effort)
            }
        }
    }

    func getAllTags() async -> [Tag] {
        openDatabase()
        
        let sql = "SELECT id, name, color, usage_count, is_favorite, parent_id, created_at, last_used_at FROM tags ORDER BY usage_count DESC, last_used_at DESC;"
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
        
        let sql = "SELECT id, name, color, usage_count, is_favorite, parent_id, created_at, last_used_at FROM tags WHERE name LIKE ? ORDER BY usage_count DESC LIMIT 10;"
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
        openDatabase()
        
        // 计算相对路径
        let relativePath = calculateRelativePath(for: file.newPath)
        
        let sql = """
        INSERT OR REPLACE INTO files 
        (id, original_name, new_name, original_path, current_path, relative_path, category, subcategory, summary, notes, file_size, file_type, created_at, imported_at, modified_at, lifecycle_stage, last_accessed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let formatter = ISO8601DateFormatter()
            
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
            
            // Lifecycle fields
            let lifecycleStageString = file.lifecycleStage.rawValue
            let lastAccessedAtString = formatter.string(from: file.lastAccessedAt)
            sqlite3_bind_text(stmt, 16, lifecycleStageString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 17, lastAccessedAtString, -1, SQLITE_TRANSIENT)
            
            let result = sqlite3_step(stmt)
            if result != SQLITE_DONE {
                Logger.error("File save failed: \(result)")
            }
        }
        sqlite3_finalize(stmt)
        
        // Clear existing tags
        let fileIdStr = file.id.uuidString
        executeSQL("DELETE FROM file_tags WHERE file_id = '\(fileIdStr)';")
        
        // Save file-tag relationships (outside dbQueue.sync to avoid nested calls)
        for tag in tags {
            await saveFileTagRelation(fileId: file.id, tagId: tag.id)
            await incrementTagUsage(tag.id)
        }
        
        // Index to Spotlight for system-wide search
        var fileWithTags = file
        fileWithTags.tags = tags
        await SpotlightIndexService.shared.indexFile(fileWithTags)
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
    
    /// 根据路径获取文件
    func getFile(byPath path: String) async -> ManagedFile? {
        openDatabase()
        
        let sql = "SELECT * FROM files WHERE new_path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var file: ManagedFile?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                if var parsedFile = parseFile(from: stmt) {
                    let fileId = parsedFile.id
                    parsedFile.tags = await getTagsForFile(fileId: fileId)
                    file = parsedFile
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return file
    }
    
    /// 根据 ID 获取文件
    func getFile(byId id: UUID) async -> ManagedFile? {
        openDatabase()
        
        let sql = "SELECT * FROM files WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var file: ManagedFile?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                if var parsedFile = parseFile(from: stmt) {
                    let fileId = parsedFile.id
                    parsedFile.tags = await getTagsForFile(fileId: fileId)
                    file = parsedFile
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return file
    }
    
    /// 更新文件信息
    func updateFile(_ file: ManagedFile) async {
        openDatabase()
        
        let sql = """
        UPDATE files SET
            new_name = ?,
            new_path = ?,
            category = ?,
            subcategory = ?,
            summary = ?,
            notes = ?,
            modified_at = ?,
            lifecycle_stage = ?,
            last_accessed_at = ?,
            content_hash = ?
        WHERE id = ?;
        """
        
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let dateFormatter = ISO8601DateFormatter()
            
            sqlite3_bind_text(stmt, 1, file.newName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, file.newPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, file.category.rawValue, -1, SQLITE_TRANSIENT)
            
            if let subcategory = file.subcategory {
                sqlite3_bind_text(stmt, 4, subcategory, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            if let summary = file.summary {
                sqlite3_bind_text(stmt, 5, summary, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            
            if let notes = file.notes {
                sqlite3_bind_text(stmt, 6, notes, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            
            sqlite3_bind_text(stmt, 7, dateFormatter.string(from: file.modifiedAt), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, file.lifecycleStage.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, dateFormatter.string(from: file.lastAccessedAt), -1, SQLITE_TRANSIENT)
            
            if let hash = file.contentHash {
                sqlite3_bind_text(stmt, 10, hash, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            
            sqlite3_bind_text(stmt, 11, file.id.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                Logger.error("Failed to update file: \(file.id)")
            }
        }
        sqlite3_finalize(stmt)
    }
    
    func saveFileTagRelation(fileId: UUID, tagId: UUID) async {
        let sql = "INSERT OR IGNORE INTO file_tags (file_id, tag_id) VALUES (?, ?);"
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let fileIdString = fileId.uuidString
            let tagIdString = tagId.uuidString
            
            sqlite3_bind_text(stmt, 1, fileIdString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, tagIdString, -1, SQLITE_TRANSIENT)
            
            let result = sqlite3_step(stmt)
            if result != SQLITE_DONE {
                Logger.error("File-tag relation save failed: \(result)")
            }
        }
        sqlite3_finalize(stmt)
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
        openDatabase()
        let id = fileId.uuidString
        executeSQL("DELETE FROM files WHERE id = '\(id)';")
        executeSQL("DELETE FROM file_tags WHERE file_id = '\(id)';")
        executeSQL("DELETE FROM file_embeddings WHERE file_id = '\(id)';")
    }

    /// Get all files from the database
    func getAllFiles() async -> [ManagedFile] {
        openDatabase()
        
        let sql = "SELECT * FROM files ORDER BY imported_at DESC;"
        var files: [ManagedFile] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
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
    
    /// Get files for category with pagination (lazy loading)
    /// - Parameters:
    ///   - category: PARA category
    ///   - limit: Number of files to fetch
    ///   - offset: Starting offset for pagination
    /// - Returns: Paginated files and hasMore flag
    func getFilesForCategoryPaginated(_ category: PARACategory, limit: Int = 50, offset: Int = 0) async -> (files: [ManagedFile], hasMore: Bool) {
        openDatabase()
        
        // Fetch one extra to check if there are more
        let sql = """
        SELECT * FROM files
        WHERE category = ?
        ORDER BY imported_at DESC
        LIMIT ? OFFSET ?;
        """
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let categoryString = category.rawValue
            sqlite3_bind_text(stmt, 1, categoryString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit + 1)) // Fetch one extra
            sqlite3_bind_int(stmt, 3, Int32(offset))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if var file = parseFile(from: stmt) {
                    let fileId = file.id
                    file.tags = await self.getTagsForFile(fileId: fileId)
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        // Check if there are more
        let hasMore = files.count > limit
        if hasMore {
            files.removeLast()
        }
        
        return (files, hasMore)
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
    
    /// Add a tag to a file
    func addTagToFile(tagId: UUID, fileId: UUID) async {
        openDatabase()
        
        let sql = "INSERT OR IGNORE INTO file_tags (file_id, tag_id) VALUES (?, ?);"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, fileId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, tagId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Update tag usage count
                await incrementTagUsage(tagId: tagId)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    /// Remove a tag from a file
    func removeTagFromFile(tagId: UUID, fileId: UUID) async {
        openDatabase()
        
        let sql = "DELETE FROM file_tags WHERE file_id = ? AND tag_id = ?;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, fileId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, tagId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Decrement tag usage count
                await decrementTagUsage(tagId: tagId)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    /// Increment tag usage count
    private func incrementTagUsage(tagId: UUID) async {
        let sql = "UPDATE tags SET usage_count = usage_count + 1 WHERE id = ?;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, tagId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    /// Decrement tag usage count
    private func decrementTagUsage(tagId: UUID) async {
        let sql = "UPDATE tags SET usage_count = MAX(0, usage_count - 1) WHERE id = ?;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, tagId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
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
    
    /// 使用自然语言解析结果进行结构化搜索
    func searchFilesWithFilters(parsed: ParsedQuery) async -> [ManagedFile] {
        openDatabase()
        
        var conditions: [String] = []
        var params: [String] = []
        
        // 时间范围
        if let start = parsed.dateRange.start {
            conditions.append("imported_at >= ?")
            params.append(ISO8601DateFormatter().string(from: start))
        }
        if let end = parsed.dateRange.end {
            conditions.append("imported_at <= ?")
            params.append(ISO8601DateFormatter().string(from: end))
        }
        
        // 文件类型
        if !parsed.fileTypes.isEmpty {
            let placeholders = parsed.fileTypes.map { _ in "?" }.joined(separator: ", ")
            conditions.append("LOWER(file_type) IN (\(placeholders))")
            params.append(contentsOf: parsed.fileTypes)
        }
        
        // 分类
        if !parsed.categories.isEmpty {
            let placeholders = parsed.categories.map { _ in "?" }.joined(separator: ", ")
            conditions.append("category IN (\(placeholders))")
            params.append(contentsOf: parsed.categories.map { $0.rawValue })
        }
        
        // 关键词
        for keyword in parsed.keywords {
            conditions.append("(new_name LIKE ? OR original_name LIKE ? OR summary LIKE ?)")
            let pattern = "%\(keyword)%"
            params.append(contentsOf: [pattern, pattern, pattern])
        }
        
        let whereClause = conditions.isEmpty ? "1=1" : conditions.joined(separator: " AND ")
        let sql = """
        SELECT * FROM files WHERE \(whereClause) ORDER BY imported_at DESC LIMIT 100;
        """
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (index, param) in params.enumerated() {
                sqlite3_bind_text(stmt, Int32(index + 1), param, -1, SQLITE_TRANSIENT)
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let file = parseFile(from: stmt) {
                    files.append(file)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        // 如果有标签过滤，再做一次筛选
        if !parsed.tags.isEmpty {
            var filteredFiles: [ManagedFile] = []
            for var file in files {
                let fileTags = await getTagsForFile(fileId: file.id)
                let fileTagNames = Set(fileTags.map { $0.name.lowercased() })
                let queryTags = Set(parsed.tags.map { $0.lowercased() })
                
                if !queryTags.isDisjoint(with: fileTagNames) {
                    file.tags = fileTags
                    filteredFiles.append(file)
                }
            }
            return filteredFiles
        }
        
        return files
    }
    
    func getTagsForFile(fileId: UUID) async -> [Tag] {
        let sql = """
        SELECT t.id, t.name, t.color, t.usage_count, t.is_favorite, t.parent_id, t.created_at, t.last_used_at FROM tags t
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
        let category = PARACategory(rawValue: String(cString: categoryStr)) ?? .resources
        
        // Parse lifecycle fields (columns 15, 16 after migration)
        var lifecycleStage: FileLifecycleStage = .active
        var lastAccessedAt: Date = Date()
        
        if let lifecycleStr = sqlite3_column_text(stmt, 15) {
            lifecycleStage = FileLifecycleStage(rawValue: String(cString: lifecycleStr)) ?? .active
        }
        if let lastAccessedStr = sqlite3_column_text(stmt, 16) {
            lastAccessedAt = formatter.date(from: String(cString: lastAccessedStr)) ?? Date()
        }
        
        var file = ManagedFile(
            id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
            originalName: String(cString: originalNameStr),
            originalPath: String(cString: originalPathStr),
            category: category,
            lifecycleStage: lifecycleStage,
            lastAccessedAt: lastAccessedAt
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
        INSERT OR IGNORE INTO subcategories (id, name, parent_category, parent_subcategory_id, created_at)
        VALUES (?, ?, ?, ?, ?);
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
            
            // Bind parent_subcategory_id (nullable)
            if let parentSubId = subcategory.parentSubcategoryId {
                sqlite3_bind_text(stmt, 4, parentSubId.uuidString, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            sqlite3_bind_text(stmt, 5, createdAtString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    func getSubcategories(for category: PARACategory) async -> [Subcategory] {
        openDatabase()
        
        let sql = "SELECT id, name, parent_category, parent_subcategory_id, created_at FROM subcategories WHERE parent_category = ? ORDER BY name;"
        var subcategories: [Subcategory] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let categoryString = category.rawValue
            sqlite3_bind_text(stmt, 1, categoryString, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idStr = sqlite3_column_text(stmt, 0),
                   let nameStr = sqlite3_column_text(stmt, 1) {
                    var parentSubId: UUID? = nil
                    if let parentSubIdStr = sqlite3_column_text(stmt, 3) {
                        parentSubId = UUID(uuidString: String(cString: parentSubIdStr))
                    }
                    let subcategory = Subcategory(
                        id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                        name: String(cString: nameStr),
                        parentCategory: category,
                        parentSubcategoryId: parentSubId
                    )
                    subcategories.append(subcategory)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return subcategories
    }
    
    /// Get all subcategories across all categories
    func getAllSubcategories() async -> [Subcategory] {
        openDatabase()
        
        let sql = "SELECT id, name, parent_category, parent_subcategory_id, created_at FROM subcategories ORDER BY parent_category, name;"
        var subcategories: [Subcategory] = []
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idStr = sqlite3_column_text(stmt, 0),
                   let nameStr = sqlite3_column_text(stmt, 1),
                   let catStr = sqlite3_column_text(stmt, 2),
                   let category = PARACategory(rawValue: String(cString: catStr)) {
                    var parentSubId: UUID? = nil
                    if let parentSubIdStr = sqlite3_column_text(stmt, 3) {
                        parentSubId = UUID(uuidString: String(cString: parentSubIdStr))
                    }
                    let subcategory = Subcategory(
                        id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                        name: String(cString: nameStr),
                        parentCategory: category,
                        parentSubcategoryId: parentSubId
                    )
                    subcategories.append(subcategory)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return subcategories
    }
    
    func renameSubcategory(oldName: String, newName: String, category: PARACategory) async {
        openDatabase()
        
        // 1. Update subcategories table
        let updateSubSql = "UPDATE subcategories SET name = ? WHERE name = ? AND parent_category = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSubSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, newName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, oldName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // 2. Update files table
        let updateFilesSql = "UPDATE files SET subcategory = ? WHERE subcategory = ? AND category = ?;"
        if sqlite3_prepare_v2(db, updateFilesSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, newName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, oldName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    func deleteSubcategory(name: String, category: PARACategory) async {
        openDatabase()
        
        // 1. Delete from subcategories table
        let deleteSql = "DELETE FROM subcategories WHERE name = ? AND parent_category = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // 2. Clear subcategory from files (move to root of category)
        let updateFilesSql = "UPDATE files SET subcategory = NULL WHERE subcategory = ? AND category = ?;"
        if sqlite3_prepare_v2(db, updateFilesSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    func mergeSubcategories(from sourceName: String, to targetName: String, category: PARACategory) async {
        openDatabase()
        
        // 1. Delete source subcategory
        let deleteSql = "DELETE FROM subcategories WHERE name = ? AND parent_category = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sourceName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // 2. Move files from source to target
        let updateFilesSql = "UPDATE files SET subcategory = ? WHERE subcategory = ? AND category = ?;"
        if sqlite3_prepare_v2(db, updateFilesSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, targetName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sourceName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
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
            _ = embeddingData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(embeddingData.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_text(stmt, 3, provider, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, createdAt, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                Logger.error("Embedding save failed")
            }
        }
        sqlite3_finalize(stmt)
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
                    
                    let rule = AutoRule(id: id, name: name, isEnabled: isEnabled, matchType: matchType)
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
        openDatabase()
        let id = ruleId.uuidString
        executeSQL("DELETE FROM rules WHERE id = '\(id)';")
        executeSQL("DELETE FROM rule_conditions WHERE rule_id = '\(id)';")
        executeSQL("DELETE FROM rule_actions WHERE rule_id = '\(id)';")
    }
    
    // MARK: - File Lifecycle Operations
    
    /// Save a file transition record
    func saveTransition(_ transition: FileTransition) async {
        openDatabase()
        
        let sql = """
        INSERT INTO file_transitions 
        (id, file_id, file_name, from_category, to_category, from_subcategory, to_subcategory, reason, notes, triggered_at, is_automatic, confirmed_by_user)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let formatter = ISO8601DateFormatter()
            
            sqlite3_bind_text(stmt, 1, transition.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, transition.fileId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, transition.fileName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, transition.fromCategory.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, transition.toCategory.rawValue, -1, SQLITE_TRANSIENT)
            
            if let fromSub = transition.fromSubcategory {
                sqlite3_bind_text(stmt, 6, fromSub, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            
            if let toSub = transition.toSubcategory {
                sqlite3_bind_text(stmt, 7, toSub, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            
            sqlite3_bind_text(stmt, 8, transition.reason.rawValue, -1, SQLITE_TRANSIENT)
            
            if let notes = transition.notes {
                sqlite3_bind_text(stmt, 9, notes, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            
            sqlite3_bind_text(stmt, 10, formatter.string(from: transition.triggeredAt), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 11, transition.isAutomatic ? 1 : 0)
            sqlite3_bind_int(stmt, 12, transition.confirmedByUser ? 1 : 0)
            
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE {
                Logger.database("Saved transition: \(transition.fileName) \(transition.fromCategory.rawValue) → \(transition.toCategory.rawValue)")
            } else {
                Logger.error("Failed to save transition: \(result)")
            }
        }
        sqlite3_finalize(stmt)
    }
    
    /// Get all transitions for a specific file
    func getTransitions(forFileId fileId: UUID) async -> [FileTransition] {
        openDatabase()
        
        let sql = """
        SELECT * FROM file_transitions 
        WHERE file_id = ? 
        ORDER BY triggered_at DESC;
        """
        
        var transitions: [FileTransition] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, fileId.uuidString, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let transition = parseTransition(from: stmt) {
                    transitions.append(transition)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return transitions
    }
    
    /// Get recent transitions across all files
    func getRecentTransitions(limit: Int = 50) async -> [FileTransition] {
        openDatabase()
        
        let sql = """
        SELECT * FROM file_transitions 
        ORDER BY triggered_at DESC 
        LIMIT ?;
        """
        
        var transitions: [FileTransition] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let transition = parseTransition(from: stmt) {
                    transitions.append(transition)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return transitions
    }
    
    private func parseTransition(from stmt: OpaquePointer?) -> FileTransition? {
        guard let stmt = stmt,
              let idStr = sqlite3_column_text(stmt, 0),
              let fileIdStr = sqlite3_column_text(stmt, 1),
              let fileNameStr = sqlite3_column_text(stmt, 2),
              let fromCatStr = sqlite3_column_text(stmt, 3),
              let toCatStr = sqlite3_column_text(stmt, 4),
              let reasonStr = sqlite3_column_text(stmt, 7) else {
            return nil
        }
        
        let fromSubcategory: String? = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let toSubcategory: String? = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let notes: String? = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        
        return FileTransition(
            id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
            fileId: UUID(uuidString: String(cString: fileIdStr)) ?? UUID(),
            fileName: String(cString: fileNameStr),
            from: PARACategory(rawValue: String(cString: fromCatStr)) ?? .resources,
            to: PARACategory(rawValue: String(cString: toCatStr)) ?? .archives,
            fromSub: fromSubcategory,
            toSub: toSubcategory,
            reason: TransitionReason(rawValue: String(cString: reasonStr)) ?? .userManual,
            notes: notes,
            isAutomatic: sqlite3_column_int(stmt, 10) != 0,
            confirmedByUser: sqlite3_column_int(stmt, 11) != 0
        )
    }
    
    /// Update file lifecycle stage
    func updateLifecycleStage(fileId: UUID, stage: FileLifecycleStage) async {
        openDatabase()
        
        let sql = "UPDATE files SET lifecycle_stage = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, stage.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, fileId.uuidString, -1, SQLITE_TRANSIENT)
            
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE {
                Logger.database("Updated lifecycle stage for file to: \(stage.rawValue)")
            }
        }
        sqlite3_finalize(stmt)
    }
    
    /// Update file last accessed time (call when file is opened/viewed)
    func updateLastAccessedAt(fileId: UUID) async {
        openDatabase()
        
        let sql = "UPDATE files SET last_accessed_at = ?, lifecycle_stage = 'active' WHERE id = ?;"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let formatter = ISO8601DateFormatter()
            sqlite3_bind_text(stmt, 1, formatter.string(from: Date()), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, fileId.uuidString, -1, SQLITE_TRANSIENT)
            
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    /// Get files by lifecycle stage
    func getFiles(byLifecycleStage stage: FileLifecycleStage) async -> [ManagedFile] {
        openDatabase()
        
        let sql = "SELECT * FROM files WHERE lifecycle_stage = ? ORDER BY last_accessed_at ASC;"
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, stage.rawValue, -1, SQLITE_TRANSIENT)
            
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
    
    /// Get files that haven't been accessed in specified days
    func getInactiveFiles(daysThreshold: Int) async -> [ManagedFile] {
        openDatabase()
        
        let sql = """
        SELECT * FROM files 
        WHERE category != 'Archives' 
        AND (
            last_accessed_at IS NULL 
            OR julianday('now') - julianday(last_accessed_at) > ?
        )
        ORDER BY last_accessed_at ASC;
        """
        
        var files: [ManagedFile] = []
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(daysThreshold))
            
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
    
    /// Refresh lifecycle stages for all files based on last access time
    func refreshAllLifecycleStages() async {
        openDatabase()
        
        // Update to dormant (30-90 days)
        executeSQL("""
            UPDATE files SET lifecycle_stage = 'dormant' 
            WHERE category != 'Archives' 
            AND lifecycle_stage = 'active'
            AND julianday('now') - julianday(last_accessed_at) BETWEEN 30 AND 90;
        """)
        
        // Update to stale (90+ days)
        executeSQL("""
            UPDATE files SET lifecycle_stage = 'stale' 
            WHERE category != 'Archives' 
            AND lifecycle_stage IN ('active', 'dormant')
            AND julianday('now') - julianday(last_accessed_at) > 90;
        """)
        
        // Ensure archived category files have archived stage
        executeSQL("""
            UPDATE files SET lifecycle_stage = 'archived' 
            WHERE category = 'Archives' AND lifecycle_stage != 'archived';
        """)
        
        Logger.database("Refreshed lifecycle stages for all files")
    }
    
    /// Get lifecycle statistics
    func getLifecycleStats() async -> [FileLifecycleStage: Int] {
        openDatabase()
        
        let sql = "SELECT lifecycle_stage, COUNT(*) FROM files GROUP BY lifecycle_stage;"
        var stats: [FileLifecycleStage: Int] = [:]
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let stageStr = sqlite3_column_text(stmt, 0) {
                    let stage = FileLifecycleStage(rawValue: String(cString: stageStr)) ?? .active
                    let count = Int(sqlite3_column_int(stmt, 1))
                    stats[stage] = count
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return stats
    }
}
