use display_info::DisplayInfo;
use enigo::{Button, Coordinate, Enigo, Key, Keyboard, Mouse, Settings};
use local_ip_address::local_ip;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use mouse_position::mouse_position::Mouse as MousePos;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::net::UdpSocket;
use std::time::Instant;
use std::thread;

const PORT: u16 = 9527;
const SERVICE_TYPE: &str = "_touchserver._udp.local.";
const DEADZONE: f32 = 0.2;
const HEARTBEAT_TIMEOUT_SECS: u64 = 3;
const SKILL_MOUSE_RADIUS: i32 = 800;
const SKILL_CLICK_DELAY_MS: u64 = 50;   // 技能释放时鼠标移动后的点击延迟
const SKILL_CLICK_HOLD_MS: u64 = 100;   // 鼠标按下保持时间

// 极限模式：二进制协议消息类型
mod binary_protocol {
    pub const MSG_JOYSTICK: u8 = 0x01;
    pub const MSG_BUTTON: u8 = 0x02;
    pub const MSG_SKILL_START: u8 = 0x03;
    pub const MSG_SKILL_DRAG: u8 = 0x04;
    pub const MSG_SKILL_RELEASE: u8 = 0x05;
    pub const MSG_SKILL_CANCEL: u8 = 0x06;
    pub const MSG_PING: u8 = 0x07;
    pub const MSG_PONG: u8 = 0x08;
    pub const MSG_ACK: u8 = 0x09;
    // 可靠消息类型（带序列号，需要ACK）
    pub const MSG_RELIABLE_BUTTON: u8 = 0x12;
    pub const MSG_RELIABLE_SKILL_RELEASE: u8 = 0x15;
    pub const MSG_RELIABLE_SKILL_CANCEL: u8 = 0x16;
    pub const MAGIC: u8 = 0xAB;  // 魔数，用于识别二进制协议
}

/// 显示器信息
#[derive(Debug, Clone)]
struct Monitor {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

impl Monitor {
    fn center(&self) -> (i32, i32) {
        (
            self.x + (self.width as i32) / 2,
            self.y + (self.height as i32) / 2,
        )
    }

    fn contains(&self, x: i32, y: i32) -> bool {
        x >= self.x
            && x < self.x + self.width as i32
            && y >= self.y
            && y < self.y + self.height as i32
    }
}

/// 获取所有显示器信息
fn get_all_monitors() -> Vec<Monitor> {
    DisplayInfo::all()
        .unwrap_or_default()
        .into_iter()
        .map(|d| Monitor {
            x: d.x,
            y: d.y,
            width: d.width,
            height: d.height,
        })
        .collect()
}

/// 获取当前鼠标位置
fn get_mouse_position() -> Option<(i32, i32)> {
    match MousePos::get_mouse_position() {
        MousePos::Position { x, y } => Some((x, y)),
        MousePos::Error => None,
    }
}

/// 获取鼠标所在显示器的中心坐标
fn get_current_display_center() -> (i32, i32) {
    let monitors = get_all_monitors();
    
    if let Some((mx, my)) = get_mouse_position() {
        // 找到鼠标所在的显示器
        for monitor in &monitors {
            if monitor.contains(mx, my) {
                return monitor.center();
            }
        }
    }
    
    // 回退：使用第一个显示器或默认值
    monitors
        .first()
        .map(|m| m.center())
        .unwrap_or((960, 540))
}


/// 修饰键
#[derive(Debug, Deserialize, Default, Clone, Copy)]
struct Modifiers {
    #[serde(default)]
    shift: bool,
    #[serde(default)]
    control: bool,
    #[serde(default)]
    alt: bool,
    #[serde(default)]
    command: bool,
}

impl Modifiers {
    fn is_empty(&self) -> bool {
        !self.shift && !self.control && !self.alt && !self.command
    }
    
    fn from_byte(b: u8) -> Self {
        Modifiers {
            shift: (b & 0x01) != 0,
            control: (b & 0x02) != 0,
            alt: (b & 0x04) != 0,
            command: (b & 0x08) != 0,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum InputMessage {
    #[serde(rename = "joystick")]
    Joystick { x: f32, y: f32 },
    #[serde(rename = "button")]
    Button { key: String, pressed: bool, #[serde(default)] modifiers: Option<Modifiers>, #[serde(default)] seq: Option<u32> },
    #[serde(rename = "skill_start")]
    SkillStart { key: String, #[serde(default)] offset_x: i32, #[serde(default)] offset_y: i32, #[serde(default)] modifiers: Option<Modifiers> },
    #[serde(rename = "skill_drag")]
    SkillDrag { key: String, dx: f32, dy: f32, distance: f32, #[serde(default)] smooth: bool },
    #[serde(rename = "skill_release")]
    SkillRelease { key: String, dx: f32, dy: f32, #[serde(default)] seq: Option<u32> },
    #[serde(rename = "skill_cancel")]
    SkillCancel { key: String, #[serde(default)] seq: Option<u32> },
    #[serde(rename = "ping")]
    Ping { timestamp: u64 },
}

#[derive(Debug, Serialize)]
struct PongMessage {
    r#type: &'static str,
    timestamp: u64,
}

#[derive(Debug, Serialize)]
struct AckMessage {
    r#type: &'static str,
    seq: u32,
}

const SMOOTH_FACTOR: f32 = 0.4;  // 服务端平滑系数

// 极限模式：解析二进制消息，返回 (消息, 可选的序列号用于ACK)
fn parse_binary_message(buf: &[u8]) -> Option<(InputMessage, Option<u32>)> {
    if buf.len() < 2 || buf[0] != binary_protocol::MAGIC {
        return None;
    }
    
    match buf[1] {
        binary_protocol::MSG_JOYSTICK if buf.len() >= 10 => {
            let x = f32::from_le_bytes([buf[2], buf[3], buf[4], buf[5]]);
            let y = f32::from_le_bytes([buf[6], buf[7], buf[8], buf[9]]);
            Some((InputMessage::Joystick { x, y }, None))
        }
        binary_protocol::MSG_BUTTON if buf.len() >= 4 => {
            // 新格式: [magic][type][key_len][key...][pressed][modifiers]
            let key_len = buf[2] as usize;
            if buf.len() < 4 + key_len + 2 {
                // 兼容旧格式: [magic][type][key:u8][pressed:u8]
                let key = (buf[2] as char).to_string();
                let pressed = buf[3] != 0;
                return Some((InputMessage::Button { key, pressed, modifiers: None, seq: None }, None));
            }
            let key = String::from_utf8_lossy(&buf[3..3+key_len]).to_string();
            let pressed = buf[3 + key_len] != 0;
            let modifiers = Modifiers::from_byte(buf[4 + key_len]);
            Some((InputMessage::Button { key, pressed, modifiers: if modifiers.is_empty() { None } else { Some(modifiers) }, seq: None }, None))
        }
        // 可靠按键消息: [magic:1][type:1][seq:4][key_len:1][key:N][pressed:1][modifiers:1] = 9 + N bytes
        binary_protocol::MSG_RELIABLE_BUTTON if buf.len() >= 9 => {
            let seq = u32::from_le_bytes([buf[2], buf[3], buf[4], buf[5]]);
            let key_len = buf[6] as usize;
            // 需要 7 + key_len + 2 = 9 + key_len 字节
            if buf.len() < 9 + key_len {
                return None;
            }
            let key = String::from_utf8_lossy(&buf[7..7+key_len]).to_string();
            let pressed = buf[7 + key_len] != 0;
            let modifiers = Modifiers::from_byte(buf[8 + key_len]);
            Some((InputMessage::Button { 
                key, 
                pressed, 
                modifiers: if modifiers.is_empty() { None } else { Some(modifiers) },
                seq: Some(seq)
            }, Some(seq)))
        }
        binary_protocol::MSG_SKILL_START if buf.len() >= 3 => {
            // 新格式: [magic][type][key_len][key...][modifiers]
            let key_len = buf[2] as usize;
            if buf.len() < 3 + key_len + 1 {
                // 兼容旧格式
                let key = (buf[2] as char).to_string();
                return Some((InputMessage::SkillStart { key, offset_x: 0, offset_y: 0, modifiers: None }, None));
            }
            let key = String::from_utf8_lossy(&buf[3..3+key_len]).to_string();
            let modifiers = Modifiers::from_byte(buf[3 + key_len]);
            Some((InputMessage::SkillStart { key, offset_x: 0, offset_y: 0, modifiers: if modifiers.is_empty() { None } else { Some(modifiers) } }, None))
        }
        binary_protocol::MSG_SKILL_DRAG if buf.len() >= 15 => {
            let key = (buf[2] as char).to_string();
            let dx = f32::from_le_bytes([buf[3], buf[4], buf[5], buf[6]]);
            let dy = f32::from_le_bytes([buf[7], buf[8], buf[9], buf[10]]);
            let distance = f32::from_le_bytes([buf[11], buf[12], buf[13], buf[14]]);
            let smooth = buf.get(15).map(|&b| b != 0).unwrap_or(true);
            Some((InputMessage::SkillDrag { key, dx, dy, distance, smooth }, None))
        }
        binary_protocol::MSG_SKILL_RELEASE if buf.len() >= 11 => {
            let key = (buf[2] as char).to_string();
            let dx = f32::from_le_bytes([buf[3], buf[4], buf[5], buf[6]]);
            let dy = f32::from_le_bytes([buf[7], buf[8], buf[9], buf[10]]);
            Some((InputMessage::SkillRelease { key, dx, dy, seq: None }, None))
        }
        // 可靠技能释放: [magic][type][seq:u32][key:u8][dx:f32][dy:f32]
        binary_protocol::MSG_RELIABLE_SKILL_RELEASE if buf.len() >= 15 => {
            let seq = u32::from_le_bytes([buf[2], buf[3], buf[4], buf[5]]);
            let key = (buf[6] as char).to_string();
            let dx = f32::from_le_bytes([buf[7], buf[8], buf[9], buf[10]]);
            let dy = f32::from_le_bytes([buf[11], buf[12], buf[13], buf[14]]);
            Some((InputMessage::SkillRelease { key, dx, dy, seq: Some(seq) }, Some(seq)))
        }
        binary_protocol::MSG_SKILL_CANCEL if buf.len() >= 3 => {
            let key = (buf[2] as char).to_string();
            Some((InputMessage::SkillCancel { key, seq: None }, None))
        }
        // 可靠技能取消: [magic][type][seq:u32][key:u8]
        binary_protocol::MSG_RELIABLE_SKILL_CANCEL if buf.len() >= 7 => {
            let seq = u32::from_le_bytes([buf[2], buf[3], buf[4], buf[5]]);
            let key = (buf[6] as char).to_string();
            Some((InputMessage::SkillCancel { key, seq: Some(seq) }, Some(seq)))
        }
        binary_protocol::MSG_PING if buf.len() >= 10 => {
            let timestamp = u64::from_le_bytes([
                buf[2], buf[3], buf[4], buf[5], buf[6], buf[7], buf[8], buf[9]
            ]);
            Some((InputMessage::Ping { timestamp }, None))
        }
        _ => None,
    }
}

// 极限模式：构建二进制 pong 响应
fn build_binary_pong(timestamp: u64) -> [u8; 10] {
    let mut buf = [0u8; 10];
    buf[0] = binary_protocol::MAGIC;
    buf[1] = binary_protocol::MSG_PONG;
    buf[2..10].copy_from_slice(&timestamp.to_le_bytes());
    buf
}

// 极限模式：构建二进制 ACK 响应
fn build_binary_ack(seq: u32) -> [u8; 6] {
    let mut buf = [0u8; 6];
    buf[0] = binary_protocol::MAGIC;
    buf[1] = binary_protocol::MSG_ACK;
    buf[2..6].copy_from_slice(&seq.to_le_bytes());
    buf
}



/// 鼠标按键类型
#[derive(Debug, Clone, Copy, PartialEq)]
enum MouseAction {
    Left,
    Right,
    Middle,
    Back,
    Forward,
    ScrollUp,
    ScrollDown,
}

/// 解析结果：键盘按键或鼠标操作
enum ParsedInput {
    Keyboard(Key),
    Mouse(MouseAction),
}

/// 解析按键字符串
fn parse_key(key_str: &str) -> Option<ParsedInput> {
    let key_lower = key_str.to_lowercase();
    match key_lower.as_str() {
        // 鼠标按键
        "mouse_left" => Some(ParsedInput::Mouse(MouseAction::Left)),
        "mouse_right" => Some(ParsedInput::Mouse(MouseAction::Right)),
        "mouse_middle" => Some(ParsedInput::Mouse(MouseAction::Middle)),
        "mouse_back" => Some(ParsedInput::Mouse(MouseAction::Back)),
        "mouse_forward" => Some(ParsedInput::Mouse(MouseAction::Forward)),
        "scroll_up" => Some(ParsedInput::Mouse(MouseAction::ScrollUp)),
        "scroll_down" => Some(ParsedInput::Mouse(MouseAction::ScrollDown)),
        // 修饰键（左）
        "lshift" => Some(ParsedInput::Keyboard(Key::LShift)),
        "lctrl" | "lcontrol" => Some(ParsedInput::Keyboard(Key::LControl)),
        "lalt" => Some(ParsedInput::Keyboard(Key::Alt)),  // enigo 不区分左右 Alt
        "lcmd" | "lmeta" | "lwin" => Some(ParsedInput::Keyboard(Key::Meta)),  // enigo 不区分左右 Meta
        // 修饰键（右）
        "rshift" => Some(ParsedInput::Keyboard(Key::RShift)),
        "rctrl" | "rcontrol" => Some(ParsedInput::Keyboard(Key::RControl)),
        "ralt" => Some(ParsedInput::Keyboard(Key::Alt)),  // enigo 不区分左右 Alt
        "rcmd" | "rmeta" | "rwin" => Some(ParsedInput::Keyboard(Key::Meta)),  // enigo 不区分左右 Meta
        // 通用修饰键（不区分左右）
        "shift" => Some(ParsedInput::Keyboard(Key::Shift)),
        "ctrl" | "control" => Some(ParsedInput::Keyboard(Key::Control)),
        "alt" => Some(ParsedInput::Keyboard(Key::Alt)),
        "cmd" | "meta" | "win" => Some(ParsedInput::Keyboard(Key::Meta)),
        // 常用键
        "space" => Some(ParsedInput::Keyboard(Key::Space)),
        "enter" | "return" => Some(ParsedInput::Keyboard(Key::Return)),
        "tab" => Some(ParsedInput::Keyboard(Key::Tab)),
        "escape" | "esc" => Some(ParsedInput::Keyboard(Key::Escape)),
        "backspace" => Some(ParsedInput::Keyboard(Key::Backspace)),
        "delete" => Some(ParsedInput::Keyboard(Key::Delete)),
        "capslock" => Some(ParsedInput::Keyboard(Key::CapsLock)),
        // 方向键
        "up" => Some(ParsedInput::Keyboard(Key::UpArrow)),
        "down" => Some(ParsedInput::Keyboard(Key::DownArrow)),
        "left" => Some(ParsedInput::Keyboard(Key::LeftArrow)),
        "right" => Some(ParsedInput::Keyboard(Key::RightArrow)),
        // 导航键
        "home" => Some(ParsedInput::Keyboard(Key::Home)),
        "end" => Some(ParsedInput::Keyboard(Key::End)),
        "pageup" => Some(ParsedInput::Keyboard(Key::PageUp)),
        "pagedown" => Some(ParsedInput::Keyboard(Key::PageDown)),
        // 功能键
        "f1" => Some(ParsedInput::Keyboard(Key::F1)),
        "f2" => Some(ParsedInput::Keyboard(Key::F2)),
        "f3" => Some(ParsedInput::Keyboard(Key::F3)),
        "f4" => Some(ParsedInput::Keyboard(Key::F4)),
        "f5" => Some(ParsedInput::Keyboard(Key::F5)),
        "f6" => Some(ParsedInput::Keyboard(Key::F6)),
        "f7" => Some(ParsedInput::Keyboard(Key::F7)),
        "f8" => Some(ParsedInput::Keyboard(Key::F8)),
        "f9" => Some(ParsedInput::Keyboard(Key::F9)),
        "f10" => Some(ParsedInput::Keyboard(Key::F10)),
        "f11" => Some(ParsedInput::Keyboard(Key::F11)),
        "f12" => Some(ParsedInput::Keyboard(Key::F12)),
        // 小键盘数字
        "num0" | "numpad0" => Some(ParsedInput::Keyboard(Key::Numpad0)),
        "num1" | "numpad1" => Some(ParsedInput::Keyboard(Key::Numpad1)),
        "num2" | "numpad2" => Some(ParsedInput::Keyboard(Key::Numpad2)),
        "num3" | "numpad3" => Some(ParsedInput::Keyboard(Key::Numpad3)),
        "num4" | "numpad4" => Some(ParsedInput::Keyboard(Key::Numpad4)),
        "num5" | "numpad5" => Some(ParsedInput::Keyboard(Key::Numpad5)),
        "num6" | "numpad6" => Some(ParsedInput::Keyboard(Key::Numpad6)),
        "num7" | "numpad7" => Some(ParsedInput::Keyboard(Key::Numpad7)),
        "num8" | "numpad8" => Some(ParsedInput::Keyboard(Key::Numpad8)),
        "num9" | "numpad9" => Some(ParsedInput::Keyboard(Key::Numpad9)),
        // 小键盘运算符
        "numadd" | "numplus" => Some(ParsedInput::Keyboard(Key::Add)),
        "numsub" | "numminus" => Some(ParsedInput::Keyboard(Key::Subtract)),
        "nummul" | "nummultiply" => Some(ParsedInput::Keyboard(Key::Multiply)),
        "numdiv" | "numdivide" => Some(ParsedInput::Keyboard(Key::Divide)),
        "numdec" | "numdecimal" => Some(ParsedInput::Keyboard(Key::Decimal)),
        "numenter" => Some(ParsedInput::Keyboard(Key::Return)),  // 小键盘回车映射到普通回车
        // 单字符按键
        s if s.len() == 1 => {
            s.chars().next().map(|c| ParsedInput::Keyboard(Key::Unicode(c.to_ascii_lowercase())))
        }
        _ => None,
    }
}

/// 将 MouseAction 转换为 enigo Button
fn mouse_action_to_button(action: MouseAction) -> Option<Button> {
    match action {
        MouseAction::Left => Some(Button::Left),
        MouseAction::Right => Some(Button::Right),
        MouseAction::Middle => Some(Button::Middle),
        MouseAction::Back => Some(Button::Back),
        MouseAction::Forward => Some(Button::Forward),
        MouseAction::ScrollUp | MouseAction::ScrollDown => None, // 滚轮不是按钮
    }
}

struct InputState {
    pressed_keys: HashSet<String>,  // 改为 String 以支持特殊按键
    pressed_modifiers: Modifiers,   // 当前按下的修饰键
    enigo: Enigo,
    skill_center: Option<(i32, i32)>,
    active_skill: Option<String>,
    // 平滑鼠标移动
    current_mouse_x: f32,
    current_mouse_y: f32,
    target_mouse_x: f32,
    target_mouse_y: f32,
}

impl InputState {
    fn new() -> Self {
        Self {
            pressed_keys: HashSet::new(),
            pressed_modifiers: Modifiers::default(),
            enigo: Enigo::new(&Settings::default()).expect("Failed to create Enigo"),
            skill_center: None,
            active_skill: None,
            current_mouse_x: 0.0,
            current_mouse_y: 0.0,
            target_mouse_x: 0.0,
            target_mouse_y: 0.0,
        }
    }
    
    /// 按下/释放修饰键
    fn update_modifiers(&mut self, modifiers: &Modifiers, press: bool) {
        let direction = if press { enigo::Direction::Press } else { enigo::Direction::Release };
        
        if modifiers.shift && (press != self.pressed_modifiers.shift) {
            let _ = self.enigo.key(Key::Shift, direction);
            self.pressed_modifiers.shift = press;
        }
        if modifiers.control && (press != self.pressed_modifiers.control) {
            let _ = self.enigo.key(Key::Control, direction);
            self.pressed_modifiers.control = press;
        }
        if modifiers.alt && (press != self.pressed_modifiers.alt) {
            let _ = self.enigo.key(Key::Alt, direction);
            self.pressed_modifiers.alt = press;
        }
        if modifiers.command && (press != self.pressed_modifiers.command) {
            let _ = self.enigo.key(Key::Meta, direction);
            self.pressed_modifiers.command = press;
        }
    }
    
    /// 释放所有修饰键
    fn release_all_modifiers(&mut self) {
        if self.pressed_modifiers.shift {
            let _ = self.enigo.key(Key::Shift, enigo::Direction::Release);
            self.pressed_modifiers.shift = false;
        }
        if self.pressed_modifiers.control {
            let _ = self.enigo.key(Key::Control, enigo::Direction::Release);
            self.pressed_modifiers.control = false;
        }
        if self.pressed_modifiers.alt {
            let _ = self.enigo.key(Key::Alt, enigo::Direction::Release);
            self.pressed_modifiers.alt = false;
        }
        if self.pressed_modifiers.command {
            let _ = self.enigo.key(Key::Meta, enigo::Direction::Release);
            self.pressed_modifiers.command = false;
        }
    }

    fn update_key(&mut self, key: char, should_press: bool) {
        let key_str = key.to_string();
        let is_pressed = self.pressed_keys.contains(&key_str);
        if should_press && !is_pressed {
            let _ = self.enigo.key(Key::Unicode(key), enigo::Direction::Press);
            self.pressed_keys.insert(key_str);
        } else if !should_press && is_pressed {
            let _ = self.enigo.key(Key::Unicode(key), enigo::Direction::Release);
            self.pressed_keys.remove(&key_str);
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

    fn handle_button(&mut self, key: &str, pressed: bool, modifiers: Option<Modifiers>) {
        let key_lower = key.to_lowercase();
        
        if pressed {
            // 先按下修饰键
            if let Some(ref mods) = modifiers {
                if !mods.is_empty() {
                    self.update_modifiers(mods, true);
                    // 给系统一点时间识别修饰键
                    thread::sleep(std::time::Duration::from_millis(10));
                }
            }
            
            // 按下主键或鼠标
            if let Some(parsed) = parse_key(&key_lower) {
                match parsed {
                    ParsedInput::Keyboard(enigo_key) => {
                        let _ = self.enigo.key(enigo_key, enigo::Direction::Press);
                        self.pressed_keys.insert(key_lower);
                    }
                    ParsedInput::Mouse(action) => {
                        match action {
                            MouseAction::ScrollUp => {
                                let _ = self.enigo.scroll(2, enigo::Axis::Vertical);
                            }
                            MouseAction::ScrollDown => {
                                let _ = self.enigo.scroll(-2, enigo::Axis::Vertical);
                            }
                            _ => {
                                if let Some(btn) = mouse_action_to_button(action) {
                                    let _ = self.enigo.button(btn, enigo::Direction::Press);
                                    self.pressed_keys.insert(key_lower);
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // 释放主键或鼠标
            if let Some(parsed) = parse_key(&key_lower) {
                match parsed {
                    ParsedInput::Keyboard(enigo_key) => {
                        let _ = self.enigo.key(enigo_key, enigo::Direction::Release);
                        self.pressed_keys.remove(&key_lower);
                    }
                    ParsedInput::Mouse(action) => {
                        // 滚轮不需要释放
                        if action != MouseAction::ScrollUp && action != MouseAction::ScrollDown {
                            if let Some(btn) = mouse_action_to_button(action) {
                                let _ = self.enigo.button(btn, enigo::Direction::Release);
                                self.pressed_keys.remove(&key_lower);
                            }
                        }
                    }
                }
            }
            
            // 释放修饰键
            if let Some(ref mods) = modifiers {
                if !mods.is_empty() {
                    // 给系统一点时间识别主键释放
                    thread::sleep(std::time::Duration::from_millis(10));
                    self.update_modifiers(mods, false);
                }
            }
        }
    }

    fn handle_skill_start(&mut self, key: &str, offset_x: i32, offset_y: i32, modifiers: Option<Modifiers>) {
        // 获取当前鼠标所在显示器的中心，并应用偏移
        let base_center = get_current_display_center();
        let center = (base_center.0 + offset_x, base_center.1 + offset_y);
        self.skill_center = Some(center);

        // 先按下修饰键
        if let Some(ref mods) = modifiers {
            self.update_modifiers(mods, true);
        }

        // 按下技能键（点击）- 支持键盘和鼠标
        if let Some(parsed) = parse_key(key) {
            match parsed {
                ParsedInput::Keyboard(enigo_key) => {
                    let _ = self.enigo.key(enigo_key, enigo::Direction::Click);
                }
                ParsedInput::Mouse(action) => {
                    match action {
                        MouseAction::ScrollUp => {
                            let _ = self.enigo.scroll(2, enigo::Axis::Vertical);
                        }
                        MouseAction::ScrollDown => {
                            let _ = self.enigo.scroll(-2, enigo::Axis::Vertical);
                        }
                        _ => {
                            if let Some(btn) = mouse_action_to_button(action) {
                                let _ = self.enigo.button(btn, enigo::Direction::Click);
                            }
                        }
                    }
                }
            }
        }
        
        // 释放修饰键
        if let Some(ref mods) = modifiers {
            self.update_modifiers(mods, false);
        }

        // 鼠标移到显示器中心（含偏移）
        let _ = self.enigo.move_mouse(center.0, center.1, Coordinate::Abs);
        
        // 初始化平滑鼠标位置
        self.current_mouse_x = center.0 as f32;
        self.current_mouse_y = center.1 as f32;
        self.target_mouse_x = center.0 as f32;
        self.target_mouse_y = center.1 as f32;

        self.active_skill = Some(key.to_string());
        
        let mod_str = modifiers.map(|m| {
            let mut parts = Vec::new();
            if m.control { parts.push("Ctrl"); }
            if m.alt { parts.push("Alt"); }
            if m.shift { parts.push("Shift"); }
            if m.command { parts.push("Cmd"); }
            if parts.is_empty() { String::new() } else { format!(" [{}]", parts.join("+")) }
        }).unwrap_or_default();
        
        if offset_x != 0 || offset_y != 0 {
            println!("[技能开始] {}{} - 中心 ({}, {}) 偏移 ({}, {})", key, mod_str, center.0, center.1, offset_x, offset_y);
        } else {
            println!("[技能开始] {}{} - 中心 ({}, {})", key, mod_str, center.0, center.1);
        }
    }

    fn handle_skill_drag(&mut self, _key: &str, dx: f32, dy: f32, _distance: f32, smooth: bool) {
        if let Some(center) = self.skill_center {
            let target_x = center.0 as f32 + dx * SKILL_MOUSE_RADIUS as f32;
            let target_y = center.1 as f32 + dy * SKILL_MOUSE_RADIUS as f32;
            
            if smooth {
                // 平滑模式：线性插值
                self.target_mouse_x = target_x;
                self.target_mouse_y = target_y;
                
                self.current_mouse_x += (self.target_mouse_x - self.current_mouse_x) * SMOOTH_FACTOR;
                self.current_mouse_y += (self.target_mouse_y - self.current_mouse_y) * SMOOTH_FACTOR;
                
                let _ = self.enigo.move_mouse(
                    self.current_mouse_x as i32,
                    self.current_mouse_y as i32,
                    Coordinate::Abs
                );
            } else {
                // 直接模式
                let _ = self.enigo.move_mouse(target_x as i32, target_y as i32, Coordinate::Abs);
            }
        }
    }

    fn handle_skill_release(&mut self, key: &str, dx: f32, dy: f32) {
        if let Some(center) = self.skill_center {
            let mouse_x = center.0 + (dx * SKILL_MOUSE_RADIUS as f32) as i32;
            let mouse_y = center.1 + (dy * SKILL_MOUSE_RADIUS as f32) as i32;
            
            // 移动到最终位置
            let _ = self.enigo.move_mouse(mouse_x, mouse_y, Coordinate::Abs);
            // 延迟一下再点击，确保鼠标移动完成
            thread::sleep(std::time::Duration::from_millis(SKILL_CLICK_DELAY_MS));
            // 点击确认 - 分开按下和释放
            let _ = self.enigo.button(Button::Left, enigo::Direction::Press);
            thread::sleep(std::time::Duration::from_millis(SKILL_CLICK_HOLD_MS));
            let _ = self.enigo.button(Button::Left, enigo::Direction::Release);
            // 延迟后再回到中心
            thread::sleep(std::time::Duration::from_millis(SKILL_CLICK_DELAY_MS));
            // 回到中心
            let _ = self.enigo.move_mouse(center.0, center.1, Coordinate::Abs);
            
            println!("[技能释放] {} - ({}, {})", key, mouse_x, mouse_y);
        }
        self.skill_center = None;
        self.active_skill = None;
    }

    fn handle_skill_cancel(&mut self, key: &str) {
        if let Some(center) = self.skill_center {
            let _ = self.enigo.move_mouse(center.0, center.1, Coordinate::Abs);
        }
        self.skill_center = None;
        self.active_skill = None;
        println!("[技能取消] {}", key);
    }

    fn release_all(&mut self) {
        for key_str in self.pressed_keys.clone() {
            if let Some(parsed) = parse_key(&key_str) {
                match parsed {
                    ParsedInput::Keyboard(enigo_key) => {
                        let _ = self.enigo.key(enigo_key, enigo::Direction::Release);
                    }
                    ParsedInput::Mouse(action) => {
                        if let Some(btn) = mouse_action_to_button(action) {
                            let _ = self.enigo.button(btn, enigo::Direction::Release);
                        }
                    }
                }
            }
        }
        self.pressed_keys.clear();
        self.release_all_modifiers();
        self.skill_center = None;
        self.active_skill = None;
    }
}


fn register_mdns_service(ip: &std::net::IpAddr, port: u16) -> Option<ServiceDaemon> {
    let mdns = ServiceDaemon::new().ok()?;
    
    // 获取主机名作为服务名（去掉可能存在的 .local 后缀）
    let raw_hostname = hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "TouchServer".to_string());
    
    let hostname = raw_hostname
        .trim_end_matches(".local")
        .trim_end_matches('.');
    
    let instance_name = format!("TouchServer-{}", hostname);
    let host_name = format!("{}.local.", hostname);
    
    // 创建服务信息
    let service_info = ServiceInfo::new(
        SERVICE_TYPE,
        &instance_name,
        &host_name,
        ip,
        port,
        None,
    );
    
    match service_info {
        Ok(info) => {
            if let Err(e) = mdns.register(info) {
                println!("[mDNS] 注册失败: {:?}", e);
                return None;
            }
            println!("[mDNS] 服务已注册: {}", instance_name);
            println!("[mDNS] 服务类型: {}", SERVICE_TYPE);
            println!("[mDNS] 主机名: {}", host_name);
            Some(mdns)
        }
        Err(e) => {
            println!("[mDNS] 创建服务信息失败: {:?}", e);
            None
        }
    }
}

fn main() {
    let local_ip = local_ip().expect("Failed to get local IP");
    
    // 注册 mDNS 服务
    let _mdns = register_mdns_service(&local_ip, PORT);
    if _mdns.is_none() {
        println!("[mDNS] 警告: 服务注册失败，客户端需手动输入IP");
    }
    
    // 显示检测到的显示器
    let monitors = get_all_monitors();
    
    println!("========================================");
    println!("  Touch Server - UDP 低延迟输入服务");
    println!("========================================");
    println!("局域网 IP: {}", local_ip);
    println!("监听端口: {}", PORT);
    println!("连接地址: {}:{}", local_ip, PORT);
    println!("----------------------------------------");
    println!("检测到 {} 个显示器:", monitors.len());
    for (i, m) in monitors.iter().enumerate() {
        println!("  [{}] {}x{} @ ({}, {})", i + 1, m.width, m.height, m.x, m.y);
    }
    println!("----------------------------------------");
    println!("摇杆映射: W(上) A(左) S(下) D(右)");
    println!("技能鼠标半径: {}px", SKILL_MOUSE_RADIUS);
    println!("死区阈值: {:.0}%", DEADZONE * 100.0);
    println!("支持模式: 普通(JSON) / 极限(二进制)");
    println!("========================================");
    println!("等待客户端连接...\n");

    let socket = UdpSocket::bind(format!("0.0.0.0:{}", PORT)).expect("Failed to bind");
    socket.set_read_timeout(Some(std::time::Duration::from_secs(1))).ok();
    
    // 极限模式优化：增大接收缓冲区
    #[cfg(unix)]
    {
        use std::os::unix::io::AsRawFd;
        let fd = socket.as_raw_fd();
        unsafe {
            let buf_size: libc::c_int = 65536;
            libc::setsockopt(
                fd,
                libc::SOL_SOCKET,
                libc::SO_RCVBUF,
                &buf_size as *const _ as *const libc::c_void,
                std::mem::size_of::<libc::c_int>() as libc::socklen_t,
            );
        }
    }

    let mut input_state = InputState::new();
    let mut buf = [0u8; 1024];
    let mut last_client: Option<std::net::SocketAddr> = None;
    let mut last_heartbeat = Instant::now();
    let mut client_extreme_mode = false;  // 跟踪客户端是否使用极限模式
    
    // 可靠消息去重：记录最近处理过的序列号
    let mut processed_seqs: std::collections::VecDeque<u32> = std::collections::VecDeque::with_capacity(100);
    const MAX_PROCESSED_SEQS: usize = 100;

    loop {
        match socket.recv_from(&mut buf) {
            Ok((len, src)) => {
                if last_client != Some(src) {
                    println!("[连接] 客户端: {}", src);
                    last_client = Some(src);
                    client_extreme_mode = false;
                    processed_seqs.clear();  // 新客户端，清空去重缓存
                }
                last_heartbeat = Instant::now();

                // 自动检测协议类型：二进制协议以 MAGIC (0xAB) 开头
                let is_binary = len > 0 && buf[0] == binary_protocol::MAGIC;
                
                // 解析消息，获取消息内容和可选的序列号
                let (msg, ack_seq) = if is_binary {
                    if !client_extreme_mode {
                        println!("[模式] 客户端切换到极限模式 (二进制协议)");
                        client_extreme_mode = true;
                    }
                    match parse_binary_message(&buf[..len]) {
                        Some((m, seq)) => (Some(m), seq),
                        None => (None, None),
                    }
                } else {
                    if client_extreme_mode {
                        println!("[模式] 客户端切换到普通模式 (JSON协议)");
                        client_extreme_mode = false;
                    }
                    match serde_json::from_slice::<InputMessage>(&buf[..len]) {
                        Ok(m) => {
                            // 从 JSON 消息中提取 seq
                            let seq = match &m {
                                InputMessage::Button { seq, .. } => *seq,
                                InputMessage::SkillRelease { seq, .. } => *seq,
                                InputMessage::SkillCancel { seq, .. } => *seq,
                                _ => None,
                            };
                            (Some(m), seq)
                        }
                        Err(_) => (None, None),
                    }
                };
                
                // 如果有序列号，发送 ACK 并检查去重
                if let Some(seq) = ack_seq {
                    // 发送 ACK
                    if is_binary {
                        let ack = build_binary_ack(seq);
                        let _ = socket.send_to(&ack, src);
                    } else {
                        let ack = AckMessage { r#type: "ack", seq };
                        if let Ok(data) = serde_json::to_vec(&ack) {
                            let _ = socket.send_to(&data, src);
                        }
                    }
                    
                    // 检查是否重复消息
                    if processed_seqs.contains(&seq) {
                        // 重复消息，跳过处理但已发送 ACK
                        continue;
                    }
                    
                    // 记录已处理的序列号
                    processed_seqs.push_back(seq);
                    if processed_seqs.len() > MAX_PROCESSED_SEQS {
                        processed_seqs.pop_front();
                    }
                }

                if let Some(msg) = msg {
                    match msg {
                        InputMessage::Joystick { x, y } => input_state.handle_joystick(x, y),
                        InputMessage::Button { key, pressed, modifiers, .. } => {
                            let mod_str = modifiers.as_ref().map(|m| {
                                let mut parts = Vec::new();
                                if m.control { parts.push("Ctrl"); }
                                if m.alt { parts.push("Alt"); }
                                if m.shift { parts.push("Shift"); }
                                if m.command { parts.push("Cmd"); }
                                if parts.is_empty() { String::new() } else { format!("[{}+]", parts.join("+")) }
                            }).unwrap_or_default();
                            println!("[按键] {}{} {}", mod_str, key, if pressed { "按下" } else { "释放" });
                            input_state.handle_button(&key, pressed, modifiers);
                        }
                        InputMessage::SkillStart { key, offset_x, offset_y, modifiers } => {
                            input_state.handle_skill_start(&key, offset_x, offset_y, modifiers);
                        }
                        InputMessage::SkillDrag { key, dx, dy, distance, smooth } => {
                            input_state.handle_skill_drag(&key, dx, dy, distance, smooth)
                        }
                        InputMessage::SkillRelease { key, dx, dy, .. } => {
                            input_state.handle_skill_release(&key, dx, dy)
                        }
                        InputMessage::SkillCancel { key, .. } => input_state.handle_skill_cancel(&key),
                        InputMessage::Ping { timestamp } => {
                            if is_binary {
                                // 极限模式：二进制 pong
                                let pong = build_binary_pong(timestamp);
                                let _ = socket.send_to(&pong, src);
                            } else {
                                // 普通模式：JSON pong
                                let pong = PongMessage { r#type: "pong", timestamp };
                                if let Ok(data) = serde_json::to_vec(&pong) {
                                    let _ = socket.send_to(&data, src);
                                }
                            }
                        }
                    }
                }
            }
            Err(e) => {
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut
                {
                    if last_client.is_some()
                        && last_heartbeat.elapsed().as_secs() > HEARTBEAT_TIMEOUT_SECS
                    {
                        println!("[断开] 心跳超时");
                        input_state.release_all();
                        last_client = None;
                    }
                }
            }
        }
    }
}
