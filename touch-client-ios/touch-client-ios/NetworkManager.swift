//
//  NetworkManager.swift
//  touch-client-ios
//
//  Created by Kiro on 2025/12/18.
//

import Combine
import Foundation
import Network

// MARK: - 发现的服务器
struct DiscoveredServer: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 输入消息类型
struct JoystickMessage: Codable {
    let type: String = "joystick"
    let x: Float
    let y: Float
}

struct ButtonMessage: Codable {
    let type: String = "button"
    let key: String
    let pressed: Bool
    let modifiers: ModifiersPayload?
}

struct ModifiersPayload: Codable {
    let shift: Bool
    let control: Bool
    let alt: Bool
    let command: Bool
    
    init(from modifiers: ModifierKeys) {
        self.shift = modifiers.shift
        self.control = modifiers.control
        self.alt = modifiers.alt
        self.command = modifiers.command
    }
}

struct SkillStartMessage: Codable {
    let type: String = "skill_start"
    let key: String
    let offset_x: Int
    let offset_y: Int
    let modifiers: ModifiersPayload?
}

struct SkillDragMessage: Codable {
    let type: String = "skill_drag"
    let key: String
    let dx: Float   // 归一化 -1 ~ 1
    let dy: Float   // 归一化 -1 ~ 1
    let distance: Float  // 归一化 0 ~ 1
    let smooth: Bool  // 是否启用服务端平滑
}

struct SkillReleaseMessage: Codable {
    let type: String = "skill_release"
    let key: String
    let dx: Float
    let dy: Float
}

struct SkillCancelMessage: Codable {
    let type: String = "skill_cancel"
    let key: String
}

struct PingMessage: Codable {
    let type: String
    let timestamp: UInt64
}

struct PongMessage: Codable {
    let type: String
    let timestamp: UInt64
}

// MARK: - 可靠消息确认
struct AckMessage: Codable {
    let type: String
    let seq: UInt32
}

// MARK: - 极限模式二进制协议
enum BinaryProtocol {
    static let magic: UInt8 = 0xAB
    static let msgJoystick: UInt8 = 0x01
    static let msgButton: UInt8 = 0x02
    static let msgSkillStart: UInt8 = 0x03
    static let msgSkillDrag: UInt8 = 0x04
    static let msgSkillRelease: UInt8 = 0x05
    static let msgSkillCancel: UInt8 = 0x06
    static let msgPing: UInt8 = 0x07
    static let msgPong: UInt8 = 0x08
    static let msgAck: UInt8 = 0x09
    // 可靠消息类型（带序列号，需要ACK）
    static let msgReliableButton: UInt8 = 0x12
    static let msgReliableSkillRelease: UInt8 = 0x15
    static let msgReliableSkillCancel: UInt8 = 0x16
}

// MARK: - 可靠消息重传管理
private struct PendingMessage {
    let seq: UInt32
    let data: Data
    let sendTime: Date
    var retryCount: Int
}

// MARK: - 网络管理器
@MainActor
class NetworkManager: ObservableObject {
    @MainActor static let shared = NetworkManager()

    @Published var isConnected = false
    @Published var serverIP: String = ""
    @Published var serverPort: UInt16 = 9527
    @Published var connectionStatus: String = "未连接"
    @Published var latency: Int = 0  // 延迟(ms)
    
    // 极限模式
    @Published var extremeMode = false {
        didSet {
            UserDefaults.standard.set(extremeMode, forKey: extremeModeKey)
        }
    }
    private let extremeModeKey = "extremeMode"
    
    // 极限模式：摇杆节流
    private var lastSentJoystickX: Float = 0
    private var lastSentJoystickY: Float = 0
    private let joystickThreshold: Float = 0.02  // 变化超过2%才发送
    
    // mDNS 服务发现
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var isSearching = false
    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "mdns.browser.queue")

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "udp.queue", qos: .userInteractive)
    private let encoder = JSONEncoder()
    private var heartbeatTimer: Timer?
    private var lastPongTime: Date = Date()
    private let heartbeatInterval: TimeInterval = 1.0
    private let heartbeatTimeout: TimeInterval = 3.0

    private let serverIPKey = "serverIP"
    private let serverPortKey = "serverPort"
    
    // 可靠消息传递
    private var messageSeq: UInt32 = 0
    private var pendingMessages: [UInt32: PendingMessage] = [:]
    private var retryTimer: Timer?
    private let maxRetries = 5
    private let retryInterval: TimeInterval = 0.05  // 50ms 重试间隔
    private let pendingLock = NSLock()

    init() {
        loadSettings()
        extremeMode = UserDefaults.standard.bool(forKey: extremeModeKey)
    }
    
    // MARK: - mDNS 服务发现
    func startBrowsing() {
        stopBrowsing()
        discoveredServers = []
        isSearching = true
        
        // 注意：type 不要带 .local. 后缀
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_touchserver._udp.", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: descriptor, using: params)
        
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[mDNS] 浏览器就绪，开始搜索...")
                case .failed(let error):
                    print("[mDNS] 浏览器失败: \(error)")
                    self?.isSearching = false
                case .cancelled:
                    print("[mDNS] 浏览器已取消")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            print("[mDNS] 发现 \(results.count) 个服务")
            for result in results {
                print("[mDNS] 服务: \(result.endpoint)")
            }
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }
        
        browser?.start(queue: browserQueue)
    }
    
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        // 清空旧的，重新解析
        var pendingServers: [String: DiscoveredServer] = [:]
        
        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                let serverId = "\(name).\(type)\(domain)"
                
                // 先添加占位服务器（显示名称，等待解析IP）
                let tempServer = DiscoveredServer(
                    id: serverId,
                    name: name,
                    host: "",
                    port: 9527
                )
                pendingServers[serverId] = tempServer
                
                // 解析服务获取 IP 和端口
                resolveService(name: name, type: type, domain: domain) { [weak self] server in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if let server = server {
                            // 更新或添加已解析的服务器
                            if let index = self.discoveredServers.firstIndex(where: { $0.id == server.id }) {
                                self.discoveredServers[index] = server
                            } else {
                                self.discoveredServers.append(server)
                            }
                        }
                    }
                }
            }
        }
        
        // 先显示占位服务器
        for (id, server) in pendingServers {
            if !discoveredServers.contains(where: { $0.id == id }) {
                discoveredServers.append(server)
            }
        }
        
        // 移除不再存在的服务器
        let validIds = Set(pendingServers.keys)
        discoveredServers.removeAll { !validIds.contains($0.id) }
    }
    
    private func resolveService(name: String, type: String, domain: String, completion: @escaping (DiscoveredServer?) -> Void) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let params = NWParameters.udp
        let connection = NWConnection(to: endpoint, using: params)
        
        connection.stateUpdateHandler = { [name, type, domain] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        hostString = "\(addr)"
                    case .ipv6(let addr):
                        // 跳过 IPv6 link-local 地址
                        let addrStr = "\(addr)"
                        if addrStr.hasPrefix("fe80") {
                            connection.cancel()
                            completion(nil)
                            return
                        }
                        hostString = addrStr
                    case .name(let hostname, _):
                        hostString = hostname
                    @unknown default:
                        hostString = ""
                    }
                    
                    print("[mDNS] 解析成功: \(name) -> \(hostString):\(port.rawValue)")
                    
                    let server = DiscoveredServer(
                        id: "\(name).\(type)\(domain)",
                        name: name,
                        host: hostString,
                        port: port.rawValue
                    )
                    completion(server)
                } else {
                    completion(nil)
                }
                connection.cancel()
                
            case .failed(let error):
                print("[mDNS] 解析失败: \(name) - \(error)")
                completion(nil)
                connection.cancel()
                
            case .waiting(let error):
                print("[mDNS] 等待中: \(name) - \(error)")
                
            default:
                break
            }
        }
        
        connection.start(queue: browserQueue)
        
        // 超时处理
        browserQueue.asyncAfter(deadline: .now() + 5) {
            if connection.state != .cancelled && connection.state != .ready {
                print("[mDNS] 解析超时: \(name)")
                connection.cancel()
                completion(nil)
            }
        }
    }
    
    func connectToServer(_ server: DiscoveredServer) {
        guard !server.host.isEmpty else {
            connectionStatus = "服务器地址解析中..."
            return
        }
        serverIP = server.host
        serverPort = server.port
        stopBrowsing()
        connect()
    }

    func loadSettings() {
        if let ip = UserDefaults.standard.string(forKey: serverIPKey) {
            serverIP = ip
        }
        let port = UserDefaults.standard.integer(forKey: serverPortKey)
        if port > 0 {
            serverPort = UInt16(port)
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(serverIP, forKey: serverIPKey)
        UserDefaults.standard.set(Int(serverPort), forKey: serverPortKey)
    }

    func connect() {
        guard !serverIP.isEmpty else {
            connectionStatus = "请输入服务器IP"
            return
        }

        disconnect()
        saveSettings()

        let host = NWEndpoint.Host(serverIP)
        let port = NWEndpoint.Port(rawValue: serverPort)!

        let params = NWParameters.udp
        params.serviceClass = .interactiveVideo

        connection = NWConnection(host: host, port: port, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.connectionStatus = "已连接"
                    self?.lastPongTime = Date()
                    self?.startHeartbeat()
                    self?.startReceiving()
                    self?.startRetryTimer()
                case .failed(let error):
                    self?.isConnected = false
                    self?.connectionStatus = "连接失败: \(error.localizedDescription)"
                    self?.stopHeartbeat()
                    self?.stopRetryTimer()
                case .cancelled:
                    self?.isConnected = false
                    self?.connectionStatus = "已断开"
                    self?.stopHeartbeat()
                    self?.stopRetryTimer()
                case .waiting(let error):
                    self?.connectionStatus = "等待中: \(error.localizedDescription)"
                default:
                    break
                }
            }
        }

        connection?.start(queue: queue)
        connectionStatus = "连接中..."
    }

    func disconnect() {
        stopHeartbeat()
        stopRetryTimer()
        clearPendingMessages()
        connection?.cancel()
        connection = nil
        isConnected = false
        connectionStatus = "已断开"
        latency = 0
    }
    
    // MARK: - 可靠消息重传机制
    private func startRetryTimer() {
        stopRetryTimer()
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: true) { [weak self] _ in
            self?.retryPendingMessages()
        }
    }
    
    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    private func clearPendingMessages() {
        pendingLock.lock()
        pendingMessages.removeAll()
        pendingLock.unlock()
    }
    
    private func nextSeq() -> UInt32 {
        messageSeq &+= 1
        return messageSeq
    }
    
    private func sendReliable(data: Data, seq: UInt32) {
        guard let connection = connection else { return }
        
        pendingLock.lock()
        pendingMessages[seq] = PendingMessage(seq: seq, data: data, sendTime: Date(), retryCount: 0)
        pendingLock.unlock()
        
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
    
    private func retryPendingMessages() {
        guard let connection = connection, isConnected else { return }
        
        pendingLock.lock()
        let now = Date()
        var toRemove: [UInt32] = []
        
        for (seq, var msg) in pendingMessages {
            if msg.retryCount >= maxRetries {
                toRemove.append(seq)
                print("[可靠消息] seq=\(seq) 重试次数耗尽，放弃")
                continue
            }
            
            // 检查是否需要重传（超过重试间隔）
            if now.timeIntervalSince(msg.sendTime) >= retryInterval * Double(msg.retryCount + 1) {
                msg.retryCount += 1
                pendingMessages[seq] = msg
                connection.send(content: msg.data, completion: .contentProcessed { _ in })
            }
        }
        
        for seq in toRemove {
            pendingMessages.removeValue(forKey: seq)
        }
        pendingLock.unlock()
    }
    
    private func handleAck(seq: UInt32) {
        pendingLock.lock()
        pendingMessages.removeValue(forKey: seq)
        pendingLock.unlock()
    }

    // MARK: - 心跳机制
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
                self?.checkHeartbeatTimeout()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendPing() {
        guard isConnected, let connection = connection else { return }

        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        if extremeMode {
            // 二进制格式: [magic][type][timestamp:u64] = 10 bytes
            var data = Data(capacity: 10)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgPing)
            withUnsafeBytes(of: timestamp.littleEndian) { data.append(contentsOf: $0) }
            connection.send(content: data, completion: .contentProcessed { _ in })
        } else {
            let message = PingMessage(type: "ping", timestamp: timestamp)
            guard let data = try? encoder.encode(message) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func checkHeartbeatTimeout() {
        let elapsed = Date().timeIntervalSince(lastPongTime)
        if elapsed > heartbeatTimeout {
            connectionStatus = "连接超时"
            isConnected = false
            // 不断开连接，继续尝试
        }
    }

    // MARK: - 接收数据
    private func startReceiving() {
        receiveNext()
    }

    private func receiveNext() {
        connection?.receiveMessage { [weak self] content, _, _, error in
            guard let self = self else { return }

            if let data = content {
                var timestamp: UInt64?
                
                // 尝试解析二进制 ACK
                if data.count >= 6 && data[0] == BinaryProtocol.magic && data[1] == BinaryProtocol.msgAck {
                    let seq = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
                    Task { @MainActor in
                        self.handleAck(seq: seq)
                    }
                }
                // 尝试解析二进制 pong
                else if data.count >= 10 && data[0] == BinaryProtocol.magic && data[1] == BinaryProtocol.msgPong {
                    timestamp = data.subdata(in: 2..<10).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
                }
                // 尝试解析 JSON ACK
                else if let ack = try? JSONDecoder().decode(AckMessage.self, from: data), ack.type == "ack" {
                    Task { @MainActor in
                        self.handleAck(seq: ack.seq)
                    }
                }
                // 尝试解析 JSON pong
                else if let pong = try? JSONDecoder().decode(PongMessage.self, from: data), pong.type == "pong" {
                    timestamp = pong.timestamp
                }
                
                if let ts = timestamp {
                    let now = UInt64(Date().timeIntervalSince1970 * 1000)
                    let rtt = Int(now - ts)

                    Task { @MainActor in
                        self.latency = rtt
                        self.lastPongTime = Date()
                        if !self.isConnected {
                            self.isConnected = true
                            self.connectionStatus = "已连接"
                        }
                    }
                }
            }

            if error == nil {
                self.receiveNext()
            }
        }
    }

    // MARK: - 发送摇杆数据
    func sendJoystick(x: Float, y: Float) {
        guard isConnected, let connection = connection else { return }
        
        if extremeMode {
            // 极限模式：节流，只在变化超过阈值时发送
            let dx = abs(x - lastSentJoystickX)
            let dy = abs(y - lastSentJoystickY)
            let isZero = (x == 0 && y == 0)
            let wasZero = (lastSentJoystickX == 0 && lastSentJoystickY == 0)
            if dx < joystickThreshold && dy < joystickThreshold && (!isZero || wasZero) {
                return
            }
            lastSentJoystickX = x
            lastSentJoystickY = y
            
            // 二进制格式: [magic][type][x:f32][y:f32] = 10 bytes
            var data = Data(capacity: 10)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgJoystick)
            withUnsafeBytes(of: x.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: y.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            connection.send(content: data, completion: .contentProcessed { _ in })
        } else {
            let message = JoystickMessage(x: x, y: y)
            guard let data = try? encoder.encode(message) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - 发送按键数据（可靠传输）
    func sendButton(key: String, pressed: Bool, modifiers: ModifierKeys? = nil) {
        guard isConnected else { return }

        let seq = nextSeq()
        
        if extremeMode {
            // 可靠二进制格式: [magic][type][seq:u32][key_len:u8][key:bytes][pressed:u8][modifiers:u8]
            let keyData = key.data(using: .utf8) ?? Data()
            var data = Data(capacity: 8 + keyData.count)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgReliableButton)
            withUnsafeBytes(of: seq.littleEndian) { data.append(contentsOf: $0) }
            data.append(UInt8(min(keyData.count, 255)))
            data.append(keyData)
            data.append(pressed ? 1 : 0)
            var modByte: UInt8 = 0
            if let m = modifiers {
                if m.shift { modByte |= 0x01 }
                if m.control { modByte |= 0x02 }
                if m.alt { modByte |= 0x04 }
                if m.command { modByte |= 0x08 }
            }
            data.append(modByte)
            sendReliable(data: data, seq: seq)
        } else {
            // JSON 格式添加 seq 字段
            let modPayload = modifiers.map { ModifiersPayload(from: $0) }
            var dict: [String: Any] = [
                "type": "button",
                "key": key,
                "pressed": pressed,
                "seq": seq
            ]
            if let mp = modPayload {
                dict["modifiers"] = [
                    "shift": mp.shift,
                    "control": mp.control,
                    "alt": mp.alt,
                    "command": mp.command
                ]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
            sendReliable(data: data, seq: seq)
        }
    }
    
    // 便捷方法：使用 KeyBindingConfig 发送按键
    func sendButton(config: KeyBindingConfig, pressed: Bool) {
        let key = config.effectiveKey
        guard !key.isEmpty else { return }
        sendButton(key: key, pressed: pressed, modifiers: config.modifiers.isEmpty ? nil : config.modifiers)
    }
    
    // MARK: - 发送技能开始
    func sendSkillStart(key: String, offsetX: Int = 0, offsetY: Int = 0, modifiers: ModifierKeys? = nil) {
        guard isConnected, let connection = connection else { return }
        
        if extremeMode {
            // 二进制格式: [magic][type][key_len:u8][key:bytes][modifiers:u8]
            let keyData = key.data(using: .utf8) ?? Data()
            var data = Data(capacity: 4 + keyData.count)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgSkillStart)
            data.append(UInt8(min(keyData.count, 255)))
            data.append(keyData)
            var modByte: UInt8 = 0
            if let m = modifiers {
                if m.shift { modByte |= 0x01 }
                if m.control { modByte |= 0x02 }
                if m.alt { modByte |= 0x04 }
                if m.command { modByte |= 0x08 }
            }
            data.append(modByte)
            connection.send(content: data, completion: .contentProcessed { _ in })
        } else {
            let modPayload = modifiers.map { ModifiersPayload(from: $0) }
            let message = SkillStartMessage(key: key, offset_x: offsetX, offset_y: offsetY, modifiers: modPayload)
            guard let data = try? encoder.encode(message) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }
    
    // 便捷方法：使用 KeyBindingConfig 发送技能开始
    func sendSkillStart(config: KeyBindingConfig, offsetX: Int = 0, offsetY: Int = 0) {
        let key = config.effectiveKey
        guard !key.isEmpty else { return }
        sendSkillStart(key: key, offsetX: offsetX, offsetY: offsetY, modifiers: config.modifiers.isEmpty ? nil : config.modifiers)
    }
    
    // MARK: - 发送技能拖动（实时鼠标位置）
    func sendSkillDrag(key: String, dx: Float, dy: Float, distance: Float, smooth: Bool = true) {
        guard isConnected, let connection = connection else { return }
        
        if extremeMode {
            // 二进制格式: [magic][type][key:u8][dx:f32][dy:f32][distance:f32][smooth:u8] = 16 bytes
            var data = Data(capacity: 16)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgSkillDrag)
            data.append(key.first?.asciiValue ?? 0)
            withUnsafeBytes(of: dx.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: dy.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: distance.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            data.append(smooth ? 1 : 0)
            connection.send(content: data, completion: .contentProcessed { _ in })
        } else {
            let message = SkillDragMessage(key: key, dx: dx, dy: dy, distance: distance, smooth: smooth)
            guard let data = try? encoder.encode(message) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }
    
    // MARK: - 发送技能释放（可靠传输）
    func sendSkillRelease(key: String, dx: Float, dy: Float) {
        guard isConnected else { return }
        
        let seq = nextSeq()
        
        if extremeMode {
            // 可靠二进制格式: [magic][type][seq:u32][key:u8][dx:f32][dy:f32] = 15 bytes
            var data = Data(capacity: 15)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgReliableSkillRelease)
            withUnsafeBytes(of: seq.littleEndian) { data.append(contentsOf: $0) }
            data.append(key.first?.asciiValue ?? 0)
            withUnsafeBytes(of: dx.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: dy.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            sendReliable(data: data, seq: seq)
        } else {
            let dict: [String: Any] = [
                "type": "skill_release",
                "key": key,
                "dx": dx,
                "dy": dy,
                "seq": seq
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
            sendReliable(data: data, seq: seq)
        }
    }
    
    // MARK: - 发送技能取消（可靠传输）
    func sendSkillCancel(key: String) {
        guard isConnected else { return }
        
        let seq = nextSeq()
        
        if extremeMode {
            // 可靠二进制格式: [magic][type][seq:u32][key:u8] = 7 bytes
            var data = Data(capacity: 7)
            data.append(BinaryProtocol.magic)
            data.append(BinaryProtocol.msgReliableSkillCancel)
            withUnsafeBytes(of: seq.littleEndian) { data.append(contentsOf: $0) }
            data.append(key.first?.asciiValue ?? 0)
            sendReliable(data: data, seq: seq)
        } else {
            let dict: [String: Any] = [
                "type": "skill_cancel",
                "key": key,
                "seq": seq
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
            sendReliable(data: data, seq: seq)
        }
    }
}
