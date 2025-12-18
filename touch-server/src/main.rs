use enigo::{Enigo, Key, Keyboard, Settings};
use local_ip_address::local_ip;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::net::UdpSocket;
use std::sync::{Arc, Mutex};
use std::time::Instant;

const PORT: u16 = 9527;
const DEADZONE: f32 = 0.2;
const HEARTBEAT_TIMEOUT_SECS: u64 = 3;

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum InputMessage {
    #[serde(rename = "joystick")]
    Joystick { x: f32, y: f32 },
    #[serde(rename = "button")]
    Button { key: String, pressed: bool },
    #[serde(rename = "ping")]
    Ping { timestamp: u64 },
}

#[derive(Debug, Serialize)]
struct PongMessage {
    r#type: &'static str,
    timestamp: u64,
}

struct KeyState {
    pressed_keys: HashSet<char>,
    enigo: Enigo,
}

impl KeyState {
    fn new() -> Self {
        Self {
            pressed_keys: HashSet::new(),
            enigo: Enigo::new(&Settings::default()).expect("Failed to create Enigo"),
        }
    }

    fn update_key(&mut self, key: char, should_press: bool) {
        let is_pressed = self.pressed_keys.contains(&key);
        
        if should_press && !is_pressed {
            let _ = self.enigo.key(Key::Unicode(key), enigo::Direction::Press);
            self.pressed_keys.insert(key);
        } else if !should_press && is_pressed {
            let _ = self.enigo.key(Key::Unicode(key), enigo::Direction::Release);
            self.pressed_keys.remove(&key);
        }
    }

    fn handle_joystick(&mut self, x: f32, y: f32) {
        let x = if x.abs() < DEADZONE { 0.0 } else { x };
        let y = if y.abs() < DEADZONE { 0.0 } else { y };

        self.update_key('a', x < -DEADZONE);
        self.update_key('d', x > DEADZONE);
        self.update_key('w', y < -DEADZONE);
        self.update_key('s', y > DEADZONE);
    }

    fn handle_button(&mut self, key: &str, pressed: bool) {
        if let Some(c) = key.chars().next() {
            let c = c.to_ascii_lowercase();
            if pressed {
                let _ = self.enigo.key(Key::Unicode(c), enigo::Direction::Press);
                self.pressed_keys.insert(c);
            } else {
                let _ = self.enigo.key(Key::Unicode(c), enigo::Direction::Release);
                self.pressed_keys.remove(&c);
            }
        }
    }

    fn release_all(&mut self) {
        for key in self.pressed_keys.clone() {
            let _ = self.enigo.key(Key::Unicode(key), enigo::Direction::Release);
        }
        self.pressed_keys.clear();
    }
}

fn main() {
    let local_ip = local_ip().expect("Failed to get local IP");
    println!("========================================");
    println!("  Touch Server - UDP 低延迟输入服务");
    println!("========================================");
    println!("局域网 IP: {}", local_ip);
    println!("监听端口: {}", PORT);
    println!("连接地址: {}:{}", local_ip, PORT);
    println!("----------------------------------------");
    println!("摇杆映射: W(上) A(左) S(下) D(右)");
    println!("死区阈值: {:.0}%", DEADZONE * 100.0);
    println!("心跳超时: {}秒", HEARTBEAT_TIMEOUT_SECS);
    println!("========================================");
    println!("等待客户端连接...\n");

    let socket = UdpSocket::bind(format!("0.0.0.0:{}", PORT))
        .expect("Failed to bind UDP socket");
    
    socket.set_read_timeout(Some(std::time::Duration::from_secs(1))).ok();

    let key_state = Arc::new(Mutex::new(KeyState::new()));
    let mut buf = [0u8; 1024];
    let mut last_client: Option<std::net::SocketAddr> = None;
    let mut last_heartbeat = Instant::now();

    loop {
        match socket.recv_from(&mut buf) {
            Ok((len, src)) => {
                if last_client != Some(src) {
                    println!("[连接] 客户端: {}", src);
                    last_client = Some(src);
                }
                last_heartbeat = Instant::now();

                if let Ok(msg) = serde_json::from_slice::<InputMessage>(&buf[..len]) {
                    let mut state = key_state.lock().unwrap();
                    match msg {
                        InputMessage::Joystick { x, y } => {
                            state.handle_joystick(x, y);
                        }
                        InputMessage::Button { key, pressed } => {
                            state.handle_button(&key, pressed);
                            println!("[按键] {} {}", key, if pressed { "按下" } else { "释放" });
                        }
                        InputMessage::Ping { timestamp } => {
                            // 回复 pong
                            let pong = PongMessage { r#type: "pong", timestamp };
                            if let Ok(data) = serde_json::to_vec(&pong) {
                                let _ = socket.send_to(&data, src);
                            }
                        }
                    }
                }
            }
            Err(e) => {
                if e.kind() == std::io::ErrorKind::WouldBlock 
                    || e.kind() == std::io::ErrorKind::TimedOut {
                    // 检查心跳超时
                    if last_client.is_some() 
                        && last_heartbeat.elapsed().as_secs() > HEARTBEAT_TIMEOUT_SECS {
                        println!("[断开] 心跳超时，释放所有按键");
                        key_state.lock().unwrap().release_all();
                        last_client = None;
                    }
                }
            }
        }
    }
}
