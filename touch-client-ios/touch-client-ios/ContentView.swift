//
//  ContentView.swift
//  touch-client-ios
//
//  Created by mac on 2025/12/18.
//

import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    @State private var showConfigPanel = false
    @State private var antiBurnOffset: CGSize = .zero
    
    // 防烧屏定时器
    let antiBurnTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
            let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            
            ZStack {
                // 背景
                if configManager.flowingLightEnabled {
                    FlowingLightBackground()
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
                
                // 按钮区域（全屏，包含摇杆和技能按钮）
                ButtonAreaView()
                    .frame(width: screenWidth, height: screenHeight)
                    .offset(antiBurnOffset)
                
                // 取消区域 - 紧贴右侧边缘
                CancelZoneView()
                    .position(x: screenWidth - 60, y: 70)
                
                // 顶部工具栏
                topBar(screenWidth: screenWidth)
                
                // 编辑模式提示
                if configManager.isEditMode {
                    editModeOverlay(screenHeight: screenHeight)
                }
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .sheet(isPresented: $showConfigPanel) {
            ConfigPanelView(configManager: configManager, isPresented: $showConfigPanel)
        }
        .onReceive(antiBurnTimer) { _ in
            if configManager.antiBurnInEnabled && !configManager.isEditMode {
                withAnimation(.easeInOut(duration: 2)) {
                    // 随机微移 -3 到 3 像素
                    antiBurnOffset = CGSize(
                        width: CGFloat.random(in: -3...3),
                        height: CGFloat.random(in: -3...3)
                    )
                }
            }
        }
    }
    
    private func topBar(screenWidth: CGFloat) -> some View {
        HStack {
            // 连接状态和延迟显示
            HStack(spacing: 4) {
                Circle()
                    .fill(networkManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                if networkManager.isConnected && networkManager.latency > 0 {
                    Text("\(networkManager.latency)ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(networkManager.latency < 50 ? .green : (networkManager.latency < 100 ? .orange : .red))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)
            .padding(.leading, 20)
            
            // 设置按钮
            Button(action: { showConfigPanel = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // 编辑按钮
            Button(action: {
                configManager.isEditMode = true
            }) {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // 当前布局名称
            if let layout = configManager.currentLayout {
                Menu {
                    ForEach(configManager.layouts) { l in
                        Button(action: {
                            configManager.switchLayout(to: l.id)
                        }) {
                            HStack {
                                Text(l.name)
                                if l.id == configManager.currentLayoutId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(layout.name)
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(4)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func editModeOverlay(screenHeight: CGFloat) -> some View {
        VStack {
            // 顶部提示
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "hand.draw")
                    Text("编辑模式 - 拖动按钮调整位置")
                }
                .font(.headline)
                .foregroundColor(.white)
                
                HStack(spacing: 16) {
                    Label("拖动移动", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    Label("点击编辑", systemImage: "pencil")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.9))
            .cornerRadius(12)
            .padding(.top, 100)
            
            Spacer()
            
            // 底部工具栏
            HStack(spacing: 16) {
                // 网格吸附开关
                Button(action: {
                    configManager.showGrid.toggle()
                    configManager.saveGridSetting()
                }) {
                    HStack {
                        Image(systemName: configManager.showGrid ? "grid.circle.fill" : "grid.circle")
                        Text("网格")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(configManager.showGrid ? Color.blue : Color.gray.opacity(0.6))
                    .cornerRadius(8)
                }
                
                Button(action: { showConfigPanel = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("添加按钮")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    configManager.isEditMode = false
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("完成")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(8)
                }
            }
            .padding(.bottom, 30)
        }
    }
}

// MARK: - 流光背景
struct FlowingLightBackground: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            // 深色背景
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black)
            )
            
            // 绘制多条流光
            let colors: [Color] = [.purple, .blue, .cyan, .pink]
            for i in 0..<4 {
                let yOffset = size.height * (0.2 + CGFloat(i) * 0.2)
                let xPhase = phase + CGFloat(i) * 0.5
                
                var path = Path()
                path.move(to: CGPoint(x: -50, y: yOffset))
                
                for x in stride(from: -50, through: size.width + 50, by: 10) {
                    let y = yOffset + sin((x / 100) + xPhase) * 30
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [colors[i].opacity(0), colors[i].opacity(0.3), colors[i].opacity(0)]),
                        startPoint: CGPoint(x: size.width * (phase.truncatingRemainder(dividingBy: 1)), y: 0),
                        endPoint: CGPoint(x: size.width * (phase.truncatingRemainder(dividingBy: 1)) + 200, y: 0)
                    ),
                    lineWidth: 2
                )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

#Preview {
    ContentView()
}
