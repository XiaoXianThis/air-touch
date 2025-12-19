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
    var maxDragRadius: CGFloat = 35
    var dragThreshold: CGFloat = 15  // 拖动阈值，超过此距离才触发指向模式
    
    init(icon: String, size: CGFloat, color: Color, label: String, isDirectional: Bool) {
        self.icon = icon
        self.size = size
        self.color = color
        self.label = label
        self.isDirectional = isDirectional
    }
}

// MARK: - 技能事件
enum SkillEvent {
    case started                                    // 技能开始（按下）
    case dragging(dx: CGFloat, dy: CGFloat, distance: CGFloat)  // 拖动中，dx/dy 归一化到 -1~1
    case released(dx: CGFloat, dy: CGFloat)         // 释放（确认施放）
    case cancelled                                  // 取消
    case tap                                        // 点击（非指向性技能）
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

// MARK: - 平滑拖动控制器
class SmoothDragController: ObservableObject {
    private var displayLink: CADisplayLink?
    private var targetDx: CGFloat = 0
    private var targetDy: CGFloat = 0
    private var currentDx: CGFloat = 0
    private var currentDy: CGFloat = 0
    private var smoothFactor: CGFloat = 0.3
    private var onUpdate: ((CGFloat, CGFloat, CGFloat) -> Void)?
    private var maxRadius: CGFloat = 55
    
    var isActive: Bool { displayLink != nil }
    
    func start(smoothFactor: CGFloat, maxRadius: CGFloat, onUpdate: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
        stop()
        self.smoothFactor = smoothFactor
        self.maxRadius = maxRadius
        self.onUpdate = onUpdate
        self.currentDx = 0
        self.currentDy = 0
        self.targetDx = 0
        self.targetDy = 0
        
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func updateTarget(dx: CGFloat, dy: CGFloat) {
        targetDx = dx
        targetDy = dy
    }
    
    @objc private func update() {
        // 线性插值平滑
        currentDx += (targetDx - currentDx) * smoothFactor
        currentDy += (targetDy - currentDy) * smoothFactor
        
        let distance = sqrt(currentDx * currentDx + currentDy * currentDy)
        let normalizedDistance = min(distance / maxRadius, 1.0)
        let normalizedDx = currentDx / maxRadius
        let normalizedDy = currentDy / maxRadius
        
        onUpdate?(normalizedDx, normalizedDy, normalizedDistance)
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        onUpdate = nil
    }
    
    deinit {
        stop()
    }
}

// MARK: - 技能按钮组件
struct SkillButton: View {
    let config: SkillButtonConfig
    var onSkillEvent: ((SkillEvent) -> Void)?
    var smoothEnabled: Bool = true
    var smoothFactor: CGFloat = 0.3
    
    @StateObject private var cancelZone = CancelZoneState.shared
    @StateObject private var smoothController = SmoothDragController()
    @State private var isDragging = false
    @State private var isDirectionalMode = false  // 是否进入指向模式
    @State private var hasStarted = false         // 是否已发送开始事件
    @State private var dragOffset: CGSize = .zero
    @State private var buttonCenter: CGPoint = .zero
    
    private var dragDistance: CGFloat {
        sqrt(pow(dragOffset.width, 2) + pow(dragOffset.height, 2))
    }
    
    private var dragAngle: CGFloat {
        atan2(dragOffset.height, dragOffset.width)
    }
    
    // 归一化的拖动偏移 (-1 ~ 1)
    private var normalizedDx: CGFloat {
        dragOffset.width / config.maxDragRadius
    }
    
    private var normalizedDy: CGFloat {
        dragOffset.height / config.maxDragRadius
    }
    
    private var normalizedDistance: CGFloat {
        min(dragDistance / config.maxDragRadius, 1.0)
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
                        // 发送技能开始事件
                        if !hasStarted {
                            hasStarted = true
                            onSkillEvent?(.started)
                            
                            // 启动平滑控制器
                            if smoothEnabled {
                                smoothController.start(
                                    smoothFactor: smoothFactor,
                                    maxRadius: config.maxDragRadius
                                ) { dx, dy, dist in
                                    onSkillEvent?(.dragging(dx: dx, dy: dy, distance: dist))
                                }
                            }
                        }
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
                    
                    // 发送拖动事件
                    if smoothEnabled {
                        // 平滑模式：更新目标位置，由 DisplayLink 平滑发送
                        smoothController.updateTarget(dx: dragOffset.width, dy: dragOffset.height)
                    } else {
                        // 直接模式：立即发送
                        onSkillEvent?(.dragging(dx: normalizedDx, dy: normalizedDy, distance: normalizedDistance))
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
                // 停止平滑控制器
                smoothController.stop()
                
                if isDirectionalMode {
                    // 指向模式下释放
                    if cancelZone.isHovering {
                        onSkillEvent?(.cancelled)
                    } else {
                        onSkillEvent?(.released(dx: normalizedDx, dy: normalizedDy))
                    }
                } else {
                    // 点击/短按释放
                    onSkillEvent?(.tap)
                }
                
                // 重置状态
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isDragging = false
                    isDirectionalMode = false
                    hasStarted = false
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
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 20, bottomTrailing: 20, topTrailing: 20))
                .fill(cancelZone.isHovering ? Color.red.opacity(0.7) : Color.gray.opacity(0.3))
                .frame(width: 85, height: 85)
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 20, bottomTrailing: 20, topTrailing: 20))
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
            // .offset(x: -10)  // 稍微往左偏移，因为右侧贴边
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
    ) { event in
        print("Skill event: \(event)")
    }
    .background(Color.black)
}
