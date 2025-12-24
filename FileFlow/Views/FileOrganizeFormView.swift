import SwiftUI

struct FileOrganizeFormView: View {
    @ObservedObject var viewModel: FileOrganizeViewModel
    @Binding var showingSubcategoryInput: Bool
    @Binding var newSubcategoryName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // File Preview Card
            FilePreviewSection(viewModel: viewModel)
                .padding(.horizontal)
            
            // AI Summary Card
            if viewModel.isAnalyzing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI 正在分析文件...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            } else if let summary = viewModel.aiSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI 摘要", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                    
                    Text(summary)
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Tags Card
            TagsSection(viewModel: viewModel)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)
            
            // Category Card
            VStack(spacing: 16) {
                CategorySection(
                    viewModel: viewModel,
                    showingSubcategoryInput: $showingSubcategoryInput,
                    newSubcategoryName: $newSubcategoryName
                )
                
                Divider().opacity(0.3)
                
                FileNamePreviewSection(viewModel: viewModel)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Notes Card
            NotesSection(viewModel: viewModel)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
}
