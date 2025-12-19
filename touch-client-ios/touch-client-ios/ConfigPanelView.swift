//
//  ConfigPanelView.swift
//  touch-client-ios
//
//  Created by mac on 2025/12/18.
//

import SwiftUI

// MARK: - 配置面板
struct ConfigPanelView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var networkManager = NetworkManager.shared
    @Binding var isPresented: Bool
    @State private var showAddButton = false
    @State private var editingButton: ButtonItem?
    @State private var newLayoutName = ""
    @State private var showNewLayoutAlert = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 分段选择器
                    Picker("", selection: $selectedTab) {
                        Text("连接").tag(0)
                        Text("显示").tag(1)
                        Text("按钮").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // 内容区域
                    switch selectedTab {
                    case 0:
                        connectionTab
                    case 1:
                        displayTab
                    case 2:
                        buttonsTab
                    default:
                        EmptyView()
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        configManager.isEditMode = false
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showAddButton) {
            ButtonEditorView(
                configManager: configManager,
                button: nil,
                onSave: { newButton in
                    if let layoutId = configManager.currentLayoutId {
                        configManager.addButton(to: layoutId, button: newButton)
                    }
                }
            )
        }
        .sheet(item: $editingButton) { button in
            ButtonEditorView(
                configManager: configManager,
                button: button,
                onSave: { updatedButton in
                    if let layoutId = configManager.currentLayoutId {
                        configManager.updateButton(updatedButton, in: layoutId)
                    }
                },
                onDelete: {
                    if let layoutId = configManager.currentLayoutId {
                        configManager.deleteButton(button.id, from: layoutId)
                    }
                }
            )
        }
        .alert("新建布局", isPresented: $showNewLayoutAlert) {
            TextField("布局名称", text: $newLayoutName)
            Button("取消", role: .cancel) { newLayoutName = "" }
            Button("创建") {
                if !newLayoutName.isEmpty {
                    configManager.createLayout(name: newLayoutName)
                    newLayoutName = ""
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .editButtonTapped)) { notification in
            if let button = notification.object as? ButtonItem {
                editingButton = button
            }
        }
    }
    
    // MARK: - 连接标签页
    private var connectionTab: some View {
        VStack(spacing: 16) {
            // 连接状态卡片
            SettingsCard {
                VStack(spacing: 16) {
                    // 状态指示器
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(networkManager.isConnected ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: networkManager.isConnected ? "wifi" : "wifi.slash")
                                .font(.title2)
                                .foregroundColor(networkManager.isConnected ? .green : .red)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(networkManager.isConnected ? "已连接" : "未连接")
                                .font(.headline)
                            Text(networkManager.connectionStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if networkManager.isConnected && networkManager.latency > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(networkManager.latency)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(latencyColor)
                                Text("ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 自动发现的服务器
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bonjour")
                                .foregroundColor(.blue)
                            Text("自动发现")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            
                            Button(action: {
                                if networkManager.isSearching {
                                    networkManager.stopBrowsing()
                                } else {
                                    networkManager.startBrowsing()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if networkManager.isSearching {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(networkManager.isSearching ? "停止" : "搜索")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        
                        if networkManager.discoveredServers.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                    Text(networkManager.isSearching ? "正在搜索..." : "点击搜索发现服务器")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 12)
                                Spacer()
                            }
                        } else {
                            ForEach(networkManager.discoveredServers) { server in
                                Button(action: {
                                    networkManager.connectToServer(server)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "desktopcomputer")
                                            .foregroundColor(.green)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(server.name)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            if !server.host.isEmpty {
                                                Text("\(server.host):\(server.port)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 手动输入服务器地址
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.orange)
                            Text("手动连接")
                                .font(.subheadline.weight(.medium))
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "server.rack")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            
                            TextField("服务器IP", text: $networkManager.serverIP)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .autocapitalization(.none)
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "number")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            
                            TextField("端口", value: $networkManager.serverPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                    }
                    
                    // 连接按钮
                    Button(action: {
                        if networkManager.isConnected {
                            networkManager.disconnect()
                        } else {
                            networkManager.connect()
                        }
                    }) {
                        HStack {
                            Image(systemName: networkManager.isConnected ? "xmark.circle" : "link")
                            Text(networkManager.isConnected ? "断开连接" : "连接服务器")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(networkManager.isConnected ? Color.red : Color.blue)
                        .cornerRadius(12)
                    }
                }
            }
            
            // 极限模式设置
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "极限模式",
                        subtitle: "二进制协议 + 节流优化，最低延迟",
                        isOn: $networkManager.extremeMode
                    )
                    
                    if networkManager.extremeMode {
                        Divider().padding(.leading, 44)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("已启用：二进制协议、摇杆节流、服务端无锁优化")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.horizontal)
        .onAppear {
            // 自动开始搜索
            if !networkManager.isConnected {
                networkManager.startBrowsing()
            }
        }
        .onDisappear {
            networkManager.stopBrowsing()
        }
    }
    
    private var latencyColor: Color {
        if networkManager.latency < 50 { return .green }
        if networkManager.latency < 100 { return .orange }
        return .red
    }
    
    // MARK: - 显示标签页
    private var displayTab: some View {
        VStack(spacing: 16) {
            // 技能操作设置
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "hand.draw",
                        iconColor: .cyan,
                        title: "平滑鼠标移动",
                        subtitle: "技能拖动时更流畅跟手",
                        isOn: $configManager.smoothMouseEnabled
                    )
                    .onChange(of: configManager.smoothMouseEnabled) { _, _ in
                        configManager.saveDisplaySettings()
                    }
                    
                    if configManager.smoothMouseEnabled {
                        Divider().padding(.leading, 44)
                        
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cyan.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.cyan)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("平滑程度")
                                    .font(.body)
                                Text(smoothnessDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Slider(value: $configManager.smoothMouseFactor, in: 0.15...0.6, step: 0.05)
                                .frame(width: 100)
                                .onChange(of: configManager.smoothMouseFactor) { _, _ in
                                    configManager.saveDisplaySettings()
                                }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            
            // 原点偏移设置
            SettingsCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "move.3d")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("原点偏移")
                                .font(.body)
                            Text("调整技能释放的鼠标原点位置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    
                    Divider().padding(.leading, 44)
                    
                    // 水平偏移
                    HStack(spacing: 12) {
                        Text("水平")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                        
                        Slider(value: Binding(
                            get: { Double(configManager.originOffsetX) },
                            set: { configManager.originOffsetX = Int($0) }
                        ), in: -500...500, step: 10)
                        
                        Text("\(configManager.originOffsetX)")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .onChange(of: configManager.originOffsetX) { _, _ in
                        configManager.saveDisplaySettings()
                    }
                    
                    // 垂直偏移
                    HStack(spacing: 12) {
                        Text("垂直")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                        
                        Slider(value: Binding(
                            get: { Double(configManager.originOffsetY) },
                            set: { configManager.originOffsetY = Int($0) }
                        ), in: -500...500, step: 10)
                        
                        Text("\(configManager.originOffsetY)")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .onChange(of: configManager.originOffsetY) { _, _ in
                        configManager.saveDisplaySettings()
                    }
                    
                    // 重置按钮
                    Button(action: {
                        configManager.originOffsetX = 0
                        configManager.originOffsetY = 0
                        configManager.saveDisplaySettings()
                    }) {
                        Text("重置偏移")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)
                }
            }
            
            // 显示效果设置
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "流光背景",
                        subtitle: "动态流光效果",
                        isOn: $configManager.flowingLightEnabled
                    )
                    .onChange(of: configManager.flowingLightEnabled) { _, _ in
                        configManager.saveDisplaySettings()
                    }
                    
                    Divider().padding(.leading, 44)
                    
                    SettingsToggleRow(
                        icon: "shield.lefthalf.filled",
                        iconColor: .green,
                        title: "防烧屏",
                        subtitle: "每分钟微移按钮位置",
                        isOn: $configManager.antiBurnInEnabled
                    )
                    .onChange(of: configManager.antiBurnInEnabled) { _, _ in
                        configManager.saveDisplaySettings()
                    }
                    
                    Divider().padding(.leading, 44)
                    
                    SettingsToggleRow(
                        icon: "grid",
                        iconColor: .blue,
                        title: "编辑网格",
                        subtitle: "编辑模式显示对齐网格",
                        isOn: $configManager.showGrid
                    )
                    .onChange(of: configManager.showGrid) { _, _ in
                        configManager.saveGridSetting()
                    }
                    
                    if configManager.showGrid {
                        Divider().padding(.leading, 44)
                        
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "square.grid.3x3")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("网格大小")
                                    .font(.body)
                                Text("\(Int(configManager.gridSize)) 像素")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Slider(value: $configManager.gridSize, in: 10...50, step: 5)
                                .frame(width: 120)
                                .onChange(of: configManager.gridSize) { _, _ in
                                    configManager.saveGridSetting()
                                }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var smoothnessDescription: String {
        if configManager.smoothMouseFactor < 0.25 {
            return "非常平滑（延迟较高）"
        } else if configManager.smoothMouseFactor < 0.35 {
            return "平滑（推荐）"
        } else if configManager.smoothMouseFactor < 0.45 {
            return "适中"
        } else {
            return "跟手（延迟较低）"
        }
    }
    
    // MARK: - 按钮标签页
    private var buttonsTab: some View {
        VStack(spacing: 16) {
            // 布局选择器
            SettingsCard {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.blue)
                        Text("当前布局")
                            .font(.headline)
                        Spacer()
                    }
                    
                    // 布局列表
                    ForEach(configManager.layouts) { layout in
                        LayoutRow(
                            layout: layout,
                            isSelected: layout.id == configManager.currentLayoutId,
                            onSelect: { configManager.switchLayout(to: layout.id) },
                            onDuplicate: { configManager.duplicateLayout(layout) },
                            onDelete: configManager.layouts.count > 1 ? { configManager.deleteLayout(layout) } : nil
                        )
                    }
                    
                    // 新建布局按钮
                    Button(action: { showNewLayoutAlert = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("新建布局")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
            
            // 按钮列表
            if let layout = configManager.currentLayout {
                SettingsCard {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "circle.grid.2x2")
                                .foregroundColor(.orange)
                            Text("按钮列表")
                                .font(.headline)
                            Spacer()
                            Text("\(layout.buttons.count) 个")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if layout.buttons.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle.dashed")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("暂无按钮")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(layout.buttons) { button in
                                ButtonRowView(button: button)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingButton = button }
                                
                                if button.id != layout.buttons.last?.id {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                        
                        // 添加按钮
                        Button(action: { showAddButton = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("添加按钮")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 设置卡片容器
struct SettingsCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - 设置开关行
struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 布局行
struct LayoutRow: View {
    let layout: LayoutConfig
    let isSelected: Bool
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layout.name)
                            .font(.body)
                            .foregroundColor(.primary)
                        Text("\(layout.buttons.count) 个按钮")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            Menu {
                Button(action: onDuplicate) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                if let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .cornerRadius(10)
    }
}

// MARK: - 按钮行视图
struct ButtonRowView: View {
    let button: ButtonItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 按钮预览
            ZStack {
                Circle()
                    .fill(button.color.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: button.icon)
                    .font(.system(size: 18))
                    .foregroundColor(button.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(button.label.isEmpty ? button.type.rawValue : button.label)
                    .font(.body)
                
                HStack(spacing: 8) {
                    Label(button.type.rawValue, systemImage: "tag")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if button.isDirectional {
                        Label("指向", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let config = button.effectiveKeyConfig {
                        Text("[\(config.displayString)]")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 按钮编辑器
struct ButtonEditorView: View {
    @ObservedObject var configManager: ConfigManager
    let button: ButtonItem?
    let onSave: (ButtonItem) -> Void
    var onDelete: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var type: ButtonType
    @State private var label: String
    @State private var icon: String
    @State private var colorName: String
    @State private var size: CGFloat
    @State private var isDirectional: Bool
    @State private var keyBinding: String
    @State private var positionX: CGFloat
    @State private var positionY: CGFloat
    // 组合键配置
    @State private var specialKey: SpecialKey
    @State private var modShift: Bool
    @State private var modControl: Bool
    @State private var modAlt: Bool
    @State private var modCommand: Bool
    
    init(configManager: ConfigManager, button: ButtonItem?, onSave: @escaping (ButtonItem) -> Void, onDelete: (() -> Void)? = nil) {
        self.configManager = configManager
        self.button = button
        self.onSave = onSave
        self.onDelete = onDelete
        
        let b = button ?? ButtonItem()
        _type = State(initialValue: b.type)
        _label = State(initialValue: b.label)
        _icon = State(initialValue: b.icon)
        _colorName = State(initialValue: b.colorName)
        _size = State(initialValue: b.size)
        _isDirectional = State(initialValue: b.isDirectional)
        _positionX = State(initialValue: b.positionX)
        _positionY = State(initialValue: b.positionY)
        
        // 初始化按键配置
        let config = b.effectiveKeyConfig ?? KeyBindingConfig()
        _keyBinding = State(initialValue: config.key)
        _specialKey = State(initialValue: config.specialKey)
        _modShift = State(initialValue: config.modifiers.shift)
        _modControl = State(initialValue: config.modifiers.control)
        _modAlt = State(initialValue: config.modifiers.alt)
        _modCommand = State(initialValue: config.modifiers.command)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 预览卡片
                    SettingsCard {
                        VStack(spacing: 12) {
                            Text("预览")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            buttonPreview
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .background(Color.black)
                    .cornerRadius(16)
                    
                    // 基本设置
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("基本设置")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("类型")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Picker("类型", selection: $type) {
                                    ForEach(ButtonType.allCases, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("标签")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("按钮标签", text: $label)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack {
                                Text("指向性技能")
                                Spacer()
                                Toggle("", isOn: $isDirectional)
                                    .labelsHidden()
                            }
                        }
                    }
                    
                    // 外观设置
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("外观")
                                .font(.headline)
                            
                            // 图标选择
                            VStack(alignment: .leading, spacing: 8) {
                                Text("图标")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                                    ForEach(ButtonItem.availableIcons, id: \.self) { iconName in
                                        Button(action: { icon = iconName }) {
                                            Image(systemName: iconName)
                                                .font(.system(size: 18))
                                                .frame(width: 40, height: 40)
                                                .background(icon == iconName ? currentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                                .cornerRadius(10)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(icon == iconName ? currentColor : Color.clear, lineWidth: 2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // 颜色选择
                            VStack(alignment: .leading, spacing: 8) {
                                Text("颜色")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    ForEach(ButtonItem.availableColors, id: \.self) { color in
                                        Button(action: { colorName = color }) {
                                            Circle()
                                                .fill(colorFromName(color))
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: colorName == color ? 3 : 0)
                                                )
                                                .shadow(color: colorName == color ? colorFromName(color).opacity(0.5) : .clear, radius: 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // 大小
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("大小")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(size))")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .monospacedDigit()
                                }
                                Slider(value: $size, in: 40...100, step: 5)
                                    .tint(currentColor)
                            }
                        }
                    }
                    
                    // 按键绑定
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("按键绑定")
                                    .font(.headline)
                                Spacer()
                                Text(currentKeyDisplayString)
                                    .font(.subheadline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(6)
                            }
                            
                            // 普通按键输入
                            VStack(alignment: .leading, spacing: 8) {
                                Text("普通按键")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("输入按键 (a-z, 0-9)", text: $keyBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none)
                                    .onChange(of: keyBinding) { _, newValue in
                                        // 只保留第一个字符
                                        if newValue.count > 1 {
                                            keyBinding = String(newValue.prefix(1))
                                        }
                                        // 如果输入了普通按键，清除特殊按键
                                        if !newValue.isEmpty {
                                            specialKey = .none
                                        }
                                    }
                            }
                            
                            // 特殊按键选择
                            VStack(alignment: .leading, spacing: 8) {
                                Text("特殊按键")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(SpecialKey.allCases, id: \.self) { key in
                                            Button(action: {
                                                specialKey = key
                                                if key != .none {
                                                    keyBinding = ""  // 清除普通按键
                                                }
                                            }) {
                                                Text(key.displayName)
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(specialKey == key ? currentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                                    .foregroundColor(specialKey == key ? currentColor : .primary)
                                                    .cornerRadius(8)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(specialKey == key ? currentColor : Color.clear, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // 修饰键
                            VStack(alignment: .leading, spacing: 12) {
                                Text("修饰键（组合键）")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    ModifierToggle(label: "Ctrl", isOn: $modControl, color: currentColor)
                                    ModifierToggle(label: "Alt", isOn: $modAlt, color: currentColor)
                                    ModifierToggle(label: "Shift", isOn: $modShift, color: currentColor)
                                    ModifierToggle(label: "Cmd", isOn: $modCommand, color: currentColor)
                                }
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("支持组合键，如 Ctrl+Q、Shift+F1")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    // 位置提示
                    SettingsCard {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.draw")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("调整位置")
                                    .font(.headline)
                                Text("关闭设置后，在编辑模式下直接拖动按钮")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // 删除按钮
                    if button != nil, let onDelete = onDelete {
                        Button(action: {
                            onDelete()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("删除按钮")
                            }
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(button == nil ? "添加按钮" : "编辑按钮")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveButton()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var buttonPreview: some View {
        ZStack {
            Circle()
                .fill(currentColor.opacity(0.3))
                .frame(width: size + 10, height: size + 10)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [currentColor.opacity(0.9), currentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                )
            
            Image(systemName: icon)
                .font(.system(size: size * 0.35))
                .foregroundColor(.white)
            
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .offset(y: size * 0.3)
            }
        }
        .padding()
    }
    
    private var currentColor: Color {
        colorFromName(colorName)
    }
    
    private var currentKeyDisplayString: String {
        let config = KeyBindingConfig(
            key: keyBinding,
            specialKey: specialKey,
            modifiers: ModifierKeys(shift: modShift, control: modControl, alt: modAlt, command: modCommand)
        )
        return config.displayString
    }
    
    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "cyan": return .cyan
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return .gray
        }
    }
    
    private func saveButton() {
        let keyConfig = KeyBindingConfig(
            key: keyBinding,
            specialKey: specialKey,
            modifiers: ModifierKeys(shift: modShift, control: modControl, alt: modAlt, command: modCommand)
        )
        
        let newButton = ButtonItem(
            id: button?.id ?? UUID(),
            type: type,
            label: label,
            icon: icon,
            colorName: colorName,
            size: size,
            positionX: positionX,
            positionY: positionY,
            isDirectional: isDirectional,
            keyBinding: nil,  // 不再使用旧版
            keyBindingConfig: keyConfig.isEmpty ? nil : keyConfig
        )
        onSave(newButton)
    }
}

// MARK: - 修饰键切换按钮
struct ModifierToggle: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOn ? color.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundColor(isOn ? color : .secondary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? color : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
