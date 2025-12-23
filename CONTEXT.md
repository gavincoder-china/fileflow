# FileFlow 项目上下文文档

> 本文档旨在帮助 AI 助手（如 Codex / Claude）快速理解项目架构，无需阅读完整历史。

---

## 📦 项目概览

**FileFlow** 是一款 macOS 本地文件智能整理工具，采用 **PARA 方法论**（Projects / Areas / Resources / Archives）对文件进行分类管理，并集成 AI 自动分析、标签系统和知识图谱可视化。

- **平台**: macOS 14.0+ (SwiftUI + AppKit)
- **语言**: Swift 5.9+
- **架构**: MVVM + 轻量级 Manager 层
- **数据存储**: SQLite3 (原生 C API)
- **AI 集成**: OpenAI / 本地 Ollama / 禁用

---

## 🏗️ 目录结构

```
FileFlow/
├── FileFlowApp.swift       # App 入口 + AppState 全局状态
├── Managers/
│   ├── DatabaseManager.swift   # SQLite 数据库操作
│   └── FileFlowManager.swift   # 文件系统操作 + 业务逻辑
├── Services/
│   └── AIService.swift         # AI 分析服务抽象层
├── Models/
│   └── Models.swift            # 数据模型 (ManagedFile, Tag, Subcategory 等)
├── ViewModels/
│   └── FileOrganizeViewModel.swift  # 单文件整理视图模型
└── Views/
    ├── ContentView.swift           # 主界面 (NavigationSplitView)
    ├── FileOrganizeSheet.swift     # 单文件整理弹窗
    ├── FileStackOrganizerView.swift # 多文件堆叠整理界面 ⭐
    ├── BatchOrganizeView.swift     # 文件夹批量扫描整理
    ├── CategoryView.swift          # PARA 分类详情页
    ├── TagManagerView.swift        # 标签管理页
    ├── TagGraphView.swift          # 知识图谱可视化
    ├── SettingsView.swift          # 设置页面
    ├── OnboardingView.swift        # 首次启动引导
    └── DesignSystem.swift          # 设计系统 (Glass 风格等)
```

---

## 🔧 核心模块职责

### Managers

| 文件 | 职责 |
|------|------|
| `DatabaseManager` | SQLite CRUD、表迁移、文件-标签关联 |
| `FileFlowManager` | 文件扫描、移动、重命名、目录创建 |

### Services

| 文件 | 职责 |
|------|------|
| `AIService` | 多 Provider 抽象 (OpenAI/Ollama)、文件内容分析、标签建议 |

### ViewModels

| 文件 | 职责 |
|------|------|
| `FileOrganizeViewModel` | 单文件整理状态管理、AI 分析触发、保存逻辑 |

### Views (关键)

| 文件 | 职责 |
|------|------|
| `ContentView` | 主框架: 侧边栏 + 详情区 + 文件拖放 |
| `FileStackOrganizerView` | **多文件拖入后的卡片堆叠整理界面**，支持并行 AI 分析 |
| `TagGraphView` | 基于 Canvas 的标签-文件关系力导向图 |

---

## 📐 数据模型

```swift
struct ManagedFile {
    id: UUID
    originalName / newName: String
    originalPath / newPath: String
    category: PARACategory      // .projects / .areas / .resources / .archives
    subcategory: String?
    tags: [Tag]
    summary: String?            // AI 生成摘要
    fileSize / fileType: ...
}

struct Tag {
    id: UUID
    name: String
    color: String               // Hex
    isFavorite: Bool
    usageCount: Int
}

enum PARACategory: String, CaseIterable {
    case projects, areas, resources, archives
}
```

---

## 🎨 设计系统

- **Glass Modifier**: `.glass(cornerRadius:material:)` 实现毛玻璃卡片效果
- **Aurora Background**: 动态渐变背景
- **GlassButtonStyle**: 统一按钮样式
- **动画**: 使用 `.spring()` 和 `.symbolEffect()` 增强交互感

---

## 🔗 关键流程

### 文件拖入流程
1. `ContentView.handleDrop` 接收 `NSItemProvider`
2. 解析 URL → 加入 `pendingFileURLs` 队列
3. 触发 `FileStackOrganizerView` Sheet
4. `BatchSessionManager` 并行启动所有文件的 AI 分析
5. 用户逐张确认或使用"AI 一键处理"

### 标签重命名流程
1. `TagManagerView` 点击重命名
2. `DatabaseManager.renameTag(tag:newName:)` 更新数据库
3. 遍历关联文件，调用 `FileFlowManager.renameFileTag` 同步文件名

---

## ⚙️ 配置与存储

- **UserDefaults Keys**:
  - `rootDirectoryBookmark`: 根目录安全书签
  - `aiProvider`: AI 服务商 (`openai` / `ollama` / `disabled`)
  - `openaiApiKey` / `ollamaHost`: API 配置

- **数据库路径**: `{RootDirectory}/.fileflow/fileflow.db`

---

## 🚀 开发注意事项

1. **沙盒限制**: 使用 Security-Scoped Bookmark 持久化文件访问权限
2. **SQLite 线程安全**: 当前使用单例，需注意并发写入
3. **SwiftUI 状态**: `@StateObject` 用于创建，`@ObservedObject` 用于传递
4. **新文件添加**: 手动添加到 Xcode Target (我无法自动修改 xcodeproj)

---

## 📝 常用命令

```bash
# 编译检查
xcodebuild -scheme FileFlow -configuration Debug build

# 清理
xcodebuild clean -scheme FileFlow
```

---

*最后更新: 2024-12-23*
