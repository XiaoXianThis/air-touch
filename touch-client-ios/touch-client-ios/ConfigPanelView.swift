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
    @State private var showLayoutList = false
    @State private var showAddButton = false
    @State private var editingButton: ButtonItem?
    @State private var newLayoutName = ""
    @State private var showNewLayoutAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 服务器连接设置
                serverConnectionSection
                
                Divider()
                
                // 显示设置
                displaySettingsSection
                
                Divider()
                
                // 当前布局选择器
                layoutSelector
                
                Divider()
                
                // 按钮列表
                buttonList
                
                Divider()
                
                // 底部工具栏
                bottomToolbar
            }
            .navigationTitle("按钮配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        configManager.isEditMode = false
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(configManager.isEditMode ? "预览" : "编辑") {
                        configManager.isEditMode.toggle()
                    }
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
            Button("取消", role: .cancel) {
                newLayoutName = ""
            }
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
    
    // 服务器连接设置
    private var serverConnectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: networkManager.isConnected ? "wifi" : "wifi.slash")
                    .foregroundColor(networkManager.isConnected ? .green : .gray)
                Text("服务器连接")
                    .font(.headline)
                Spacer()
                if networkManager.isConnected && networkManager.latency > 0 {
                    Text("\(networkManager.latency)ms")
                        .font(.caption)
                        .foregroundColor(networkManager.latency < 50 ? .green : (networkManager.latency < 100 ? .orange : .red))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                Text(networkManager.connectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                TextField("服务器IP", text: $networkManager.serverIP)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .autocapitalization(.none)
                
                Text(":")
                
                TextField("端口", value: $networkManager.serverPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 70)
                
                Button(action: {
                    if networkManager.isConnected {
                        networkManager.disconnect()
                    } else {
                        networkManager.connect()
                    }
                }) {
                    Text(networkManager.isConnected ? "断开" : "连接")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(networkManager.isConnected ? Color.red : Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    // 显示设置
    private var displaySettingsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "display")
                    .foregroundColor(.blue)
                Text("显示设置")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .frame(width: 24)
                Text("流光背景")
                Spacer()
                Toggle("", isOn: $configManager.flowingLightEnabled)
                    .labelsHidden()
                    .onChange(of: configManager.flowingLightEnabled) { _, _ in
                        configManager.saveDisplaySettings()
                    }
            }
            
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.green)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("防烧屏")
                    Text("每分钟微移按钮位置")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $configManager.antiBurnInEnabled)
                    .labelsHidden()
                    .onChange(of: configManager.antiBurnInEnabled) { _, _ in
                        configManager.saveDisplaySettings()
                    }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    // 布局选择器
    private var layoutSelector: some View {
        HStack {
            Menu {
                ForEach(configManager.layouts) { layout in
                    Button(action: {
                        configManager.switchLayout(to: layout.id)
                    }) {
                        HStack {
                            Text(layout.name)
                            if layout.id == configManager.currentLayoutId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                Button(action: { showNewLayoutAlert = true }) {
                    Label("新建布局", systemImage: "plus")
                }
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text(configManager.currentLayout?.name ?? "选择布局")
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // 布局操作按钮
            if let layout = configManager.currentLayout {
                Menu {
                    Button(action: {
                        configManager.duplicateLayout(layout)
                    }) {
                        Label("复制布局", systemImage: "doc.on.doc")
                    }
                    
                    if configManager.layouts.count > 1 {
                        Button(role: .destructive, action: {
                            configManager.deleteLayout(layout)
                        }) {
                            Label("删除布局", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
            }
        }
        .padding()
    }
    
    // 按钮列表
    private var buttonList: some View {
        List {
            if let layout = configManager.currentLayout {
                ForEach(layout.buttons) { button in
                    ButtonRowView(button: button)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingButton = button
                        }
                }
                .onDelete { indexSet in
                    if let layoutId = configManager.currentLayoutId {
                        for index in indexSet {
                            let button = layout.buttons[index]
                            configManager.deleteButton(button.id, from: layoutId)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    // 底部工具栏
    private var bottomToolbar: some View {
        HStack {
            Spacer()
            
            // 添加按钮
            Button(action: { showAddButton = true }) {
                Label("添加按钮", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
                    .fill(button.color.opacity(0.3))
                    .frame(width: 44, height: 44)
                
                Image(systemName: button.icon)
                    .font(.system(size: 18))
                    .foregroundColor(button.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(button.label.isEmpty ? button.type.rawValue : button.label)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text(button.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if button.isDirectional {
                        Label("指向", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let key = button.keyBinding {
                        Text("[\(key)]")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
        _keyBinding = State(initialValue: b.keyBinding ?? "")
        _positionX = State(initialValue: b.positionX)
        _positionY = State(initialValue: b.positionY)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // 预览
                Section {
                    HStack {
                        Spacer()
                        buttonPreview
                        Spacer()
                    }
                    .listRowBackground(Color.black)
                }
                
                // 基本设置
                Section("基本设置") {
                    Picker("类型", selection: $type) {
                        ForEach(ButtonType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    TextField("标签", text: $label)
                    
                    Toggle("指向性技能", isOn: $isDirectional)
                }
                
                // 外观设置
                Section("外观") {
                    // 图标选择
                    iconPicker
                    
                    // 颜色选择
                    colorPicker
                    
                    // 大小
                    VStack(alignment: .leading) {
                        Text("大小: \(Int(size))")
                        Slider(value: $size, in: 40...100, step: 5)
                    }
                }
                
                // 位置提示
                Section("位置") {
                    HStack {
                        Image(systemName: "hand.draw")
                            .foregroundColor(.blue)
                        Text("关闭此面板后，在编辑模式下直接拖动按钮调整位置")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 按键绑定
                Section("按键绑定") {
                    TextField("绑定按键 (可选)", text: $keyBinding)
                }
                
                // 删除按钮
                if button != nil, let onDelete = onDelete {
                    Section {
                        Button(role: .destructive, action: {
                            onDelete()
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text("删除按钮")
                                Spacer()
                            }
                        }
                    }
                }
            }
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
            
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .offset(y: size * 0.3)
        }
        .padding()
    }
    
    private var iconPicker: some View {
        VStack(alignment: .leading) {
            Text("图标")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(ButtonItem.availableIcons, id: \.self) { iconName in
                    Button(action: { icon = iconName }) {
                        Image(systemName: iconName)
                            .font(.system(size: 20))
                            .frame(width: 36, height: 36)
                            .background(icon == iconName ? currentColor.opacity(0.3) : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(icon == iconName ? currentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var colorPicker: some View {
        VStack(alignment: .leading) {
            Text("颜色")
            
            HStack(spacing: 10) {
                ForEach(ButtonItem.availableColors, id: \.self) { color in
                    Button(action: { colorName = color }) {
                        Circle()
                            .fill(colorFromName(color))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(colorName == color ? Color.white : Color.clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var currentColor: Color {
        colorFromName(colorName)
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
            keyBinding: keyBinding.isEmpty ? nil : keyBinding
        )
        onSave(newButton)
    }
}
