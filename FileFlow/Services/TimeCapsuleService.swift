//
//  TimeCapsuleService.swift
//  FileFlow
//
//  时间胶囊服务 - 设定未来日期解锁文件
//

import Foundation
import SwiftUI

// MARK: - Time Capsule Model
struct TimeCapsule: Codable, Identifiable {
    let id: UUID
    let fileId: UUID
    let fileName: String
    let filePath: String
    let unlockDate: Date
    let createdAt: Date
    var note: String
    var isOpened: Bool
    
    init(fileId: UUID, fileName: String, filePath: String, unlockDate: Date, note: String = "") {
        self.id = UUID()
        self.fileId = fileId
        self.fileName = fileName
        self.filePath = filePath
        self.unlockDate = unlockDate
        self.createdAt = Date()
        self.note = note
        self.isOpened = false
    }
    
    var isUnlocked: Bool {
        Date() >= unlockDate
    }
    
    var daysUntilUnlock: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: unlockDate).day ?? 0
        return max(0, days)
    }
    
    var formattedUnlockDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: unlockDate)
    }
}

// MARK: - Time Capsule Service
actor TimeCapsuleService {
    static let shared = TimeCapsuleService()
    
    private let storageKey = "time_capsules"
    private var capsules: [TimeCapsule] = []
    
    private init() {
        Task { await loadData() }
    }
    
    // MARK: - CRUD Operations
    
    /// 创建时间胶囊
    func createCapsule(for file: ManagedFile, unlockDate: Date, note: String = "") async -> TimeCapsule {
        let capsule = TimeCapsule(
            fileId: file.id,
            fileName: file.displayName,
            filePath: file.newPath,
            unlockDate: unlockDate,
            note: note
        )
        capsules.append(capsule)
        await saveData()
        Logger.info("⏳ 创建时间胶囊: \(file.displayName) 解锁日期: \(capsule.formattedUnlockDate)")
        return capsule
    }
    
    /// 获取所有时间胶囊
    func getAllCapsules() -> [TimeCapsule] {
        capsules.sorted { $0.unlockDate < $1.unlockDate }
    }
    
    /// 获取已解锁但未打开的胶囊
    func getUnlockedCapsules() -> [TimeCapsule] {
        capsules.filter { $0.isUnlocked && !$0.isOpened }
    }
    
    /// 获取待解锁的胶囊
    func getPendingCapsules() -> [TimeCapsule] {
        capsules.filter { !$0.isUnlocked }
    }
    
    /// 标记胶囊已打开
    func markOpened(_ capsuleId: UUID) async {
        if let index = capsules.firstIndex(where: { $0.id == capsuleId }) {
            capsules[index].isOpened = true
            await saveData()
        }
    }
    
    /// 删除胶囊
    func deleteCapsule(_ capsuleId: UUID) async {
        capsules.removeAll { $0.id == capsuleId }
        await saveData()
    }
    
    /// 检查文件是否有时间胶囊
    func getCapsule(for fileId: UUID) -> TimeCapsule? {
        capsules.first { $0.fileId == fileId && !$0.isOpened }
    }
    
    /// 获取今日解锁的胶囊数量
    func getTodayUnlockedCount() -> Int {
        getUnlockedCapsules().count
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TimeCapsule].self, from: data) else {
            return
        }
        capsules = decoded
    }
    
    private func saveData() async {
        guard let encoded = try? JSONEncoder().encode(capsules) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}

// MARK: - Time Capsule View
struct TimeCapsuleView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var capsules: [TimeCapsule] = []
    @State private var showingCreateSheet = false
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⏳ 时间胶囊")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("设定未来日期解锁重要文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if capsules.isEmpty {
                emptyCapsuleView
            } else {
                capsuleList
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await loadCapsules()
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateCapsuleSheet { capsule in
                capsules.insert(capsule, at: 0)
            }
        }
    }
    
    private var emptyCapsuleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("没有时间胶囊")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("创建一个时间胶囊，在未来的某天打开")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                showingCreateSheet = true
            } label: {
                Label("创建时间胶囊", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var capsuleList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // 已解锁区域
                let unlocked = capsules.filter { $0.isUnlocked && !$0.isOpened }
                if !unlocked.isEmpty {
                    Section {
                        ForEach(unlocked) { capsule in
                            CapsuleCard(capsule: capsule, onOpen: openCapsule, onDelete: deleteCapsule)
                        }
                    } header: {
                        HStack {
                            Label("已解锁", systemImage: "lock.open.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Spacer()
                        }
                    }
                }
                
                // 待解锁区域
                let pending = capsules.filter { !$0.isUnlocked }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { capsule in
                            CapsuleCard(capsule: capsule, onOpen: openCapsule, onDelete: deleteCapsule)
                        }
                    } header: {
                        HStack {
                            Label("待解锁", systemImage: "lock.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func loadCapsules() async {
        let all = await TimeCapsuleService.shared.getAllCapsules()
        await MainActor.run {
            capsules = all
            isLoading = false
        }
    }
    
    private func openCapsule(_ capsule: TimeCapsule) {
        Task {
            await TimeCapsuleService.shared.markOpened(capsule.id)
            // 打开文件
            NSWorkspace.shared.open(URL(fileURLWithPath: capsule.filePath))
            // 刷新列表
            await loadCapsules()
        }
    }
    
    private func deleteCapsule(_ capsule: TimeCapsule) {
        Task {
            await TimeCapsuleService.shared.deleteCapsule(capsule.id)
            await loadCapsules()
        }
    }
}

// MARK: - Capsule Card
struct CapsuleCard: View {
    let capsule: TimeCapsule
    var onOpen: (TimeCapsule) -> Void
    var onDelete: (TimeCapsule) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(capsule.isUnlocked ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: capsule.isUnlocked ? "lock.open.fill" : "hourglass")
                    .font(.title2)
                    .foregroundStyle(capsule.isUnlocked ? .green : .orange)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(capsule.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                if capsule.isUnlocked {
                    Text("🎉 已解锁！")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("\(capsule.daysUntilUnlock) 天后解锁 (\(capsule.formattedUnlockDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !capsule.note.isEmpty {
                    Text(capsule.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 操作按钮
            if capsule.isUnlocked {
                Button("打开") {
                    onOpen(capsule)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            
            Button {
                onDelete(capsule)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(capsule.isUnlocked ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                )
        )
    }
}

// MARK: - Create Capsule Sheet
struct CreateCapsuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFile: ManagedFile?
    @State private var unlockDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    @State private var note = ""
    @State private var searchText = ""
    @State private var files: [ManagedFile] = []
    @State private var isCreating = false
    
    var onCreated: (TimeCapsule) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("创建时间胶囊")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                Section("选择文件") {
                    TextField("搜索文件...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    
                    if let file = selectedFile {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                            Text(file.displayName)
                                .lineLimit(1)
                            Spacer()
                            Button("更换") { selectedFile = nil }
                                .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(filteredFiles) { file in
                                    Button {
                                        selectedFile = file
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc")
                                            Text(file.displayName)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(8)
                                        .background(Color.primary.opacity(0.03))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 150)
                    }
                }
                
                Section("解锁日期") {
                    DatePicker("解锁日期", selection: $unlockDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    
                    Text("文件将在 \(daysUntil) 天后解锁")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("备注 (可选)") {
                    TextField("给未来的自己留言...", text: $note)
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Spacer()
                Button("创建") {
                    createCapsule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFile == nil || isCreating)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .task {
            files = await DatabaseManager.shared.getAllFiles()
        }
    }
    
    private var filteredFiles: [ManagedFile] {
        if searchText.isEmpty {
            return Array(files.prefix(20))
        }
        return files.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }.prefix(20).map { $0 }
    }
    
    private var daysUntil: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: unlockDate).day ?? 0
        return max(0, days)
    }
    
    private func createCapsule() {
        guard let file = selectedFile else { return }
        isCreating = true
        
        Task {
            let capsule = await TimeCapsuleService.shared.createCapsule(for: file, unlockDate: unlockDate, note: note)
            await MainActor.run {
                onCreated(capsule)
                dismiss()
            }
        }
    }
}

#Preview {
    TimeCapsuleView()
}
