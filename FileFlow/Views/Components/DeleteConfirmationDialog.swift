//
//  DeleteConfirmationDialog.swift
//  FileFlow
//
//  删除确认对话框 - 避免误删文件
//

import SwiftUI

struct DeleteConfirmationDialog: View {
    let file: ManagedFile
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            // Title
            Text("确认删除")
                .font(.title2)
                .fontWeight(.semibold)
            
            // File info
            HStack(spacing: 12) {
                RichFileIcon(path: file.newPath)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(file.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            // Warning message
            Text("文件将被移至废纸篓，您可以从废纸篓中恢复。\n同时会从 FileFlow 数据库中移除记录。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Action buttons
            HStack(spacing: 16) {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(10)
                
                Button {
                    onConfirm()
                    isPresented = false
                } label: {
                    Text("删除")
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
        .shadow(radius: 20)
    }
}

// MARK: - Confirmation Dialog Modifier
struct DeleteConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let file: ManagedFile
    let onConfirm: () -> Void
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                DeleteConfirmationDialog(
                    file: file,
                    isPresented: $isPresented,
                    onConfirm: onConfirm
                )
            }
    }
}

extension View {
    func deleteConfirmation(isPresented: Binding<Bool>, file: ManagedFile, onConfirm: @escaping () -> Void) -> some View {
        modifier(DeleteConfirmationModifier(isPresented: isPresented, file: file, onConfirm: onConfirm))
    }
}
