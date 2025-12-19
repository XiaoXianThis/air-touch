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

// MARK: - 修饰键
struct ModifierKeys: Codable, Equatable {
    var shift: Bool = false
    var control: Bool = false
    var alt: Bool = false      // Option on macOS
    var command: Bool = false  // Meta/Win key
    
    var isEmpty: Bool {
        !shift && !control && !alt && !command
    }
    
    var displayString: String {
        var parts: [String] = []
        if control { parts.append("Ctrl") }
        if alt { parts.append("Alt") }
        if shift { parts.append("Shift") }
        if command { parts.append("Cmd") }
        return parts.joined(separator: "+")
    }
}

// MARK: - 特殊按键
enum SpecialKey: String, Codable, CaseIterable {
    case none = ""
    // 鼠标按键
    case mouseLeft = "mouse_left"
    case mouseRight = "mouse_right"
    case mouseMiddle = "mouse_middle"
    case mouseBack = "mouse_back"       // 鼠标侧键（后退）
    case mouseForward = "mouse_forward" // 鼠标侧键（前进）
    case scrollUp = "scroll_up"
    case scrollDown = "scroll_down"
    // 修饰键（左）
    case leftShift = "lshift"
    case leftControl = "lctrl"
    case leftAlt = "lalt"
    case leftCommand = "lcmd"       // macOS Command / Windows Win
    // 修饰键（右）
    case rightShift = "rshift"
    case rightControl = "rctrl"
    case rightAlt = "ralt"
    case rightCommand = "rcmd"
    // 常用键
    case space = "space"
    case enter = "enter"
    case tab = "tab"
    case escape = "escape"
    case backspace = "backspace"
    case delete = "delete"
    case capsLock = "capslock"
    // 方向键
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
    // 导航键
    case home = "home"
    case end = "end"
    case pageUp = "pageup"
    case pageDown = "pagedown"
    // 功能键
    case f1 = "f1"
    case f2 = "f2"
    case f3 = "f3"
    case f4 = "f4"
    case f5 = "f5"
    case f6 = "f6"
    case f7 = "f7"
    case f8 = "f8"
    case f9 = "f9"
    case f10 = "f10"
    case f11 = "f11"
    case f12 = "f12"
    // 小键盘
    case numpad0 = "num0"
    case numpad1 = "num1"
    case numpad2 = "num2"
    case numpad3 = "num3"
    case numpad4 = "num4"
    case numpad5 = "num5"
    case numpad6 = "num6"
    case numpad7 = "num7"
    case numpad8 = "num8"
    case numpad9 = "num9"
    case numpadAdd = "numadd"
    case numpadSubtract = "numsub"
    case numpadMultiply = "nummul"
    case numpadDivide = "numdiv"
    case numpadDecimal = "numdec"
    case numpadEnter = "numenter"

    var displayName: String {
        switch self {
        case .none: return "无"
        // 鼠标
        case .mouseLeft: return "鼠标左键"
        case .mouseRight: return "鼠标右键"
        case .mouseMiddle: return "鼠标中键"
        case .mouseBack: return "鼠标后退"
        case .mouseForward: return "鼠标前进"
        case .scrollUp: return "滚轮↑"
        case .scrollDown: return "滚轮↓"
        // 修饰键（左）
        case .leftShift: return "左Shift"
        case .leftControl: return "左Ctrl"
        case .leftAlt: return "左Alt"
        case .leftCommand: return "左Cmd"
        // 修饰键（右）
        case .rightShift: return "右Shift"
        case .rightControl: return "右Ctrl"
        case .rightAlt: return "右Alt"
        case .rightCommand: return "右Cmd"
        // 常用键
        case .space: return "空格"
        case .enter: return "回车"
        case .tab: return "Tab"
        case .escape: return "Esc"
        case .backspace: return "退格"
        case .delete: return "Delete"
        case .capsLock: return "CapsLock"
        // 方向键
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        // 导航键
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        // 功能键
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        // 小键盘
        case .numpad0: return "Num0"
        case .numpad1: return "Num1"
        case .numpad2: return "Num2"
        case .numpad3: return "Num3"
        case .numpad4: return "Num4"
        case .numpad5: return "Num5"
        case .numpad6: return "Num6"
        case .numpad7: return "Num7"
        case .numpad8: return "Num8"
        case .numpad9: return "Num9"
        case .numpadAdd: return "Num+"
        case .numpadSubtract: return "Num-"
        case .numpadMultiply: return "Num*"
        case .numpadDivide: return "Num/"
        case .numpadDecimal: return "Num."
        case .numpadEnter: return "NumEnter"
        }
    }

    var isMouse: Bool {
        switch self {
        case .mouseLeft, .mouseRight, .mouseMiddle, .mouseBack, .mouseForward, .scrollUp, .scrollDown:
            return true
        default:
            return false
        }
    }
}

// MARK: - 按键绑定配置
struct KeyBindingConfig: Codable, Equatable {
    var key: String = ""           // 普通按键 (a-z, 0-9 等)
    var specialKey: SpecialKey = .none  // 特殊按键
    var modifiers: ModifierKeys = ModifierKeys()
    
    var isEmpty: Bool {
        key.isEmpty && specialKey == .none
    }
    
    var displayString: String {
        var parts: [String] = []
        
        if !modifiers.isEmpty {
            parts.append(modifiers.displayString)
        }
        
        if specialKey != .none {
            parts.append(specialKey.displayName)
        } else if !key.isEmpty {
            parts.append(key.uppercased())
        }
        
        return parts.isEmpty ? "未绑定" : parts.joined(separator: "+")
    }
    
    // 获取实际发送的按键值
    var effectiveKey: String {
        if specialKey != .none {
            return specialKey.rawValue
        }
        return key
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
    var keyBinding: String?  // 旧版兼容：简单按键绑定
    var keyBindingConfig: KeyBindingConfig?  // 新版：完整按键配置
    
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
        keyBinding: String? = nil,
        keyBindingConfig: KeyBindingConfig? = nil
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
        self.keyBindingConfig = keyBindingConfig
    }
    
    // 获取有效的按键配置（兼容旧版）
    var effectiveKeyConfig: KeyBindingConfig? {
        if let config = keyBindingConfig, !config.isEmpty {
            return config
        }
        if let key = keyBinding, !key.isEmpty {
            return KeyBindingConfig(key: key)
        }
        return nil
    }
    
    // 显示用的按键字符串
    var keyDisplayString: String {
        if let config = effectiveKeyConfig {
            return config.displayString
        }
        return "未绑定"
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
                ButtonItem(type: .attack, label: "普攻", icon: "hand.raised.fill", colorName: "orange", size: 80, positionX: 700, positionY: 280, isDirectional: false, keyBindingConfig: KeyBindingConfig(key: "j")),
                ButtonItem(type: .skill, label: "1", icon: "bolt.fill", colorName: "cyan", size: 60, positionX: 600, positionY: 320, isDirectional: true, keyBindingConfig: KeyBindingConfig(key: "q")),
                ButtonItem(type: .skill, label: "2", icon: "flame.fill", colorName: "purple", size: 60, positionX: 580, positionY: 220, isDirectional: true, keyBindingConfig: KeyBindingConfig(key: "e")),
                ButtonItem(type: .skill, label: "R", icon: "star.fill", colorName: "yellow", size: 70, positionX: 660, positionY: 160, isDirectional: true, keyBindingConfig: KeyBindingConfig(key: "r")),
                ButtonItem(type: .skill, label: "D", icon: "sparkles", colorName: "green", size: 50, positionX: 740, positionY: 180, isDirectional: false, keyBindingConfig: KeyBindingConfig(key: "d")),
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
    @Published var gridSize: CGFloat = 20  // 网格大小 10-50
    
    // 摇杆位置
    @Published var joystickX: CGFloat = 120
    @Published var joystickY: CGFloat = 250
    
    // 防烧屏和流光特效设置
    @Published var antiBurnInEnabled = true
    @Published var flowingLightEnabled = true
    
    // 平滑鼠标移动设置
    @Published var smoothMouseEnabled = true
    @Published var smoothMouseFactor: Double = 0.3  // 平滑系数 0.1-0.5，越小越平滑
    
    // 原点偏移设置
    @Published var originOffsetX: Int = 0  // 水平偏移（像素）
    @Published var originOffsetY: Int = 0  // 垂直偏移（像素）
    
    private let layoutsKey = "savedLayouts"
    private let currentLayoutKey = "currentLayoutId"
    private let joystickXKey = "joystickX"
    private let joystickYKey = "joystickY"
    private let showGridKey = "showGrid"
    private let gridSizeKey = "gridSize"
    private let antiBurnInKey = "antiBurnInEnabled"
    private let flowingLightKey = "flowingLightEnabled"
    private let smoothMouseKey = "smoothMouseEnabled"
    private let smoothMouseFactorKey = "smoothMouseFactor"
    private let originOffsetXKey = "originOffsetX"
    private let originOffsetYKey = "originOffsetY"
    
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
        if UserDefaults.standard.object(forKey: gridSizeKey) != nil {
            gridSize = UserDefaults.standard.double(forKey: gridSizeKey)
        }
        
        // 加载防烧屏和流光设置
        if UserDefaults.standard.object(forKey: antiBurnInKey) != nil {
            antiBurnInEnabled = UserDefaults.standard.bool(forKey: antiBurnInKey)
        }
        if UserDefaults.standard.object(forKey: flowingLightKey) != nil {
            flowingLightEnabled = UserDefaults.standard.bool(forKey: flowingLightKey)
        }
        
        // 加载平滑鼠标设置
        if UserDefaults.standard.object(forKey: smoothMouseKey) != nil {
            smoothMouseEnabled = UserDefaults.standard.bool(forKey: smoothMouseKey)
        }
        if UserDefaults.standard.object(forKey: smoothMouseFactorKey) != nil {
            smoothMouseFactor = UserDefaults.standard.double(forKey: smoothMouseFactorKey)
        }
        
        // 加载原点偏移设置
        if UserDefaults.standard.object(forKey: originOffsetXKey) != nil {
            originOffsetX = UserDefaults.standard.integer(forKey: originOffsetXKey)
        }
        if UserDefaults.standard.object(forKey: originOffsetYKey) != nil {
            originOffsetY = UserDefaults.standard.integer(forKey: originOffsetYKey)
        }
    }
    
    func saveDisplaySettings() {
        UserDefaults.standard.set(antiBurnInEnabled, forKey: antiBurnInKey)
        UserDefaults.standard.set(flowingLightEnabled, forKey: flowingLightKey)
        UserDefaults.standard.set(smoothMouseEnabled, forKey: smoothMouseKey)
        UserDefaults.standard.set(smoothMouseFactor, forKey: smoothMouseFactorKey)
        UserDefaults.standard.set(originOffsetX, forKey: originOffsetXKey)
        UserDefaults.standard.set(originOffsetY, forKey: originOffsetYKey)
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
        UserDefaults.standard.set(gridSize, forKey: gridSizeKey)
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
