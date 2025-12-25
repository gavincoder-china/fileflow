//
//  ProjectArchiveWizard.swift
//  FileFlow
//
//  项目归档向导
//  提供完整的项目归档体验，支持选择归档策略
//

import SwiftUI

/// 项目归档向导视图
struct ProjectArchiveWizard: View {
    let subcategory: String
    let category: PARACategory
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @State private var files: [ManagedFile] = []
    @State private var isLoading = true
    @State private var selectedStrategy: ProjectArchiveStrategy = .archiveAll
    @State private var selectedReason: TransitionReason = .projectCompleted
    @State private var notes: String = ""
    @State private var isArchiving = false
    
    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.fileSize }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if isLoading {
                loadingView
            } else if files.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        statsCard
                        strategySection
                        reasonSection
                        notesSection
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Footer Actions
            actionBar
        }
        .frame(width: 500, height: 520)
        .task {
            await loadFiles()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                    Text("项目归档向导")
                        .font(.title2.bold())
                }
                Text("将「\(subcategory)」归档到 Archives")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载项目文件...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("此项目没有文件")
                .font(.headline)
            Text("无需归档")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Stats Card
    private var statsCard: some View {
        HStack(spacing: 24) {
            statItem(icon: "doc.fill", value: "\(files.count)", label: "个文件")
            Divider().frame(height: 40)
            statItem(icon: "internaldrive.fill", value: formatFileSize(totalSize), label: "总大小")
            Divider().frame(height: 40)
            statItem(icon: "folder.fill", value: category.displayName, label: "来源分类")
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Strategy Section
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("归档策略")
                .font(.headline)
            
            VStack(spacing: 8) {
                strategyOption(
                    strategy: .archiveAll,
                    title: "整体归档",
                    description: "所有文件移至 Archives/\(subcategory)",
                    icon: "archivebox"
                )
                
                strategyOption(
                    strategy: .smartArchive,
                    title: "智能归档",
                    description: "提取可复用资源到 Resources，其余归档",
                    icon: "wand.and.stars"
                )
                
                strategyOption(
                    strategy: .markComplete,
                    title: "仅标记完成",
                    description: "更新状态为已归档，文件位置不变",
                    icon: "checkmark.circle"
                )
            }
        }
    }
    
    private func strategyOption(strategy: ProjectArchiveStrategy, title: String, description: String, icon: String) -> some View {
        Button {
            selectedStrategy = strategy
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedStrategy == strategy ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedStrategy == strategy ? .blue : .secondary)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selectedStrategy == strategy ? .blue : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedStrategy == strategy ? Color.blue.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedStrategy == strategy ? Color.blue.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Reason Section
    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("归档原因")
                .font(.headline)
            
            Picker("原因", selection: $selectedReason) {
                ForEach(TransitionReason.projectReasons, id: \.self) { reason in
                    Label(reason.displayName, systemImage: reason.icon)
                        .tag(reason)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注 (可选)")
                .font(.headline)
            
            TextField("添加归档说明...", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }
    
    // MARK: - Action Bar
    private var actionBar: some View {
        HStack {
            Button("取消") {
                onCancel()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button {
                Task { await performArchive() }
            } label: {
                if isArchiving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Label("执行归档", systemImage: "archivebox.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(files.isEmpty || isArchiving)
        }
        .padding()
    }
    
    // MARK: - Actions
    private func loadFiles() async {
        files = await DatabaseManager.shared.getFiles(category: category, subcategory: subcategory)
        isLoading = false
    }
    
    private func performArchive() async {
        isArchiving = true
        
        _ = await LifecycleService.shared.archiveProject(
            subcategory: subcategory,
            strategy: selectedStrategy,
            reason: selectedReason,
            notes: notes.isEmpty ? nil : notes
        )
        
        isArchiving = false
        onComplete()
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - TransitionReason Extension
extension TransitionReason {
    /// Project-related reasons for archive wizard picker
    static var projectReasons: [TransitionReason] {
        [.projectCompleted, .projectCanceled, .projectPaused, .projectEvolved]
    }
}

// MARK: - Preview
#Preview {
    ProjectArchiveWizard(
        subcategory: "2024年度报告",
        category: .projects,
        onComplete: {},
        onCancel: {}
    )
}
