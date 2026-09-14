# Thyco Monitor

[English](#english) | [简体中文](#简体中文)

---

<span id="english"></span>
## English

Thyco Monitor is a lightweight system monitor and utility panel designed specifically for macOS. Living in your menu bar, it provides a frameless floating panel that lets you monitor system status and perform quick actions anytime.

### 🌟 Key Features

#### 📊 System Monitoring
- **CPU & Thermal**: Real-time display of CPU temperature, CPU load, and fan speed (RPM).
- **Network Status**: Displays Wi-Fi connection status, along with real-time network upload and download speeds.
- **Storage**: Intuitive display of remaining, used, and total disk space, with quick launch for your preferred cleaning utility (e.g., CleanMyMac).
- **Memory Usage**: Provides an overview and detailed breakdown of memory (App Memory, Wired, Compressed, etc.), equipped with a **Memory Pressure Indicator** (Green/Yellow/Red, consistent with Activity Monitor) in the bottom-right corner of the memory card.
- **Battery Information**: Shows current battery percentage, charging state, and charging wattage.

#### 🛠️ Quick Utilities
- **Hide Desktop**: One-click toggle to hide all desktop icons and files, keeping your desktop clean for screenshots or screen recordings.
- **Cleaning Mode**: Enters a full-screen blackout mode and locks keyboard input, making it easy to clean your screen and keyboard.
- **Audio Control**: Quickly switch audio output and input devices, adjust volume, and balance left/right channels.
- **Type Racing Game**: Built-in mini typing test game to relax and test your typing speed in your spare time.
- **Launch at Login**: Easily toggle launch-at-login for seamless menu bar residency.

#### 🎨 Interface & Experience
- **Floating Panel**: Designed with a frameless frosted glass (vibrancy) background, seamlessly integrating into macOS aesthetics.
- **Appearance Modes**: Supports manual switching between Dark and Light mode, defaulting to system appearance on first launch.
- **Multi-language Support**: Built-in localization (supports English and Simplified Chinese).

#### 💡 Easter Eggs & Advanced Tricks
- **Quick Mute**: Click the **percentage number** above the volume slider to quickly mute (set volume to 0), and click again to restore previous volume.
- **Quick Center Balance**: When adjusting audio balance, click the **"L"** or **"R"** label on either side of the slider to immediately reset channel balance to center.
- **Reset Local Data**: Triple-click the **"MADE BY HYC"** label in the bottom-right corner of the panel to clear all locally saved preferences and data.

### 🚀 Getting Started

1. Clone this repository locally:
   ```bash
   git clone https://github.com/HYC6113/Thyco_Monitor.git
   ```
2. Open `Thyco Monitor.xcodeproj` in Xcode.
3. Select your Mac as the destination (My Mac).
4. Click **Run** (`Cmd + R`) to build and run.
5. Once running, you will see a Vision Pro-shaped icon in the top menu bar. Click it to expand the monitor panel.

### 🛡️ Security & Privacy

Thyco Monitor is committed to user privacy and system security:
- **Zero Network Requests**: All system monitoring is performed strictly locally; no device information is ever sent to external servers.
- **Read-Only Monitoring**: The majority of features only read system states (such as SMC sensors, network interfaces, disk space, etc.).
- **Safe Operations**: Features like "Hide Desktop" only modify Finder's `CreateDesktop` preference without deleting or moving any of your files.

### ⚙️ Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)

### 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page or submit a pull request.

### 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

<span id="简体中文"></span>
## 简体中文

Thyco Monitor 是一款专为 macOS 设计的轻量级系统监控与实用工具面板。它常驻于菜单栏，提供无边框的浮动面板，让你可以随时查看系统状态并进行快捷操作。

### 🌟 核心功能

#### 📊 系统状态监控
- **CPU & 散热**：实时显示 CPU 温度、CPU 负载以及风扇转速（RPM）。
- **网络状态**：显示 Wi-Fi 连接状态，以及实时的网络上传和下载速度。
- **存储空间**：直观展示磁盘剩余空间、已用空间和总空间，并支持一键启动你常用的清理工具（如 CleanMyMac）。
- **内存使用**：提供内存概览与详细的内存细分（App Memory, Wired, Compressed 等），内存卡片右下角配有**内存压力指示灯**（绿/黄/红，与活动监视器一致）。
- **电池信息**：显示当前电量、充电状态及充电功率（瓦特）。

#### 🛠️ 快捷实用工具
- **隐藏桌面**：一键隐藏桌面上的所有文件和图标，让你在截图或录屏时保持桌面整洁。
- **清洁模式**：进入全屏纯黑模式，屏蔽键盘输入，方便你清洁屏幕和键盘。
- **音频控制**：快速切换音频输出和输入设备，调整音量以及左右声道平衡。
- **打字游戏 (Type Racing)**：内置一个简单的打字测速小游戏，在闲暇之余放松一下。
- **开机自启动**：支持一键开启或关闭开机自动启动，方便常驻使用。

#### 🎨 界面与体验
- **悬浮面板**：采用无边框、毛玻璃背景设计，完美融入 macOS 视觉风格。
- **外观模式**：支持手动切换深色（Dark）和浅色（Light）模式，初次打开默认跟随系统。
- **多语言支持**：内置多语言切换（支持中文和英文）。

#### 💡 隐藏彩蛋与高级操作
- **快速静音**：点击音量滑块上方的**数字百分比**，可一键将音量设为 0（静音），再次点击即可恢复原音量。
- **声道快速居中**：在调整声道平衡时，点击滑块左右两侧的 **"L"** 或 **"R"** 标签，即可快速将声道平衡恢复至居中状态。
- **重置本地数据**：连续三击面板右下角的 **"MADE BY HYC"** 字样，即可清除所有本地保存的偏好设置与数据。

### 🚀 安装与运行

1. 克隆本仓库到本地：
   ```bash
   git clone https://github.com/HYC6113/Thyco_Monitor.git
   ```
2. 使用 Xcode 打开 `Thyco Monitor.xcodeproj`。
3. 选择你的 Mac 作为目标设备（My Mac）。
4. 点击 **Run** (Cmd + R) 编译并运行。
5. 运行后，你会在屏幕顶部的菜单栏看到一个类似 Vision Pro 形状的图标，点击即可展开监控面板。

### 🛡️ 安全性与隐私

Thyco Monitor 致力于保护用户的隐私与系统安全：
- **无网络请求**：所有的系统数据监控均在本地完成，不会向任何外部服务器发送你的设备信息。
- **只读监控**：大部分功能仅读取系统状态（如 SMC 传感器、网络接口、磁盘空间等）。
- **安全的操作**：如“隐藏桌面”功能，仅通过修改 Finder 的 `CreateDesktop` 偏好设置实现，不会删除或移动你的任何文件。

### ⚙️ 系统要求

- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本（用于编译）

### 🤝 贡献

欢迎提交 Issue 或 Pull Request 来帮助改进 Thyco Monitor！

### 📄 许可证

本项目采用 MIT 许可证。详情请参阅 [LICENSE](LICENSE) 文件。
