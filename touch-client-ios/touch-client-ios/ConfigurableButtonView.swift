//
//  ConfigurableButtonView.swift
//  touch-client-ios
//
//  Created by mac on 2025/12/18.
//

import SwiftUI

// MARK: - 可配置按钮视图
struct DraggableButtonView: View {
    @ObservedObject var configManager: ConfigManager
    let buttonId: UUID
    let layoutId: UUID
    
    @State private var isDragging = false
    @State private var dragPosition: CGPoint? = nil
    
    private var button: ButtonItem? {
        configManager.layouts
            .first { $0.id == layoutId }?
            .buttons.first { $0.id == buttonId }
    }
    
    var body: some View {
        if let button = button {
            let position = dragPosition ?? CGPoint(x: button.positionX, y: button.positionY)
            
            Group {
                if configManager.isEditMode {
                    editModeButton(button: button)
                } else {
                    let config = SkillButtonConfig(
                        icon: button.icon,
                        size: button.size,
                        color: button.color,
                        label: button.label,
                        isDirectional: button.isDirectional
                    )
                    SkillButton(config: config) { result in
                        handleSkillRelease(button: button, result: result)
                    }
                }
            }
            .position(position)
        }
    }
    
    private func editModeButton(button: ButtonItem) -> some View {
        ZStack {
            Circle()
                .fill(button.color.opacity(0.3))
                .frame(width: button.size + 10, height: button.size + 10)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [button.color.opacity(0.9), button.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: button.size, height: button.size)
                .overlay(
                    Circle()
                        .stroke(isDragging ? Color.white : Color.white.opacity(0.4), lineWidth: isDragging ? 3 : 2)
                )
            
            Image(systemName: button.icon)
                .font(.system(size: button.size * 0.35))
                .foregroundColor(.white)
            
            Text(button.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .offset(y: button.size * 0.3)
            
            // 编辑图标 - 点击打开编辑面板
            Button(action: {
                NotificationCenter.default.post(name: .editButtonTapped, object: button)
            }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.blue).frame(width: 24, height: 24))
            }
            .offset(x: button.size * 0.4, y: -button.size * 0.4)
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named("buttonArea"))
                .onChanged { value in
                    isDragging = true
                    // 应用网格吸附
                    let snappedX = configManager.snapToGrid(value.location.x)
                    let snappedY = configManager.snapToGrid(value.location.y)
                    dragPosition = CGPoint(x: snappedX, y: snappedY)
                }
                .onEnded { value in
                    // 保存绝对位置（带网格吸附）
                    let finalX = configManager.snapToGrid(value.location.x)
                    let finalY = configManager.snapToGrid(value.location.y)
                    
                    if let layoutIndex = configManager.layouts.firstIndex(where: { $0.id == layoutId }),
                       let buttonIndex = configManager.layouts[layoutIndex].buttons.firstIndex(where: { $0.id == buttonId }) {
                        configManager.layouts[layoutIndex].buttons[buttonIndex].positionX = finalX
                        configManager.layouts[layoutIndex].buttons[buttonIndex].positionY = finalY
                        configManager.saveLayouts()
                    }
                    
                    dragPosition = nil
                    isDragging = false
                }
        )
    }
    
    private func handleSkillRelease(button: ButtonItem, result: SkillReleaseResult) {
        switch result {
        case .tap:
            print("Button \(button.label): tap release")
        case .directional(let angle):
            print("Button \(button.label): directional release at angle \(angle)")
        case .cancelled:
            print("Button \(button.label): cancelled")
        }
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let editButtonTapped = Notification.Name("editButtonTapped")
}

// MARK: - 可拖动摇杆视图
struct DraggableJoystickView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var networkManager = NetworkManager.shared
    let size: CGFloat
    
    @State private var isDragging = false
    @State private var dragPosition: CGPoint? = nil
    @State private var knobOffset: CGSize = .zero
    @State private var isOperating = false
    
    private var knobSize: CGFloat { size * 0.45 }
    private var maxDistance: CGFloat { (size - knobSize) / 2 }
    
    private var position: CGPoint {
        dragPosition ?? CGPoint(x: configManager.joystickX, y: configManager.joystickY)
    }
    
    var body: some View {
        Group {
            if configManager.isEditMode {
                editModeJoystick
            } else {
                joystickContent
                    .gesture(joystickGesture)
            }
        }
        .position(position)
    }
    
    private var joystickContent: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
            
            ForEach(0..<8) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: size * 0.35)
                    .offset(y: -size * 0.15)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: knobSize, height: knobSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                )
                .shadow(color: .blue.opacity(0.5), radius: isOperating ? 10 : 5)
                .offset(knobOffset)
        }
    }
    
    private var editModeJoystick: some View {
        ZStack {
            joystickContent
            
            // 编辑模式标识
            Button(action: {
                // 摇杆没有编辑面板，只能拖动
            }) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.orange).frame(width: 24, height: 24))
            }
            .offset(x: size * 0.4, y: -size * 0.4)
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named("buttonArea"))
                .onChanged { value in
                    isDragging = true
                    let snappedX = configManager.snapToGrid(value.location.x)
                    let snappedY = configManager.snapToGrid(value.location.y)
                    dragPosition = CGPoint(x: snappedX, y: snappedY)
                }
                .onEnded { value in
                    let finalX = configManager.snapToGrid(value.location.x)
                    let finalY = configManager.snapToGrid(value.location.y)
                    configManager.joystickX = finalX
                    configManager.joystickY = finalY
                    configManager.saveJoystickPosition()
                    dragPosition = nil
                    isDragging = false
                }
        )
    }
    
    private var joystickGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isOperating = true
                let translation = value.translation
                let distance = sqrt(pow(translation.width, 2) + pow(translation.height, 2))
                
                if distance <= maxDistance {
                    knobOffset = translation
                } else {
                    let angle = atan2(translation.height, translation.width)
                    knobOffset = CGSize(
                        width: cos(angle) * maxDistance,
                        height: sin(angle) * maxDistance
                    )
                }
                
                // 发送摇杆数据到服务器 (归一化到 -1 ~ 1)
                let normalizedX = Float(knobOffset.width / maxDistance)
                let normalizedY = Float(knobOffset.height / maxDistance)
                networkManager.sendJoystick(x: normalizedX, y: normalizedY)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    knobOffset = .zero
                    isOperating = false
                }
                // 释放时发送归零
                networkManager.sendJoystick(x: 0, y: 0)
            }
    }
}

// MARK: - 按钮区域容器
struct ButtonAreaView: View {
    @StateObject private var configManager = ConfigManager.shared
    
    var body: some View {
        ZStack {
            // 编辑模式下显示网格
            if configManager.isEditMode && configManager.showGrid {
                GridOverlay(gridSize: configManager.gridSize)
            }
            
            // 摇杆
            DraggableJoystickView(configManager: configManager, size: 150)
            
            // 技能按钮
            if let layout = configManager.currentLayout {
                ForEach(layout.buttons) { button in
                    DraggableButtonView(
                        configManager: configManager,
                        buttonId: button.id,
                        layoutId: layout.id
                    )
                }
            }
        }
        .coordinateSpace(name: "buttonArea")
    }
}

// MARK: - 网格覆盖层
struct GridOverlay: View {
    let gridSize: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let cols = Int(geometry.size.width / gridSize)
                for i in 0...cols {
                    let x = CGFloat(i) * gridSize
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                
                let rows = Int(geometry.size.height / gridSize)
                for i in 0...rows {
                    let y = CGFloat(i) * gridSize
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}
