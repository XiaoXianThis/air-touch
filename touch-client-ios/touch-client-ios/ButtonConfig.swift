//
//  ButtonConfig.swift
//  touch-client-ios
//
//  Created by mac on 2025/12/18.
//

import SwiftUI
import Combine

// MARK: - 按钮类型
enum ButtonType: String, Codable, CaseIterable {
    case skill = "技能"
    case attack = "普攻"
    case joystick = "摇杆"
    case custom = "自定义"
    
    var defaultIcon: String {
        switch self {
        case .skill: return "star.fill"
        case .attack: return "hand.raised.fill"
        case .joystick: return "arrow.up.and.down.and.arrow.left.and.right"
        case .custom: return "square.fill"
        }
    }
    
    var defaultColor: String {
        switch self {
        case .skill: return "cyan"
        case .attack: return "orange"
        case .joystick: return "blue"
        case .custom: return "gray"
        }
    }
}

// MARK: - 单个按钮配置
struct ButtonItem: Identifiable, Codable, Equatable {
    var id: UUID
    var type: ButtonType
    var label: String
    var icon: String
    var colorName: String
    var size: CGFloat
    var positionX: CGFloat
    var positionY: CGFloat
    var isDirectional: Bool
    var keyBinding: String?  // 绑定的按键
    
    // 默认位置为屏幕中心（横屏 iPhone 约 400x180）
    init(
        id: UUID = UUID(),
        type: ButtonType = .custom,
        label: String = "",
        icon: String = "circle.fill",
        colorName: String = "gray",
        size: CGFloat = 60,
        positionX: CGFloat = 400,
        positionY: CGFloat = 180,
        isDirectional: Bool = false,
        keyBinding: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.icon = icon
        self.colorName = colorName
        self.size = size
        self.positionX = positionX
        self.positionY = positionY
        self.isDirectional = isDirectional
        self.keyBinding = keyBinding
    }
    
    var color: Color {
        switch colorName {
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
    
    static let availableColors = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "gray"]
    
    static let availableIcons = [
        "star.fill", "bolt.fill", "flame.fill", "hand.raised.fill",
        "sparkles", "heart.fill", "shield.fill", "wand.and.stars",
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
        "a.circle.fill", "b.circle.fill", "x.circle.fill", "y.circle.fill",
        "l.circle.fill", "r.circle.fill", "1.circle.fill", "2.circle.fill",
        "3.circle.fill", "4.circle.fill", "arrow.up.circle.fill", "arrow.down.circle.fill"
    ]
}

// MARK: - 布局配置
struct LayoutConfig: Identifiable, Codable {
    var id: UUID
    var name: String
    var buttons: [ButtonItem]
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, buttons: [ButtonItem] = []) {
        self.id = id
        self.name = name
        self.buttons = buttons
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // 默认布局 - 使用绝对坐标（基于横屏 iPhone）
    static var defaultLayout: LayoutConfig {
        LayoutConfig(
            name: "默认布局",
            buttons: [
                ButtonItem(type: .attack, label: "普攻", icon: "hand.raised.fill", colorName: "orange", size: 80, positionX: 700, positionY: 280, isDirectional: false),
                ButtonItem(type: .skill, label: "1", icon: "bolt.fill", colorName: "cyan", size: 60, positionX: 600, positionY: 320, isDirectional: true),
                ButtonItem(type: .skill, label: "2", icon: "flame.fill", colorName: "purple", size: 60, positionX: 580, positionY: 220, isDirectional: true),
                ButtonItem(type: .skill, label: "R", icon: "star.fill", colorName: "yellow", size: 70, positionX: 660, positionY: 160, isDirectional: true),
                ButtonItem(type: .skill, label: "D", icon: "sparkles", colorName: "green", size: 50, positionX: 740, positionY: 180, isDirectional: false),
            ]
        )
    }
}

// MARK: - 配置管理器
@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var layouts: [LayoutConfig] = []
    @Published var currentLayoutId: UUID?
    @Published var isEditMode = false
    @Published var showGrid = true
    @Published var gridSize: CGFloat = 20
    
    // 摇杆位置
    @Published var joystickX: CGFloat = 120
    @Published var joystickY: CGFloat = 250
    
    // 防烧屏和流光特效设置
    @Published var antiBurnInEnabled = true
    @Published var flowingLightEnabled = true
    
    private let layoutsKey = "savedLayouts"
    private let currentLayoutKey = "currentLayoutId"
    private let joystickXKey = "joystickX"
    private let joystickYKey = "joystickY"
    private let showGridKey = "showGrid"
    private let antiBurnInKey = "antiBurnInEnabled"
    private let flowingLightKey = "flowingLightEnabled"
    
    var currentLayout: LayoutConfig? {
        get {
            layouts.first { $0.id == currentLayoutId }
        }
        set {
            if let newValue = newValue, let index = layouts.firstIndex(where: { $0.id == newValue.id }) {
                layouts[index] = newValue
                layouts[index].updatedAt = Date()
                saveLayouts()
            }
        }
    }
    
    init() {
        loadLayouts()
    }
    
    func loadLayouts() {
        if let data = UserDefaults.standard.data(forKey: layoutsKey),
           let decoded = try? JSONDecoder().decode([LayoutConfig].self, from: data) {
            layouts = decoded
        }
        
        if layouts.isEmpty {
            layouts = [LayoutConfig.defaultLayout]
        }
        
        if let savedId = UserDefaults.standard.string(forKey: currentLayoutKey),
           let uuid = UUID(uuidString: savedId) {
            currentLayoutId = uuid
        }
        
        if currentLayoutId == nil || !layouts.contains(where: { $0.id == currentLayoutId }) {
            currentLayoutId = layouts.first?.id
        }
        
        // 加载摇杆位置
        if UserDefaults.standard.object(forKey: joystickXKey) != nil {
            joystickX = UserDefaults.standard.double(forKey: joystickXKey)
            joystickY = UserDefaults.standard.double(forKey: joystickYKey)
        }
        
        // 加载网格设置
        if UserDefaults.standard.object(forKey: showGridKey) != nil {
            showGrid = UserDefaults.standard.bool(forKey: showGridKey)
        }
        
        // 加载防烧屏和流光设置
        if UserDefaults.standard.object(forKey: antiBurnInKey) != nil {
            antiBurnInEnabled = UserDefaults.standard.bool(forKey: antiBurnInKey)
        }
        if UserDefaults.standard.object(forKey: flowingLightKey) != nil {
            flowingLightEnabled = UserDefaults.standard.bool(forKey: flowingLightKey)
        }
    }
    
    func saveDisplaySettings() {
        UserDefaults.standard.set(antiBurnInEnabled, forKey: antiBurnInKey)
        UserDefaults.standard.set(flowingLightEnabled, forKey: flowingLightKey)
    }
    
    func saveLayouts() {
        if let encoded = try? JSONEncoder().encode(layouts) {
            UserDefaults.standard.set(encoded, forKey: layoutsKey)
        }
        if let id = currentLayoutId {
            UserDefaults.standard.set(id.uuidString, forKey: currentLayoutKey)
        }
    }
    
    func saveJoystickPosition() {
        UserDefaults.standard.set(joystickX, forKey: joystickXKey)
        UserDefaults.standard.set(joystickY, forKey: joystickYKey)
    }
    
    func saveGridSetting() {
        UserDefaults.standard.set(showGrid, forKey: showGridKey)
    }
    
    func snapToGrid(_ value: CGFloat) -> CGFloat {
        showGrid ? round(value / gridSize) * gridSize : value
    }
    
    func createLayout(name: String) {
        let newLayout = LayoutConfig(name: name)
        layouts.append(newLayout)
        currentLayoutId = newLayout.id
        saveLayouts()
    }
    
    func duplicateLayout(_ layout: LayoutConfig) {
        var newLayout = layout
        newLayout.id = UUID()
        newLayout.name = "\(layout.name) 副本"
        newLayout.createdAt = Date()
        newLayout.updatedAt = Date()
        layouts.append(newLayout)
        currentLayoutId = newLayout.id
        saveLayouts()
    }
    
    func deleteLayout(_ layout: LayoutConfig) {
        layouts.removeAll { $0.id == layout.id }
        if currentLayoutId == layout.id {
            currentLayoutId = layouts.first?.id
        }
        if layouts.isEmpty {
            layouts = [LayoutConfig.defaultLayout]
            currentLayoutId = layouts.first?.id
        }
        saveLayouts()
    }
    
    func switchLayout(to id: UUID) {
        currentLayoutId = id
        saveLayouts()
    }
    
    func addButton(to layoutId: UUID, button: ButtonItem) {
        if let index = layouts.firstIndex(where: { $0.id == layoutId }) {
            layouts[index].buttons.append(button)
            layouts[index].updatedAt = Date()
            saveLayouts()
        }
    }
    
    func updateButton(_ button: ButtonItem, in layoutId: UUID) {
        if let layoutIndex = layouts.firstIndex(where: { $0.id == layoutId }),
           let buttonIndex = layouts[layoutIndex].buttons.firstIndex(where: { $0.id == button.id }) {
            layouts[layoutIndex].buttons[buttonIndex] = button
            layouts[layoutIndex].updatedAt = Date()
            saveLayouts()
        }
    }
    
    func deleteButton(_ buttonId: UUID, from layoutId: UUID) {
        if let index = layouts.firstIndex(where: { $0.id == layoutId }) {
            layouts[index].buttons.removeAll { $0.id == buttonId }
            layouts[index].updatedAt = Date()
            saveLayouts()
        }
    }
}
