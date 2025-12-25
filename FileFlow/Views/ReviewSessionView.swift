//
//  ReviewSessionView.swift
//  FileFlow
//
//  间隔重复复习会话界面
//

import SwiftUI

struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var cards: [KnowledgeCard] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var isLoading = true
    @State private var sessionStats = SessionStats()
    @State private var showingCompletion = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            if isLoading {
                loadingView
            } else if cards.isEmpty {
                emptyView
            } else if showingCompletion {
                completionView
            } else {
                // Main Card Area
                cardArea
                
                Spacer()
                
                // Quality Buttons
                qualityButtons
                    .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadCards()
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("知识复习")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if !cards.isEmpty && !showingCompletion {
                    Text("第 \(currentIndex + 1) / \(cards.count) 张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Progress indicator
            if !cards.isEmpty && !showingCompletion {
                ProgressView(value: Double(currentIndex), total: Double(cards.count))
                    .frame(width: 120)
            }
            
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Card Area
    private var cardArea: some View {
        VStack(spacing: 20) {
            // Card with flip animation
            ZStack {
                // Front (Question)
                cardFront
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                
                // Back (Answer)
                cardBack
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(maxWidth: 500, minHeight: 300)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
            .onTapGesture {
                withAnimation { isFlipped = true }
            }
            
            if !isFlipped {
                Text("点击卡片显示答案")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var cardFront: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)
            
            Text(currentCard?.title ?? "")
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            if let keywords = currentCard?.keywords, !keywords.isEmpty {
                HStack {
                    ForEach(keywords.prefix(5), id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.1)))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }
    
    private var cardBack: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("摘要")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(currentCard?.summary ?? "")
                    .font(.body)
                
                if let keyPoints = currentCard?.keyPoints, !keyPoints.isEmpty {
                    Divider()
                    
                    Text("要点")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    ForEach(keyPoints.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.blue)
                            Text(keyPoints[index])
                                .font(.body)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }
    
    // MARK: - Quality Buttons
    private var qualityButtons: some View {
        HStack(spacing: 20) {
            ForEach(ReviewQuality.allCases, id: \.self) { quality in
                Button {
                    answerCard(with: quality)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: quality.icon)
                            .font(.title2)
                        Text(quality.rawValue)
                            .font(.headline)
                        Text(intervalHint(for: quality))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 100, height: 90)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(buttonColor(for: quality).opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(buttonColor(for: quality), lineWidth: 2)
                    )
                    .foregroundStyle(buttonColor(for: quality))
                }
                .buttonStyle(.plain)
                .disabled(!isFlipped)
                .opacity(isFlipped ? 1 : 0.5)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Empty & Loading Views
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载复习卡片...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            Text("太棒了！")
                .font(.title)
                .fontWeight(.bold)
            
            Text("当前没有待复习的卡片")
                .foregroundStyle(.secondary)
            
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "star.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            
            Text("复习完成!")
                .font(.title)
                .fontWeight(.bold)
            
            // Stats
            VStack(spacing: 12) {
                StatRow(label: "复习卡片", value: "\(sessionStats.totalReviewed)")
                StatRow(label: "简单", value: "\(sessionStats.easyCount)", color: .green)
                StatRow(label: "一般", value: "\(sessionStats.goodCount)", color: .blue)
                StatRow(label: "困难", value: "\(sessionStats.hardCount)", color: .red)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            
            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Helpers
    private var currentCard: KnowledgeCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }
    
    private func buttonColor(for quality: ReviewQuality) -> Color {
        switch quality {
        case .hard: return .red
        case .good: return .blue
        case .easy: return .green
        }
    }
    
    private func intervalHint(for quality: ReviewQuality) -> String {
        guard let card = currentCard else { return "" }
        let baseIntervals = [1, 2, 4, 7, 15, 30, 60]
        let index = min(card.reviewCount, baseIntervals.count - 1)
        let baseDays = Double(baseIntervals[index])
        let adjustedDays = Int(baseDays * quality.intervalMultiplier * (card.easeFactor / 2.5))
        return "\(max(1, adjustedDays))天后"
    }
    
    private func loadCards() async {
        let reviewCards = await KnowledgeLinkService.shared.getCardsForReview()
        await MainActor.run {
            cards = reviewCards
            isLoading = false
        }
    }
    
    private func answerCard(with quality: ReviewQuality) {
        guard let card = currentCard else { return }
        
        // Update stats
        switch quality {
        case .hard: sessionStats.hardCount += 1
        case .good: sessionStats.goodCount += 1
        case .easy: sessionStats.easyCount += 1
        }
        sessionStats.totalReviewed += 1
        
        // Mark reviewed
        Task {
            await KnowledgeLinkService.shared.markCardReviewed(card.id, quality: quality)
        }
        
        // Next card
        withAnimation {
            isFlipped = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentIndex + 1 < cards.count {
                currentIndex += 1
            } else {
                showingCompletion = true
            }
        }
    }
}

// MARK: - Session Stats
private struct SessionStats {
    var totalReviewed = 0
    var easyCount = 0
    var goodCount = 0
    var hardCount = 0
}

// MARK: - Supporting Views
private struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ReviewSessionView()
}
