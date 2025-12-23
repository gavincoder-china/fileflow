# FileFlow - 智能文件整理系统

> 一款基于 PARA 方法论的 macOS 原生智能文件整理应用

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## ✨ 特性

- **🎯 零摩擦整理** - 拖拽 + 输入几个关键词，即可完成文件的标签化、命名和归档
- **📁 PARA 方法论** - 基于 Projects/Areas/Resources/Archives 的文件组织结构
- **🏷️ 智能标签** - 自动补全、Finder 原生标签同步
- **🤖 AI 分析** - 支持 OpenAI API 和本地 Ollama，自动生成摘要和标签建议
- **🔍 全文搜索** - 按文件名、标签、备注快速检索
- **📊 批量整理** - 一键扫描文件夹，批量处理历史文件

## 🎨 设计理念

FileFlow 采用类似 **Obsidian Vault** 的设计：

1. **文件系统为主** - 真实文件只存一份，移动而非复制
2. **数据库为辅** - SQLite 仅作为索引和元数据存储
3. **用户选择根目录** - 所有文件存储在用户指定的目录中
4. **数据可移植** - 即使卸载应用，文件仍然存在且组织有序

## 📦 安装

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- 约 50MB 磁盘空间

### 使用 Xcode 构建

1. 克隆仓库：
```bash
git clone https://github.com/yourname/FileFlow.git
cd FileFlow
```

2. 使用 Xcode 打开项目：
```bash
open FileFlow.xcodeproj
```

3. 选择 `My Mac` 作为运行目标，点击 Run (⌘R)

### 使用 Swift Package Manager

```bash
cd FileFlow
swift build -c release
```

## 🚀 快速开始

### 1. 选择根目录

首次启动时，FileFlow 会引导你选择一个文件夹作为根目录。所有整理的文件都将保存在这个目录中。

```
/Your/Chosen/Path/
├── 1_Projects/          # 当前项目
├── 2_Areas/             # 持续关注的领域
├── 3_Resources/         # 参考资料
├── 4_Archives/          # 归档内容
└── .fileflow/           # 数据库和配置
```

### 2. 拖拽文件

将任意文件拖拽到 FileFlow 主窗口：

1. 系统会自动分析文件类型
2. AI 会建议标签和分类（如已配置）
3. 输入或选择标签
4. 选择 PARA 分类和子目录
5. 点击「保存并归档」

### 3. 搜索和浏览

- 使用侧边栏按分类浏览
- 点击标签快速筛选
- 使用搜索栏全文检索

## ⚙️ 配置 AI

### OpenAI API

1. 打开设置 (⌘,)
2. 选择「AI」标签页
3. 选择提供商为「OpenAI」
4. 输入你的 API Key

### 本地 Ollama

1. 安装 [Ollama](https://ollama.ai)
2. 拉取模型：`ollama pull llama3.2`
3. 在 FileFlow 设置中选择「本地 Ollama」
4. 确认服务地址（默认 http://localhost:11434）

## 📂 文件命名规则

FileFlow 使用以下格式自动生成文件名：

```
YYYY-MM-DD_[分类]_[简述]_[标签].ext

示例:
2024-12-22_Resources_机器学习入门指南_#AI#教程.pdf
```

## ⌨️ 快捷键

| 快捷键 | 功能 |
|--------|------|
| ⌘O | 导入文件 |
| ⌘⇧B | 批量整理 |
| ⌘⇧F | 打开根目录 |
| ⌘, | 设置 |

## 🔧 技术栈

- **语言**: Swift 5.9
- **UI 框架**: SwiftUI
- **平台**: macOS 14.0+
- **数据库**: SQLite3
- **AI**: OpenAI API / Ollama

## 📄 License

MIT License © 2024 FileFlow
