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
    
    func body(content: Content) -> some View {
        content
            .background(material)
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 16, material: Material = .ultraThin, shadowRadius: CGFloat = 8) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius, material: material, shadowRadius: shadowRadius))
    }
}

// MARK: - Animated Background Gradient
struct AuroraBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor) // Base color
            
            // Blobs
            GeometryReader { proxy in
                ZStack {
                    // Blob 1 (Blue-ish)
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 400, height: 400)
                        .blur(radius: 80)
                        .offset(x: animate ? -100 : 100, y: animate ? -100 : 100)
                    
                    // Blob 2 (Purple-ish)
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: animate ? 200 : -200, y: animate ? 100 : -100)
                    
                    // Blob 3 (Cyan-ish)
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 350, height: 350)
                        .blur(radius: 70)
                        .offset(x: animate ? -150 : 150, y: animate ? 200 : -200)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Modern Button Style
struct GlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isActive 
                ? Color.blue.opacity(0.8) 
                : (configuration.isPressed ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            )
            .background(.ultraThinMaterial)
            .foregroundStyle(isActive ? .white : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.clear : Color.white.opacity(0.2), 
                        lineWidth: 1
                    )
            )
            .animation(.spring(response: 0.3), value: isActive)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}
