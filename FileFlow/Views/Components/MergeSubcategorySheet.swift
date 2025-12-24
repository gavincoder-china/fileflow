//
//  MergeSubcategorySheet.swift
//  FileFlow
//
//  Created for Subfolder UX Enhancement
//

import SwiftUI

struct MergeSubcategorySheet: View {
    let category: PARACategory
    let sourceSubcategory: String
    @Binding var isPresented: Bool
    let onMerge: (String) -> Void
    
    @State private var selectedTarget: String = ""
    @State private var availableTargets: [String] = []
    
    var body: some View {
        VStack(spacing: 24) {
            Text("合并文件夹")
                .font(.headline)
            
            // Visual Diagram
            HStack(spacing: 20) {
                // Source
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(category.color)
                    Text(sourceSubcategory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80)
                        .lineLimit(1)
                }
                
                // Arrow
                VStack(spacing: 4) {
                    Text("移动到")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                
                // Target
                VStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(category.color)
                    
                    if selectedTarget.isEmpty {
                        Text("选择目标")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(selectedTarget)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(width: 80)
                            .lineLimit(1)
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Target Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("选择目标文件夹")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Menu {
                    ForEach(availableTargets, id: \.self) { target in
                        Button {
                            withAnimation {
                                selectedTarget = target
                            }
                        } label: {
                            Text(target)
                            if selectedTarget == target {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack {
                        if selectedTarget.isEmpty {
                            Text("请选择...")
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(selectedTarget)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
            }
            .frame(width: 280)
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 16) {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                Button {
                    onMerge(selectedTarget)
                    isPresented = false
                } label: {
                    Text("确认合并")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTarget.isEmpty ? Color.gray.opacity(0.3) : category.color)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(selectedTarget.isEmpty)
            }
            .frame(width: 280)
        }
        .padding(32)
        .frame(width: 400, height: 450)
        .glass()
        .task {
            // Load available targets excluding source
            let allSubs = FileFlowManager.shared.getSubcategories(for: category)
            availableTargets = allSubs.filter { $0 != sourceSubcategory }
        }
    }
}
