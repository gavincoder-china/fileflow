//
//  DesignSystem.swift
//  FileFlow
//
//  设计系统：Glassmorphism 风格组件与扩展
//

import SwiftUI

// MARK: - Glass Effect Modifier
struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material
    var shadowRadius: CGFloat
    var shadowOpacity: Double = 0.12
    
    func body(content: Content) -> some View {
        content
            .background(material)
            .cornerRadius(cornerRadius)
            // Ambient Soft Shadow
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowRadius / 2)
            .overlay(
                ZStack {
                    // Outer Rim Highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                    
                    // Inner Glow (Modern Organic Glass Look)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .clear, .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .padding(1)
                        .blur(radius: 1)
                }
            )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 32, material: Material = .ultraThin, shadowRadius: CGFloat = 12) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius, material: material, shadowRadius: shadowRadius))
    }
}

// MARK: - Animated Background Gradient
struct AuroraBackground: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            // Base: Pure White
            Color.white
            
            // Layer 1: Wallpaper (Optional)
            if appState.useBingWallpaper {
                if let url = appState.wallpaperURL {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ProgressView().controlSize(.small)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                    .opacity(appState.wallpaperOpacity)
                    .blur(radius: appState.wallpaperBlur)
                    
                    // Overlay for readability
                    if appState.showGlassOverlay {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.8)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar Selection Modifier
struct SidebarSelectionModifier: ViewModifier {
    var isSelected: Bool
    var color: Color
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .shadow(color: color.opacity(0.15), radius: 2, x: 0, y: 1) // Very subtle shadow
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hover
                }
            }
    }
}

extension View {
    func sidebarSelection(isSelected: Bool, color: Color = .blue) -> some View {
        modifier(SidebarSelectionModifier(isSelected: isSelected, color: color))
    }
}

// MARK: - Modern Button Style
struct GlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                isActive 
                ? Color.blue.opacity(0.7) 
                : (configuration.isPressed ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
            )
            .background(.ultraThinMaterial)
            .foregroundStyle(isActive ? .white : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isActive ? .white.opacity(0.3) : .white.opacity(0.15), 
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3), value: isActive)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}
