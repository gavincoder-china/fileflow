//
//  IncrementalProcessingPipeline.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import Foundation
import SwiftUI
import Combine

/// 增量处理管线
/// 使用 Swift Concurrency 和 OperationQueue 管理后台任务
@MainActor
public class IncrementalProcessingPipeline: ObservableObject {
    // MARK: - Published Properties

    @Published public var isProcessing: Bool = false
    @Published public var currentTask: String = ""
    @Published public var progress: Double = 0.0
    @Published public var queue: [ProcessingTask] = []
    @Published public var completedTasks: [ProcessingTask] = []

    // MARK: - Private Properties

    private let operationQueue = OperationQueue()
    private let taskScheduler = TaskScheduler()
    private var activeOperations: [UUID: AsyncOperation] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        operationQueue.maxConcurrentOperationCount = 4
        operationQueue.underlyingQueue = DispatchQueue(
            label: "VectorProcessingQueue",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    // MARK: - Public Methods

    /// 排队任务
    public func enqueueTask(_ task: ProcessingTask) {
        queue.append(task)
        taskScheduler.schedule(&queue)
        processQueue()
    }

    /// 批量排队任务
    public func enqueueTasks(_ tasks: [ProcessingTask]) {
        queue.append(contentsOf: tasks)
        taskScheduler.schedule(&queue)
        processQueue()
    }

    /// 暂停处理
    public func pause() {
        operationQueue.isSuspended = true
        currentTask = "已暂停"
    }

    /// 恢复处理
    public func resume() {
        operationQueue.isSuspended = false
        if !queue.isEmpty {
            currentTask = "恢复处理"
            processQueue()
        }
    }

    /// 取消所有任务
    public func cancelAll() {
        operationQueue.cancelAllOperations()
        activeOperations.removeAll()
        queue.removeAll()
        isProcessing = false
        currentTask = "已取消"
        progress = 0.0
    }

    /// 取消特定任务
    public func cancelTask(id: UUID) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: index)
        }

        if let operation = activeOperations[id] {
            operation.cancel()
            activeOperations.removeValue(forKey: id)
        }
    }

    /// 获取任务统计
    public func getStats() -> ProcessingStats {
        return ProcessingStats(
            totalQueued: queue.count,
            totalCompleted: completedTasks.count,
            totalFailed: completedTasks.filter { $0.status == .failed }.count,
            isProcessing: isProcessing,
            activeTasks: activeOperations.count
        )
    }

    // MARK: - Private Methods

    private func processQueue() {
        guard !queue.isEmpty && !operationQueue.isSuspended else { return }

        let task = queue.removeFirst()
        isProcessing = true
        currentTask = task.description
        progress = 0.0

        let operation = AsyncOperation(task: task) { [weak self] progress in
            await MainActor.run {
                self?.progress = progress
            }
        }

        operation.completionBlock = { [weak self] in
            Task {
                await self?.handleOperationCompletion(operation)
            }
        }

        activeOperations[task.id] = operation
        operationQueue.addOperation(operation)
    }

    private func handleOperationCompletion(_ operation: AsyncOperation) async {
        let task = operation.task

        if operation.isCancelled {
            currentTask = "任务已取消"
        } else if let error = operation.error {
            print("Task failed: \(error)")
            currentTask = "任务失败: \(error.localizedDescription)"
            await MainActor.run {
                task.status = .failed
                completedTasks.append(task)
            }
        } else {
            await MainActor.run {
                task.status = .completed
                completedTasks.append(task)
                currentTask = "任务完成"
                progress = 1.0
            }
        }

        activeOperations.removeValue(forKey: task.id)

        // 处理下一个任务
        if !queue.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 短暂延迟
            await MainActor.run {
                processQueue()
            }
        } else {
            await MainActor.run {
                isProcessing = false
                currentTask = "所有任务已完成"
                progress = 1.0
            }
        }
    }
}

/// 异步操作实现
class AsyncOperation: Operation {
    let task: ProcessingTask
    let progressHandler: (Double) -> Void

    private(set) var error: Error?
    private let executionBlock: @MainActor () async throws -> Void

    init(task: ProcessingTask, progressHandler: @escaping (Double) -> Void, executionBlock: @MainActor @escaping () async throws -> Void) {
        self.task = task
        self.progressHandler = progressHandler
        self.executionBlock = executionBlock
        super.init()
    }

    override func main() {
        if isCancelled { return }

        Task {
            do {
                try await executionBlock()
            } catch {
                self.error = error
            }
        }
    }

    override var isAsynchronous: Bool {
        return true
    }

    override var isExecuting: Bool {
        return false
    }

    override var isFinished: Bool {
        return false
    }
}

/// 处理任务模型
public struct ProcessingTask: Identifiable, Equatable {
    public let id: UUID
    public var type: TaskType
    public var description: String
    public var priority: TaskPriority
    public var files: [URL]?
    public var metadata: [String: Any]?
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var status: TaskStatus = .pending

    public init(
        id: UUID = UUID(),
        type: TaskType,
        description: String,
        priority: TaskPriority = .normal,
        files: [URL]? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.priority = priority
        self.files = files
        self.metadata = metadata
        self.createdAt = Date()
    }

    public static func == (lhs: ProcessingTask, rhs: ProcessingTask) -> Bool {
        return lhs.id == rhs.id
    }

    public enum TaskType {
        case embeddingGeneration
        case indexUpdate
        case lifecycleRefresh
        case fileAnalysis
        case tagExtraction
        case summaryGeneration
        case workflowExecution
        case searchIndexing
        case cleanup
        case custom(String)
    }

    public enum TaskPriority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3

        public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    public enum TaskStatus {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }
}

/// 任务调度器
class TaskScheduler {
    /// 按优先级调度任务
    func schedule(_ queue: inout [ProcessingTask]) {
        queue.sort { task1, task2 in
            if task1.priority == task2.priority {
                return task1.createdAt < task2.createdAt
            }
            return task1.priority > task2.priority
        }
    }

    /// 估算任务执行时间
    func estimateExecutionTime(for task: ProcessingTask) -> TimeInterval {
        switch task.type {
        case .embeddingGeneration:
            // 假设每个文件需要 2 秒
            return Double(task.files?.count ?? 1) * 2.0
        case .indexUpdate:
            return 5.0
        case .lifecycleRefresh:
            return 10.0
        case .fileAnalysis:
            return Double(task.files?.count ?? 1) * 1.0
        default:
            return 3.0
        }
    }
}

/// 处理统计信息
public struct ProcessingStats {
    public let totalQueued: Int
    public let totalCompleted: Int
    public let totalFailed: Int
    public let isProcessing: Bool
    public let activeTasks: Int

    public var successRate: Double {
        let total = totalCompleted + totalFailed
        return total > 0 ? Double(totalCompleted) / Double(total) : 1.0
    }

    public init(
        totalQueued: Int,
        totalCompleted: Int,
        totalFailed: Int,
        isProcessing: Bool,
        activeTasks: Int
    ) {
        self.totalQueued = totalQueued
        self.totalCompleted = totalCompleted
        self.totalFailed = totalFailed
        self.isProcessing = isProcessing
        self.activeTasks = activeTasks
    }
}

// MARK: - 便捷扩展

extension ProcessingTask {
    /// 创建向量生成任务
    public static func embeddingGeneration(for files: [URL]) -> ProcessingTask {
        return ProcessingTask(
            type: .embeddingGeneration,
            description: "生成向量嵌入 (\(files.count) 个文件)",
            files: files,
            priority: .high
        )
    }

    /// 创建索引更新任务
    public static func indexUpdate(fileCount: Int) -> ProcessingTask {
        return ProcessingTask(
            type: .indexUpdate,
            description: "更新搜索索引 (\(fileCount) 个文档)",
            priority: .normal
        )
    }

    /// 创建生命周期刷新任务
    public static func lifecycleRefresh(fileCount: Int) -> ProcessingTask {
        return ProcessingTask(
            type: .lifecycleRefresh,
            description: "刷新文件生命周期状态 (\(fileCount) 个文件)",
            priority: .low
        )
    }

    /// 创建文件分析任务
    public static func fileAnalysis(for files: [URL]) -> ProcessingTask {
        return ProcessingTask(
            type: .fileAnalysis,
            description: "分析文件内容 (\(files.count) 个文件)",
            files: files,
            priority: .normal
        )
    }
}

// MARK: - 使用示例

extension IncrementalProcessingPipeline {
    /// 示例：添加向量生成任务
    public func addEmbeddingTasks(for files: [URL]) {
        let task = ProcessingTask.embeddingGeneration(for: files)
        enqueueTask(task)
    }

    /// 示例：添加多个任务
    public func addBatchTasks(files: [URL], includeSummaries: Bool = true, includeTags: Bool = true) {
        var tasks: [ProcessingTask] = []

        if includeSummaries {
            tasks.append(ProcessingTask(
                type: .summaryGeneration,
                description: "生成摘要 (\(files.count) 个文件)",
                files: files
            ))
        }

        if includeTags {
            tasks.append(ProcessingTask(
                type: .tagExtraction,
                description: "提取标签 (\(files.count) 个文件)",
                files: files
            ))
        }

        enqueueTasks(tasks)
    }
}
