//
//  SkillButton.swift
//  touch-client-ios
//
//  Created by mac on 2025/12/18.
//

import SwiftUI
import Combine

// MARK: - 技能按钮配置
struct SkillButtonConfig {
    let icon: String
    let size: CGFloat
    let color: Color
    let label: String
    let isDirectional: Bool
    var maxDragRadius: CGFloat = 55
    var dragThreshold: CGFloat = 15  // 拖动阈值，超过此距离才触发指向模式
    
    init(icon: String, size: CGFloat, color: Color, label: String, isDirectional: Bool) {
        self.icon = icon
        self.size = size
        self.color = color
        self.label = label
        self.isDirectional = isDirectional
    }
}

// MARK: - 技能释放结果
enum SkillReleaseResult {
    case tap                    // 点击释放
    case directional(CGFloat)   // 指向性释放，带角度
    case cancelled              // 取消
}

// MARK: - 取消区域状态（全局共享）
class CancelZoneState: ObservableObject {
    static let shared = CancelZoneState()
    
    @Published var isActive = false           // 是否有技能正在拖动
    @Published var isHovering = false         // 是否悬停在取消区域
    @Published var zoneFrame: CGRect = .zero  // 取消区域的frame
    
    func checkHover(globalPosition: CGPoint) -> Bool {
        let isInZone = zoneFrame.contains(globalPosition)
        isHovering = isInZone
        return isInZone
    }
}

// MARK: - 技能按钮组件
struct SkillButton: View {
    let config: SkillButtonConfig
    var onSkillRelease: ((SkillReleaseResult) -> Void)?
    
    @StateObject private var cancelZone = CancelZoneState.shared
    @State private var isDragging = false
    @State private var isDirectionalMode = false  // 是否进入指向模式
    @State private var dragOffset: CGSize = .zero
    @State private var buttonCenter: CGPoint = .zero
    
    private var dragDistance: CGFloat {
        sqrt(pow(dragOffset.width, 2) + pow(dragOffset.height, 2))
    }
    
    private var dragAngle: CGFloat {
        atan2(dragOffset.height, dragOffset.width)
    }
    
    var body: some View {
        ZStack {
            // 指向性技能的方向指示器（只在指向模式下显示）
            if config.isDirectional && isDirectionalMode {
                DirectionalIndicator(
                    config: config,
                    dragOffset: dragOffset
                )
            }
            
            // 主按钮
            skillButtonContent
                .scaleEffect(isDragging ? 0.9 : 1.0)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            buttonCenter = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                    }
                )
                .gesture(skillGesture)
        }
    }
    
    private var skillButtonContent: some View {
        ZStack {
            Circle()
                .fill(config.color.opacity(isDragging ? 0.4 : 0.2))
                .frame(width: config.size + 10, height: config.size + 10)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [config.color.opacity(0.9), config.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: config.size, height: config.size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isDragging ? 0.8 : 0.4), lineWidth: 2)
                )
                .shadow(color: config.color.opacity(0.6), radius: isDragging ? 15 : 8)
            
            Image(systemName: config.icon)
                .font(.system(size: config.size * 0.35))
                .foregroundColor(.white)
            
            Text(config.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .offset(y: config.size * 0.3)
            
            if config.isDirectional {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.6))
                    .offset(x: config.size * 0.3, y: -config.size * 0.3)
            }
        }
    }
    
    private var skillGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                
                let translation = value.translation
                let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
                
                // 检查是否超过拖动阈值，进入指向模式
                if config.isDirectional && distance > config.dragThreshold {
                    if !isDirectionalMode {
                        isDirectionalMode = true
                        cancelZone.isActive = true
                    }
                    
                    // 限制最大拖动距离
                    if distance <= config.maxDragRadius {
                        dragOffset = translation
                    } else {
                        let angle = atan2(translation.height, translation.width)
                        dragOffset = CGSize(
                            width: cos(angle) * config.maxDragRadius,
                            height: sin(angle) * config.maxDragRadius
                        )
                    }
                    
                    // 检查是否在取消区域
                    let globalPos = CGPoint(
                        x: buttonCenter.x + translation.width,
                        y: buttonCenter.y + translation.height
                    )
                    _ = cancelZone.checkHover(globalPosition: globalPos)
                }
            }
            .onEnded { value in
                let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                
                if isDirectionalMode {
                    // 指向模式下释放
                    if cancelZone.isHovering {
                        onSkillRelease?(.cancelled)
                    } else {
                        onSkillRelease?(.directional(dragAngle))
                    }
                } else {
                    // 点击/短按释放
                    onSkillRelease?(.tap)
                }
                
                // 重置状态
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isDragging = false
                    isDirectionalMode = false
                    dragOffset = .zero
                    cancelZone.isActive = false
                    cancelZone.isHovering = false
                }
            }
    }
}

// MARK: - 方向指示器
struct DirectionalIndicator: View {
    let config: SkillButtonConfig
    let dragOffset: CGSize
    
    private var dragDistance: CGFloat {
        sqrt(pow(dragOffset.width, 2) + pow(dragOffset.height, 2))
    }
    
    private var dragAngle: Angle {
        Angle(radians: atan2(dragOffset.height, dragOffset.width) - Double.pi / 2)
    }
    
    var body: some View {
        ZStack {
            // 外圈范围指示
            Circle()
                .stroke(
                    config.color.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                )
                .frame(width: config.maxDragRadius * 2, height: config.maxDragRadius * 2)
            
            // 方向箭头
            if dragDistance > config.dragThreshold {
                DirectionArrow(
                    length: min(dragDistance, config.maxDragRadius),
                    color: config.color
                )
                .rotationEffect(dragAngle)
                
                // 拖动点
                Circle()
                    .fill(config.color)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: config.color, radius: 5)
                    .offset(dragOffset)
            }
        }
    }
}

// MARK: - 方向箭头
struct DirectionArrow: View {
    let length: CGFloat
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(color)
                .frame(width: 20, height: 15)
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 8, height: max(0, length - 15))
        }
        .offset(y: -length / 2)
    }
}

// MARK: - 三角形
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 取消区域视图
struct CancelZoneView: View {
    @StateObject private var cancelZone = CancelZoneState.shared
    
    var body: some View {
        ZStack {
            // 取消区域背景 - 更大，紧贴右侧
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 20, bottomTrailing: 0, topTrailing: 0))
                .fill(cancelZone.isHovering ? Color.red.opacity(0.7) : Color.gray.opacity(0.3))
                .frame(width: 120, height: 100)
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 20, bottomTrailing: 0, topTrailing: 0))
                        .stroke(
                            cancelZone.isHovering ? Color.red : Color.white.opacity(0.3),
                            lineWidth: 2
                        )
                )
            
            VStack(spacing: 6) {
                Image(systemName: cancelZone.isHovering ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 32))
                    .foregroundColor(cancelZone.isHovering ? .white : .white.opacity(0.6))
                
                Text("取消")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(cancelZone.isHovering ? .white : .white.opacity(0.6))
            }
            .offset(x: -10)  // 稍微往左偏移，因为右侧贴边
        }
        .opacity(cancelZone.isActive ? 1 : 0)
        .scaleEffect(cancelZone.isActive ? 1 : 0.8, anchor: .trailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cancelZone.isActive)
        .animation(.easeInOut(duration: 0.15), value: cancelZone.isHovering)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        cancelZone.zoneFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        cancelZone.zoneFrame = newFrame
                    }
            }
        )
    }
}

#Preview {
    SkillButton(
        config: SkillButtonConfig(
            icon: "star.fill",
            size: 70,
            color: .yellow,
            label: "R",
            isDirectional: true
        )
    )
    .background(Color.black)
}
