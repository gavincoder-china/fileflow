#!/bin/bash

# FileFlow 快速启动脚本
# 由于这是一个完整的 macOS 应用，需要使用 Xcode 编译

echo "🚀 正在启动 FileFlow..."
echo ""
echo "由于这是一个 macOS 原生应用，需要使用 Xcode 编译。"
echo ""
echo "方式 1: 使用 xcodegen (推荐)"
echo "  brew install xcodegen"
echo "  xcodegen generate"
echo "  xed ."
echo ""
echo "方式 2: 手动在 Xcode 中创建项目"
echo "  1. 打开 Xcode"
echo "  2. 创建新的 macOS App 项目，命名为 FileFlow"
echo "  3. 将 FileFlow/ 目录下的所有 .swift 文件拖入项目"
echo "  4. 将 Assets.xcassets 拖入项目"
echo "  5. 点击运行 (⌘R)"
echo ""

# 尝试安装 xcodegen
read -p "是否现在安装 xcodegen 并自动生成项目? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "正在安装 xcodegen..."
    brew install xcodegen
    
    echo "正在生成 Xcode 项目..."
    xcodegen generate
    
    echo "正在打开 Xcode..."
    open FileFlow.xcodeproj
fi
