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
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Layer 0: System Base
            Color(nsColor: .windowBackgroundColor)
            
            // Layer 1: Wallpaper
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
                }
                
                // Overlay for readability
                if appState.showGlassOverlay {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.8)
                }
            } else {
                // Secondary Fallback Gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Layer 2: Animated Floating Blobs (Premium Depth)
            GeometryReader { proxy in
                ZStack {
                    // Projects Indigo Bloom
                    Circle()
                        .fill(Color(hex: "#4F46E5")?.opacity(0.18) ?? .blue.opacity(0.15))
                        .frame(width: 600, height: 600)
                        .blur(radius: 120)
                        .offset(x: animate ? -proxy.size.width * 0.3 : proxy.size.width * 0.2, 
                                y: animate ? -proxy.size.height * 0.2 : proxy.size.height * 0.3)
                    
                    // Areas Amethyst Bloom
                    Circle()
                        .fill(Color(hex: "#A855F7")?.opacity(0.14) ?? .purple.opacity(0.12))
                        .frame(width: 500, height: 500)
                        .blur(radius: 100)
                        .offset(x: animate ? proxy.size.width * 0.4 : -proxy.size.width * 0.2, 
                                y: animate ? proxy.size.height * 0.3 : -proxy.size.height * 0.2)
                }
                .blendMode(.plusLighter)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar Selection Modifier
struct SidebarSelectionModifier: ViewModifier {
    var isSelected: Bool
    var color: Color
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    ZStack {
                        // Smooth Gradient Fill
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.8), color],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Glass Highlight
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.02))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
