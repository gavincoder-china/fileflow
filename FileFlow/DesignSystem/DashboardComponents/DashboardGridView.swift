//
//  DashboardGridView.swift
//  FileFlow
//
//  Created by 刑天 on 2025/12/27.
//

import SwiftUI

/// 仪表盘网格布局视图
/// 自动排列和调整组件大小
public struct DashboardGridView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var draggedComponent: (any DashboardComponent, CGPoint)?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: DesignTokens.spacing.md),
        count: 6
    )

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            DashboardToolbar(
                onAddComponent: { type in
                    viewModel.addComponent(type: type)
                },
                onToggleEditMode: {
                    viewModel.toggleEditMode()
                },
                onRefreshAll: {
                    viewModel.refreshAllComponents()
                },
                onClearLayout: {
                    viewModel.clearLayout()
                }
            )
            .padding()
            .background(.ultraThinMaterial)

            // 组件网格
            ScrollView {
                LazyVGrid(columns: columns, spacing: DesignTokens.spacing.md) {
                    ForEach(viewModel.components, id: \.id) { component in
                        ComponentContainer(component: component)
                        {
                            component.view
                        }
                        .opacity(viewModel.isEditMode ? 0.8 : 1.0)
                        .scaleEffect(viewModel.isEditMode && viewModel.selectedComponent?.id == component.id ? 0.95 : 1.0)
                        .animation(DesignTokens.animation.fast, value: component.id)
                        .onTapGesture {
                            if viewModel.isEditMode {
                                viewModel.selectComponent(component)
                            } else {
                                handleComponentTap(component)
                            }
                        }
                        .onLongPressGesture {
                            viewModel.selectComponent(component)
                        }
                        .draggable(component) {
                            // 拖拽占位符
                            Rectangle()
                                .fill(.clear)
                                .frame(width: 100, height: 100)
                        }
                        .dropDestination(for: any DashboardComponent.self) { items, location in
                            handleDrop(component: component, items: items, location: location)
                            return true
                        } isTargeted: { isTargeted in
                            if isTargeted {
                                viewModel.setDropTarget(component.id)
                            } else {
                                viewModel.clearDropTarget()
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(DesignTokens.auroraGradient)
        .onAppear {
            viewModel.loadInitialComponents()
        }
    }

    private func handleComponentTap(_ component: any DashboardComponent) {
        // 处理组件点击事件
        print("Tapped component: \(component.title)")
    }

    private func handleDrop(component: any DashboardComponent, items: [any DashboardComponent], location: CGPoint) {
        // 处理组件拖拽放置
        if let dragged = draggedComponent?.0 {
            viewModel.moveComponent(dragged, to: component.id)
        }
    }
}

/// 仪表盘视图模型
@MainActor
public class DashboardViewModel: ObservableObject {
    @Published public var components: [any DashboardComponent] = []
    @Published public var isEditMode: Bool = false
    @Published public var selectedComponent: (any DashboardComponent)?
    @Published public var dropTargetComponentId: UUID?
    @Published public var isLoading: Bool = false

    private let componentFactory = ComponentFactory.shared

    public init() {}

    /// 加载初始组件
    public func loadInitialComponents() {
        let initialTypes: [ComponentType] = [
            .statsCard,
            .activityChart,
            .recentFiles,
            .aiSuggestions,
            .workflowStatus
        ]

        components = initialTypes.compactMap { type in
            componentFactory.createComponent(type: type)
        }
    }

    /// 添加组件
    public func addComponent(type: ComponentType) {
        let component = componentFactory.createComponent(type: type)
        components.append(component)
    }

    /// 移除组件
    public func removeComponent(_ component: any DashboardComponent) {
        components.removeAll { $0.id == component.id }
    }

    /// 移动组件
    public func moveComponent(_ component: any DashboardComponent, to targetId: UUID) {
        guard let fromIndex = components.firstIndex(where: { $0.id == component.id }),
              let toIndex = components.firstIndex(where: { $0.id == targetId }) else {
            return
        }

        var component = components[fromIndex]
        components.remove(at: fromIndex)
        components.insert(component, at: toIndex)
    }

    /// 切换编辑模式
    public func toggleEditMode() {
        isEditMode.toggle()
        if !isEditMode {
            selectedComponent = nil
        }
    }

    /// 选择组件
    public func selectComponent(_ component: any DashboardComponent) {
        selectedComponent = component
    }

    /// 设置拖拽目标
    public func setDropTarget(_ componentId: UUID) {
        dropTargetComponentId = componentId
    }

    /// 清除拖拽目标
    public func clearDropTarget() {
        dropTargetComponentId = nil
    }

    /// 刷新所有组件
    public func refreshAllComponents() {
        Task {
            isLoading = true
            defer { isLoading = false }

            for index in components.indices {
                var component = components[index]
                await component.refresh()
                components[index] = component
            }
        }
    }

    /// 清除布局
    public func clearLayout() {
        components.removeAll()
    }

    /// 保存布局
    public func saveLayout() {
        let layout = components.map { component in
            ComponentLayoutItem(id: component.id, type: component.size)
        }

        // 保存到 UserDefaults 或文件
        UserDefaults.standard.set(try? JSONEncoder().encode(layout), forKey: "DashboardLayout")
    }

    /// 加载布局
    public func loadLayout() {
        guard let data = UserDefaults.standard.data(forKey: "DashboardLayout"),
              let layout = try? JSONDecoder().decode([ComponentLayoutItem].self, from: data) else {
            return
        }

        // 根据布局重建组件
        components = layout.compactMap { item in
            componentFactory.createComponent(type: item.type.defaultSize as! ComponentType) as? any DashboardComponent
        }
    }
}

/// 布局项
struct ComponentLayoutItem: Codable {
    let id: UUID
    let type: ComponentType
}

/// 仪表盘工具栏
struct DashboardToolbar: View {
    let onAddComponent: (ComponentType) -> Void
    let onToggleEditMode: () -> Void
    let onRefreshAll: () -> Void
    let onClearLayout: () -> Void

    @State private var showComponentPicker = false

    var body: some View {
        HStack {
            // 标题
            Text("仪表盘")
                .font(DesignTokens.fontScale.xxl)
                .fontWeight(.bold)

            Spacer()

            // 操作按钮
            HStack(spacing: DesignTokens.spacing.sm) {
                Button(action: { showComponentPicker = true }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(GlassButtonStyle())
                .help("添加组件")

                Button(action: onRefreshAll) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(GlassButtonStyle())
                .help("刷新所有")

                Divider()
                    .frame(height: 20)

                Button(action: onToggleEditMode) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(GlassButtonStyle())
                .help("编辑模式")

                Button(action: onClearLayout) {
                    Image(systemName: "trash")
                }
                .buttonStyle(GlassButtonStyle())
                .foregroundColor(DesignTokens.error)
                .help("清除布局")
            }
        }
        .sheet(isPresented: $showComponentPicker) {
            ComponentPickerView { type in
                onAddComponent(type)
                showComponentPicker = false
            }
        }
    }
}

/// 组件选择器视图
struct ComponentPickerView: View {
    let onSelectComponent: (ComponentType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: DesignTokens.spacing.md) {
                    ForEach(ComponentType.allCases, id: \.self) { type in
                        ComponentPickerCard(type: type) {
                            onSelectComponent(type)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("选择组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 组件选择卡片
struct ComponentPickerCard: View {
    let type: ComponentType
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.spacing.sm) {
            Image(systemName: type.icon)
                .font(.system(size: 32))
                .foregroundColor(DesignTokens.primary)

            Text(type.rawValue)
                .font(DesignTokens.fontScale.sm)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("点击添加")
                .font(DesignTokens.fontScale.xs)
                .foregroundColor(DesignTokens.textTertiary)
        }
        .padding(DesignTokens.spacing.md)
        .glass()
        .onTapGesture {
            onSelect()
        }
        .hoverEffect()
    }
}

// MARK: - 预览

struct DashboardGridView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardGridView()
            .frame(width: 1200, height: 800)
    }
}
