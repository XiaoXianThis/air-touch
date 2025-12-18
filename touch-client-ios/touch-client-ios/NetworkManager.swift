//
//  NetworkManager.swift
//  touch-client-ios
//
//  Created by Kiro on 2025/12/18.
//

import Combine
import Foundation
import Network

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
}

struct PingMessage: Codable {
    let type: String
    let timestamp: UInt64
}

struct PongMessage: Codable {
    let type: String
    let timestamp: UInt64
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

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "udp.queue", qos: .userInteractive)
    private let encoder = JSONEncoder()
    private var heartbeatTimer: Timer?
    private var lastPongTime: Date = Date()
    private let heartbeatInterval: TimeInterval = 1.0
    private let heartbeatTimeout: TimeInterval = 3.0

    private let serverIPKey = "serverIP"
    private let serverPortKey = "serverPort"

    init() {
        loadSettings()
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
                case .failed(let error):
                    self?.isConnected = false
                    self?.connectionStatus = "连接失败: \(error.localizedDescription)"
                    self?.stopHeartbeat()
                case .cancelled:
                    self?.isConnected = false
                    self?.connectionStatus = "已断开"
                    self?.stopHeartbeat()
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
        connection?.cancel()
        connection = nil
        isConnected = false
        connectionStatus = "已断开"
        latency = 0
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
        let message = PingMessage(type: "ping", timestamp: timestamp)
        guard let data = try? encoder.encode(message) else { return }

        connection.send(content: data, completion: .contentProcessed { _ in })
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

            if let data = content,
               let pong = try? JSONDecoder().decode(PongMessage.self, from: data),
               pong.type == "pong"
            {
                let now = UInt64(Date().timeIntervalSince1970 * 1000)
                let rtt = Int(now - pong.timestamp)

                Task { @MainActor in
                    self.latency = rtt
                    self.lastPongTime = Date()
                    if !self.isConnected {
                        self.isConnected = true
                        self.connectionStatus = "已连接"
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

        let message = JoystickMessage(x: x, y: y)
        guard let data = try? encoder.encode(message) else { return }

        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - 发送按键数据
    func sendButton(key: String, pressed: Bool) {
        guard isConnected, let connection = connection else { return }

        let message = ButtonMessage(key: key, pressed: pressed)
        guard let data = try? encoder.encode(message) else { return }

        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
