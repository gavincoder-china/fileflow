//
//  CloudSyncService.swift
//  FileFlow
//
//  iCloud 同步服务 (CloudKit)
//  负责将本地 SQLite 数据同步到 iCloud 私有数据库
//
//  注意：需要在 Xcode 中配置 iCloud Capability 才能使用
//

import Foundation
import CloudKit
import SwiftUI

@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()
    
    // Published state
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    @Published var isAvailable = false
    
    private init() {
        // Load last sync time from UserDefaults
        if let time = UserDefaults.standard.object(forKey: "lastCloudSyncTime") as? Date {
            lastSyncTime = time
        }
        
        // Don't call any CloudKit APIs here - they crash without proper entitlements
        // Availability will be checked on first sync attempt
    }
    
    // MARK: - Public API
    
    func syncNow() async {
        // First, check if CloudKit is available
        let available = await checkAvailability()
        
        guard available else {
            await MainActor.run {
                syncError = "iCloud 不可用。请确保已登录 iCloud 账户，并在 Xcode 中配置 iCloud Capability。"
                isAvailable = false
            }
            Logger.warning("CloudKit sync skipped - not available")
            return
        }
        
        await MainActor.run { 
            isSyncing = true
            syncError = nil 
        }
        
        do {
            let container = CKContainer.default()
            let database = container.privateCloudDatabase
            let zoneId = CKRecordZone.ID(zoneName: "FileFlowZone", ownerName: CKCurrentUserDefaultName)
            
            // 1. Setup Zone if needed
            let zone = CKRecordZone(zoneID: zoneId)
            try await database.save(zone)
            Logger.info("CloudKit Zone created/verified")
            
            // 2. Push local changes to Cloud
            let files = await DatabaseManager.shared.getAllFiles()
            let filesToSync = files.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(10)
            
            for file in filesToSync {
                let recordId = CKRecord.ID(recordName: file.id.uuidString, zoneID: zoneId)
                let record: CKRecord
                do {
                    record = try await database.record(for: recordId)
                } catch {
                    record = CKRecord(recordType: "ManagedFile", recordID: recordId)
                }
                
                record["originalName"] = file.originalName
                record["newName"] = file.newName
                record["originalPath"] = file.originalPath
                record["newPath"] = file.newPath
                record["categoryRaw"] = file.category.rawValue
                record["summary"] = file.summary
                
                try await database.save(record)
            }
            
            Logger.info("Pushed \(filesToSync.count) records to cloud")
            
            await MainActor.run {
                lastSyncTime = Date()
                UserDefaults.standard.set(lastSyncTime, forKey: "lastCloudSyncTime")
                isSyncing = false
            }
            Logger.info("CloudKit Sync Completed Successfully")
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
                isSyncing = false
            }
            Logger.error("CloudKit Sync Failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func checkAvailability() async -> Bool {
        // Try to get account status - this is the safest way to check
        do {
            let container = CKContainer.default()
            let status = try await container.accountStatus()
            let available = (status == .available)
            await MainActor.run { isAvailable = available }
            return available
        } catch {
            Logger.error("CloudKit availability check failed: \(error)")
            await MainActor.run { isAvailable = false }
            return false
        }
    }
}
