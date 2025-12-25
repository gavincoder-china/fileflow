//
//  IntelligenceCenterView.swift
//  FileFlow
//
//  Created for Unified Intelligence Center
//

import SwiftUI

struct IntelligenceCenterView: View {
    @State private var selectedTab: IntelligenceTab = .dashboard
    
    enum IntelligenceTab: Int, CaseIterable, Identifiable {
        case dashboard
        case knowledge
        case maintenance
        
        var id: Int { rawValue }
        
        var title: String {
            switch self {
            case .dashboard: return "统计仪表盘"
            case .knowledge: return "知识发现"
            case .maintenance: return "整理建议"
            }
        }
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.xaxis"
            case .knowledge: return "network"
            case .maintenance: return "wand.and.stars"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Navigation Bar
            HStack {
                Text("智慧中心")
                    .font(.largeTitle.bold())
                
                Spacer()
                
                Picker("Tab", selection: $selectedTab) {
                    ForEach(IntelligenceTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.regularMaterial)
            
            Divider()
            
            // MARK: - Content Area
            ZStack {
                switch selectedTab {
                case .dashboard:
                    LifecycleDashboardView(isEmbedded: true)
                case .knowledge:
                    KnowledgeHubView(isEmbedded: true)
                case .maintenance:
                    CleanupSuggestionsView(isEmbedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        }
        .background(Color.white) // Unified background
    }
}

#Preview {
    IntelligenceCenterView()
        .frame(width: 1000, height: 800)
}
