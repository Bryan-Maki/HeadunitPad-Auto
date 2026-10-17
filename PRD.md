# HeadunitPad-Auto Product Requirements Document (Pure Wireless & Open-Headunit Full Port)

## 1. Product goal

将 `HeadunitPad-Auto` 打造为功能完整、纯无线架构的 iPadOS 原生 Android Auto 车机接收端（Head Unit Receiver）。

通过彻底移除对有线 USB（AOA）、`TrollUSBHostKit` 及 TrollStore 私有硬件权限的依赖，并将开源项目 `open-headunit` 中 **80% 以上的核心协议、策略类（Policies）、音视频管线、传感器联动与 UI 诊断功能** 移植到 iPadOS，使用户在任何未越狱的 iPad 设备上（通过普通个人证书、AltStore、SideStore 或 Sideloadly 安装），即可获得满屏无黑边（4:3 / 3:2 比例裁切）、Coolwalk 分屏自由调节、HEVC 高清低延迟视频、多音轨混音压音（Audio Ducking）以及断线自动重连的完整车机体验。

---

## 2. Source and compatibility assumptions

- **参考基线工程**：以 `open-headunit` 的架构、Protobuf 定义与业务策略类为唯一移植蓝本。
- **零私有权限与免越狱**：彻底移除 `TrollUSBHostKit`、`libusb` 及所有 USB Host 私有 Entitlements；应用仅依赖 iOS/iPadOS 标准沙盒 API（`Network.framework`、`VideoToolbox`、`AVFoundation`、`CoreLocation`、`CoreImage`），确保普通 Apple ID 免费签名与第三方自签工具均可正常打包安装。
- **系统版本要求**：保持当前 Deployment Target 为 iOS/iPadOS 16.6，除非用户明确同意，不得随意提高最低系统版本要求。
- **第三方依赖**：保留现有 `CocoaPods` 中的 `OpenSSL-Universal`（用于 AAP TLS 握手），并新增 `SwiftProtobuf`（用于编译 `open-headunit` 的全套 `.proto` 协议文件）。

---

## 3. User-visible requirements

### 3.1 Pure wireless connection modes

设置与主界面必须移除所有 USB 选项，并提供以下纯无线连接模式：

- `Auto Wireless`（自动无线模式）：同时启动无线辅助监听（`WirelessHelperServer` / `WppTcpServer`）与子网主动扫描（`NetworkDiscovery`），一旦检测到手机端开启车机服务器或处于同一热点子网即自动发起连接。
- `Direct Headunit Server`（直连手机车机服务器）：支持自动扫描手机热点网关 IP 或手动输入 `IP:5277` 发起 TCP 连接，并保留历史连接记录（`WirelessServerHistory`）。
- `Wireless Helper / WPP`（被动等待手机连入）：在 iPad 本地监听 TCP 端口，等待手机端通过无线投影协议（WPP）或辅助工具主动连入。
- `QR Code Pairing`（扫码配对）：在主界面生成包含当前局域网/热点连接参数的二维码（`ProjectionSetupQrDialog`），支持手机扫码快速建立连接。

切换连接模式在下一次连接或重连时立即生效，并保持设置持久化。

### 3.2 iPad full-screen aspect ratio & Coolwalk DPI split-screen

1. **分辨率与帧率档位**：支持协商 `480p (800×480)`、`720p (1280×720)`、`1080p (1920×1080)`、`1440p (2560×1440)` 与 `4K (3840×2160)`，以及 `30fps` / `60fps` 切换。
2. **iPad 满屏无黑边适配（Margin Cropping）**：
   - 提供 `Fit`（保持 16:9 居中留黑边）、`Fill (Margin Crop)`（协议级边距裁切铺满 iPad 4:3 或 3:2 全屏，画面不变形）、`Stretch`（强制拉伸）三种显示模式。
   - 在 `Fill (Margin Crop)` 模式下，自动根据 iPad 屏幕比例计算 `width_margin` 与 `height_margin` 上报给手机，并通过 `AVSampleBufferDisplayLayer.contentsRect` 裁切掉黑边区域。
3. **精准触控坐标反算（`TouchCoordinateMapper`）**：在任何缩放模式与 Margin 裁切状态下，点击与滑动手势必须精确还原为手机端容器坐标，不得出现触控偏移。
4. **Coolwalk 分屏 DPI 调节与实时预览（`DpiPreviewView`）**：
   - 支持 `100` ~ `320` 自定义 DPI 调节，以及左舵（`LHD`）/ 右舵（`RHD`）驾驶位切换。
   - 设置界面内置可视化 `DpiPreviewView`，无需连接手机即可实时预览当前 DPI 下的侧边栏/底栏位置及单栏、双栏、三栏分屏卡片比例。
5. **动态 UI 配置刷新（`UpdateUiConfigRequest`）**：当 iPad 发生横竖屏旋转或切换分屏窗口大小时，通过视频通道发送 `0x800A` 消息动态更新边距。

### 3.3 Video & audio pipeline experience

1. **双视频编码硬解（H.264 & HEVC/H.265）**：支持在设置中选择 H.264 或 HEVC (H.265) 硬件解码；当解码器初始化失败时，自动按 `DecoderConfigLadder` 降级分辨率或回退编码格式。
2. **无线丢包防花屏与关键帧自愈（Keyframe Repair）**：当无线网络发生丢包、分片缺失或应用从后台返回前台时，自动拦截残缺帧（杜绝马赛克与绿屏），并立即向手机发送关键帧刷新请求。
3. **AAC-LC 音频硬解与多声道混音（Audio Mixing & Ducking）**：
   - 支持 AAC-LC 压缩音频流与 PCM 双模式解码。
   - 独立管理 `Media`（媒体音乐）、`Guidance`（导航播报）、`System`（系统提示音）多条音轨。
   - 当导航语音播报时，自动通过包络算法（`MixerDuckingEnvelope`）平滑压低背景音乐音量，播报结束后平滑恢复。
   - 内置自适应抗抖动缓冲（`AdaptivePcmBuffer`）与防削波限幅器（`MixerSoftClipper`），消除无线网络波动引起的爆音与断音。
4. **语音助手麦克风降采样**：通过 `MicPcmDecimator` 将 iPad 硬件麦克风采集的 48kHz 音频实时抗混叠降采样为 Android Auto 标准 16kHz 单声道 PCM 流，确保 Google Assistant 语音识别准确。

### 3.4 Smart sensors, HUD navigation & peripherals

1. **多模式日夜切换（Night Mode）**：
   - 支持 `Follow System`（跟随 iPadOS 深浅色）、`Day Only`、`Night Only`、`Astronomical Twilight`（根据 GPS 经纬度自动计算日出日落时间切换）以及 `Geofence`（进入预设隧道/地下车库电子围栏坐标时自动切换夜间模式）。
2. **行车限制解除（`DrivingStatusEvent`）**：默认上报 `UNRESTRICTED` 驻车状态，允许用户在投屏期间使用手机软键盘输入。
3. **HUD 导航浮窗与系统媒体播控同步**：
   - 解析导航通道（`AapNavigation`）的实时路名、转向箭头、路口距离与剩余时间，支持在纯视频模式下叠加半透明 HUD 导航指引。
   - 解析媒体播放通道（`AapMediaPlayback`）的歌曲名、歌手、专辑名与封面图片，实时同步至 iPadOS 锁屏与控制中心（`NowPlayingCoordinator`）。
4. **外接按键/旋钮映射与车机身份伪装**：
   - 支持外接蓝牙方向盘按键、蓝牙键盘快捷键与触控板滚轮/旋钮事件（`KeyCodeEvent`、`ScrollWheelEvent`）自定义映射与按键消抖。
   - 支持自定义上报给手机的车机品牌（Make）、型号（Model）、年份（Year）及车机名称。

### 3.5 Floating control, diagnostics & backup

- **全局悬浮控制球（`FloatingButton`）**：在投屏画面提供可自由拖拽、闲置自动半透明的悬浮球，支持一键返回主界面、切换日夜模式、切歌及唤醒语音助手。
- **实时性能监控图层（`PerformanceOverlay`）**：开启后在屏幕角落实时展示 FPS、无线接收码率（Mbps）、解码耗时（ms）、音频缓冲水位、关键帧修复次数与丢包计数。
- **诊断、日志与备份**：主页顶部集成连接故障诊断横幅（`ConnectionIssueBanner`），设置页提供独立声道测试器（`AudioStreamTester`）、运行日志一键导出分享（`LogExporter`）以及全部设置项的 JSON 导入/导出备份（`SettingsBackupManager`）。

---

## 4. Architecture requirements

### 4.1 USB removal & transport boundary

- 彻底删除 `HeadunitPad/Core/USB/` 目录及 `HeadunitPadTests/` 下所有 USB 单元测试文件，清理 `project.pbxproj` 中的残留引用。
- 统一使用 `ByteStreamConnection` 协议抽象所有无线字节流传输（提供连接状态、异步发送、断开连接及数据接收回调）。
- `TcpHandler`、`WirelessHelperServer` 与新增的 `WppTcpServer` 均实现该协议，`AapTransport` 仅依赖 `ByteStreamConnection` 协议而不感知底层是主动 TCP 还是被动监听。

### 4.2 Protocol standardization & message framing

- 将 `open-headunit/app/src/main/proto/` 下的全部 8 个 `.proto` 文件（`common`、`control`、`input`、`media`、`navigation`、`playback`、`sensors`、`wireless`）纳入工程，通过 `SwiftProtobuf` 编译生成强类型 Swift 代码。
- 完整移植 `AapMessageFraming`、`AapMessageReassembler` 与 `FragmentedMessageAudit`，替换 `AapTransport` 中原有的硬编码字节拼接逻辑，确保多通道并发分片报文（如大尺寸视频关键帧与专辑封面）重组安全可靠。

### 4.3 Watchdog & auto-reconnect state machine

- `ConnectionManager` 必须集成来自 `open-headunit` 的无线链路监控策略：
  - `LinkGapMonitor`：监控 Ping/Pong 往返延迟与心跳间隔，超时自动判定链路断开。
  - `VideoStarvationPolicy` & `UnresponsivePeerPolicy`：检测视频流饥饿与对端假死状态。
  - `AutomaticReconnect` & `ReconnectGracePolicy`：在无线闪断时按指数退避策略自动重连，并在重连成功后通过 `ReconnectPlaybackSnapshot` 与 `AutoResumePlaybackPolicy` 自动恢复音乐播放。

### 4.4 Threading & memory safety

- 所有 Socket 读写、OpenSSL TLS 加解密、NAL 分帧、视频硬解与音频重采样必须在专用后台队列或 Swift `Actor` 中执行，严禁阻塞 UI 主线程。
- 视频帧总线（`VideoFrameBus`）需实现 `VideoBackpressurePolicy` 与 `VideoFeedQueuePolicy`，当解码队列积压时主动丢弃非参考帧并触发关键帧请求，防止内存暴涨。

---

## 5. Signing and packaging requirements

- **清理私有 Entitlements**：从 `HeadunitPad/HeadunitPad.entitlements` 中彻底移除 `com.apple.vm.device-access`、`com.apple.security.exception.iokit-user-client-class` 与 `com.apple.system.diagnostics.iokit-properties`。
- **标准沙盒权限配置**：`Info.plist` 仅保留标准网络通信、本地网络发现（`NSLocalNetworkUsageDescription`）、麦克风（`NSMicrophoneUsageDescription`）、定位（`NSLocationWhenInUseUsageDescription`）及后台音频播放（`UIBackgroundModes: audio`）声明。
- **通用 IPA 构建流水线**：移除原 TrollStore 专用签名脚本，改为构建标准的未签名/自签通用 `.ipa`（`scripts/build_unsigned_ipa.sh` 与 `.github/workflows/build-ipa.yml`），完整包含 App 资源与 CocoaPods 框架。

---

## 6. Scope

### 6.1 In scope

- 移除全部 USB / TrollStore 依赖并完成工程清理。
- 移植 `open-headunit` 全部 8 个 `.proto` 协议与分片重组器。
- 移植 iPad 屏幕比例 Margin 裁切、触控映射、Coolwalk DPI 调节与 `DpiPreviewView`。
- 移植纯无线发现、WPP 服务、扫码配对、链路看门狗与断线自动重连。
- 移植 HEVC (H.265) 硬件解码与无线丢包关键帧修复管线。
- 移植 AAC-LC 音频硬解、多音轨混音、导航自动压音（Ducking）、自适应抗抖动缓冲与麦克风降采样。
- 移植多模式日夜切换（含天文计算与电子围栏）、HUD 导航提取、媒体封面同步、外设按键映射与车机身份伪装。
- 移植全局悬浮球、实时性能监控 HUD、声道测试器、故障诊断横幅、日志导出与设置 JSON 备份。

### 6.2 Out of scope

- 任何有线 USB、AOA 协议、`libusb` 或 `TrollUSBHostKit` 相关功能。
- `open-headunit` 中的安卓同机自连模式（`connection/self/*`）。
- 安卓专有特权功能（Root Shell、`SUExecutor`、内置 ADB、Shizuku、虚拟 VPN 路由服务 `DummyVpnService` 及 Wi-Fi Direct 底层反射 hack）。
- 特定国产安卓车机主板广播与外置串口蓝牙芯片驱动（`byd`、`fyt`、`blink`、`zbt`）。

---

## 7. Delivery phases

每次仅推进一个阶段（Phase），每个阶段必须通过对应的编译、单元测试与功能门禁（Gate）后方可进入下一阶段。

| 阶段编号 | 阶段名称 | 核心交付内容 | 当前状态 |
|---|---|---|---|
| **Phase 0** | 工程基建与免越狱适配 | 移除私有 USB 权限，配置普通 Apple ID 免费自签打包与 CI 流水线 | ✅ 已完成 |
| **Phase 1** | 协议层与 1:1 满屏自适应 | Protobuf 编解码、分片重组、`0x8009` 零断连横竖屏动态边距重排、触控零漂移映射 | ✅ 已完成 |
| **Phase 2** | 无线 5277 发现与重连状态机 | 网关直连、并发子网扫描、探活连接零损耗复用、3.0s 静默重拨双保险、看门狗与自动重连 | ✅ 已完成 |
| **Phase 3** | 视频硬解升级与丢包自愈 | `VideoToolbox` H.264/HEVC 硬解、PLI 关键帧自愈、`activeClipView` 局部裁剪与防拉伸护栏 | ✅ 已完成 |
| **Phase 4** | 多音轨混音、AAC 硬解与麦克风 | `AudioToolbox` AAC-LC 硬解、三声道独立混音、导航 30% 自动压音（Ducking）、48k->16k 麦克风降采样 | ✅ 已完成 |
| **Phase 5** | 日夜模式、GPS 与行车解除 | `SensorBatch (0x8003)` 日夜切换、`DrivingStatus = UNRESTRICTED`、CoreLocation GPS 透传 | ✅ 已完成 |
| **Phase 6** | 纯净全屏与诊断工具箱 | 移除投屏遮挡按钮、左上角穿透式 `PerformanceOverlayView`、`AudioStreamTester`、故障横幅、`AppLog` 导出与 JSON 备份、全新 AppIcon | ✅ 已完成 |
| **Phase 7** | **锁屏 Now Playing 修复与麦克风源路由** | **修复 `.mixWithOthers` 导致 iOS 锁屏/控制中心无歌曲信息 Bug、重构 `NowPlayingCoordinator`、新增 `MicrophoneSource`（Follow / iPad / Phone + Motorcycle 协议策略）与 JSON 备份补齐** | ✅ 已完成 |
| **Phase 8** | **现代车载仪表盘主页与原生分组设置中心** | **重构 `MainViewController` 为双栏卡片式车载仪表盘（含状态呼吸灯胶囊与 6 大配置速览磁贴）、新建 `.insetGrouped` 原生 `SettingsViewController`（内嵌实时 `DpiPreviewView`）、投屏防熄屏常亮** | 🎯 当前待执行 |
| **Phase 9** | **智能网络感知、天文日夜、方控映射与解码降级** | **实现 `F8` (`NetworkReachabilityMonitor`)、`F4` (`TwilightCalculator` 日出日落算法 + GPS 负经纬度修复)、`F3` (`KeymapManager` 蓝牙方控/键盘映射)、`F10` (`DecoderConfigLadder` 运行时自动降级闭环)** | ⏳ 待执行 |

### Phase 0 — USB purge and standard IPA foundation

1. 删除 `HeadunitPad/Core/USB/`、`HeadunitPadTests/*USB*`、`HeadunitPadTests/AndroidOpenAccessoryTests.swift` 及旧构建脚本，修复 `project.pbxproj` 引用。
2. 清理 `HeadunitPad.entitlements` 中的私有硬件权限，解耦 `ConnectionManager` 与 `MainViewController` 中的 USB 分支。
3. 建立标准 `.ipa` 构建脚本与 GitHub Actions 工作流。

**Gate**：Xcode Simulator 与 Generic iOS Device 编译零错误通过；生成的 `.ipa` 不含任何私有 USB Entitlements；现有无线连接功能可正常启动运行。

### Phase 1 — Protobuf standardization & iPad screen/DPI system (P0)

1. 引入 `SwiftProtobuf`，编译 `open-headunit` 的 8 个 `.proto` 文件，重构 `AapMessage`、`AapMessageFraming`、`AapMessageReassembler` 与 `AapTransport`。
2. 移植 `HeadUnitScreenConfig`、`MarginStrategyPolicy`、`VideoFitPolicy` 与 `TouchCoordinateMapper`，实现 iPad 4:3 / 3:2 满屏无黑边裁切与精准触控映射。
3. 移植 `DpiPreviewView`、`UpdateUiConfigRequest` 与左右舵（LHD/RHD）设置。

**Gate**：分片重组与坐标映射单元测试 100% 通过；iPad 真机连接后画面可无损铺满 4:3 屏幕且边缘触控精准；调节 DPI 可改变 Coolwalk 分屏形态且预览图与实际投屏一致。

### Phase 2 — Pure wireless engine, watchdogs & auto-reconnect (P0)

1. 移植 `NetworkDiscovery`、`DiscoverySubnetPolicy`、`WppTcpServer`、`WppHandshakeSession` 与 `QrCodeGenerator` 扫码配对弹窗。
2. 移植 `LinkGapMonitor`、`VideoStarvationPolicy`、`UnresponsivePeerPolicy`、`AutomaticReconnect` 与 `AutoResumePlaybackPolicy` 至 `ConnectionManager`。

**Gate**：支持热点子网自动发现与二维码扫码连接；模拟 Wi-Fi 闪断或手机端服务重启时，App 不崩溃且能在宽限期内自动重连并恢复播放。

### Phase 3 — HEVC hardware decoding & wireless keyframe repair (P1)

1. 升级 `NalParser` 与 `VideoRendererView`，支持 H.264 与 HEVC (H.265) 硬件解码及 `DecoderConfigLadder` 自动降级。
2. 移植 `VideoFragmentAssembler`、`VideoKeyframeScanner`、`KeyframeRepairTracker`、`WarmRelaunchKeyframePolicy` 与 `VideoBackpressurePolicy`。

**Gate**：1080p/1440p 60fps 下 HEVC 硬解流畅运行；弱网丢包或前后台切换时无持续花屏/黑屏，关键帧请求能在 1 秒内恢复正常画面。

### Phase 4 — Multi-channel audio mixer, AAC decoding & mic decimator (P1)

1. 实现 `AacAudioDecoder`，支持 AAC-LC 无线压缩音频硬解。
2. 升级 `AudioMixerEngine`，整合 `AudioStreamCatalog`、`MixerDuckingEnvelope`、`MixerSoftClipper` 与 `AdaptivePcmBuffer`。
3. 在 `MicrophoneCapture` 中移植 `MicPcmDecimator`（48kHz 转 16kHz）与 `MicChunkAccumulator`。

**Gate**：导航播报时背景音乐自动平滑压低并在播报后恢复；连续播放 30 分钟无爆音或音画不同步；语音唤醒 Google Assistant 识别正常。

### Phase 5 — Smart sensors, geofencing, HUD navigation & keymap (P2)

1. 移植 `NightModeManager`、`TwilightCalculator`、`GeofenceLocation`（地图选点电子围栏）与 `DrivingStatusEvent`。
2. 移植 `AapNavigation`（HUD 转向指引浮窗）与 `AapMediaPlayback`（锁屏专辑封面与曲目同步）。
3. 移植 `KeyCode`、`ScrollWheelEvent`、`KeymapManager` 外设按键映射及 `VehicleIdentityPolicy` 车机身份自定义。

**Gate**：全部 4 种日夜切换模式及电子围栏触发正常；全屏 HUD 导航卡片与系统控制中心曲目封面显示正确；蓝牙键盘/方控按键可正常控制车机。

### Phase 6 — Performance HUD, diagnostics & backup (P3) [✅ 已完成 (100% 闭环收官)]

1. **投屏画面 100% 纯净无遮挡**：严格遵循纯净车机原则，投屏画面不添加任何常驻悬浮控制按钮。
2. **实时性能监控图层 (`PerformanceOverlayView`)**：仅在用户在设置中开启 `Performance HUD: On` 时以穿透模式（`isUserInteractionEnabled = false`）显示在左上角，黄字等宽实时展示 RES、FPS、接收码率、解码延迟 (median/p95)、音频缓冲深度、关键帧修复 (PLI) 与丢包数。
3. **独立多通道音频测试器 (`AudioStreamTester` & `AudioDiagnostics`)**：纯数学合成 16-bit LE PCM 正弦波与平滑线性淡入淡出包络，支持独立播放 Media (440Hz)、Guidance (587Hz)、System (880Hz) 音频，并支持自动化压音时序模拟测试。
4. **连接故障诊断与横幅 (`ConnectionIssues` & `ConnectionIssueBannerPolicy`)**：智能归因连接失败根因并在主页呈现带解决建议的警告横幅，连接成功自动清除，支持用户主动关闭。
5. **日志与配置备份 (`AppLog`、`LogExporter` & `SettingsBackupManager`)**：提供 4000 行循环日志缓冲、文件轮转、一键复制诊断报告（250KB 安全截断）以及全量设置项的 JSON 导入/导出/重置备份。
6. **全量单元测试 (`Phase6DiagnosticsAndPolishTests`)**：全面覆盖 HUD 格式化、无交互穿透、音频波形合成与压音、连接故障过滤、日志轮转、设置备份导入及横竖屏 DPI 对称性。

**Gate**：性能监控 HUD 穿透显示且指标刷新准确；声道测试器发声与压音正常；日志导出与设置 JSON 备份/恢复闭环验证通过；全部 Phase 1-6 单元测试 100% 通过。

### Phase 7 — Audio Focus, Lockscreen Now Playing Restoration & Microphone Source Routing (P1) [✅ 已完成 (100% 闭环收官)]

1. **彻底修复 iOS 锁屏与控制中心不显示歌曲信息与专辑封面**：
   - 根因消除：彻底移除 `NowPlayingCoordinator`、`PCMAudioPlayer`、`MicrophoneCapture` 中所有 `AVAudioSession.setCategory` 调用里的 `.mixWithOthers` 伴音标志，恢复系统级主媒体播放器锁屏焦点资格。
   - 重构 `NowPlayingCoordinator`：废除局部 `MPNowPlayingSession`，统一使用全局 `MPNowPlayingInfoCenter.default()` 与 `MPRemoteCommandCenter.shared()`，并启用 `UIApplication.shared.beginReceivingRemoteControlEvents()`。
   - 解除 `isAudioSinkEnabled` 拦截门禁：通过 `0.001` 音量的 `keepAlivePlayer` 静音流保活，确保即使声音走手机/车载蓝牙（`AudioOutputTarget == .phone`），iPad 锁屏与控制中心依然实时展示歌曲名、歌手、专辑封面并支持锁屏按键切歌。
   - 修复播放状态刷新：每次收到状态或进度更新，立即同步 `MPNowPlayingInfoCenter.default().playbackState` 并全量更新锁屏信息。
   - 升级 `Channel.ID_MPB (9)` 强类型解析：使用 `PlaybackProto.swift` 的 `ProtoReader` 反序列化 `MediaPlaybackStatus` 与 `MediaMetaData`，防止手机端扩展字段截断 `albumArt` 提取。
2. **新增麦克风设备位置设定 (`MicrophoneSource`) 与车型伪装防断连策略**：
   - 配置模型：新增 `MicrophoneSource`（`.followAudioOutput`、`.ipad`、`.phone`）与 `effectiveUseIpadMic` 计算属性，并在 `SettingsBackupManager` 补齐 `isAutoDpi` 与 `microphoneSource` 的 JSON 导入导出与默认重置。
   - AAP 协议层对标 `open-headunit`：当 `useMic == false` 时，不宣告 Channel 7 麦克风服务，并将 `HeadUnitInfo.vehicleType` 设为 `3` (`MOTORCYCLE`)、`vehicleId` 设为 `"\(vehicleId)-moto"`，强制 Android Auto 使用手机本地/原车蓝牙麦克风收音且不中止握手。
   - 拒收逻辑：若 `!effectiveUseIpadMic`，拒绝启动 `MicrophoneCapture` 并回复状态码 `1`。
3. **主界面与设置联动**：主菜单展示并支持切换麦克风源，切换导致模式变化时在投屏中自动触发重握手。

**Gate**：单元测试 100% 通过（Covering `effectiveUseIpadMic`、Motorcycle 车型伪装协议、`PlaybackProto` 编解码及 JSON 备份往返）；连接后锁屏与控制中心实时显示曲目与封面；切换麦克风模式协议响应无断连。

### Phase 8 — Modern Dual-Column Inset-Grouped Dashboard & Settings Center (P1) [⏳ 待执行]

1. **现代车载卡片式双栏仪表盘主页 (`MainViewController.swift`)**：
   - 顶部品牌与动态状态胶囊栏（带呼吸指示灯状态胶囊、IP 徽标与毛玻璃 Settings 按钮）。
   - 双栏自适应网格（横屏左右双栏、竖屏上下单栏）：左栏直连与扫描主控 Hub，右栏 4 步结构化新手引导卡片。
   - 底部 6 大交互式配置速览磁贴栏（点击直达设置）。
   - 投屏常亮防熄屏（`UIApplication.shared.isIdleTimerDisabled = true`）。
2. **原生 iPadOS 分组设置中心 (`SettingsViewController.swift`)**：
   - 模态弹出 `.insetGrouped` 样式原生控制器，内嵌实时 `DpiPreviewView`、全量音视频管线、智能传感器、网络看门狗与备份管理。

**Gate**：界面视觉对标新能源原生车机设计；全功能设置项平滑交互；投屏常亮与熄屏保护正常。

### Phase 9 — Smart Network Reachability, Twilight Night Mode, Keymap & Decoder Fallback Ladder (P2) [⏳ 待执行]

1. **动态网络常驻监听器 (`NetworkReachabilityMonitor`)**：基于 `NWPathMonitor` 常驻感知 Wi-Fi 断开/接入手机热点，自动刷新网关并触发自动重连。
2. **天文日出日落算法 (`TwilightCalculator`) & GPS 负坐标修复**：NOAA 太阳算法 + 4 分钟防眩光修正日夜切换；修复 AAP 负经纬度补码。
3. **物理键盘与蓝牙方控映射 (`KeymapManager`)**：`UIKeyboardHIDUsage` 到 Android KeyCode 完整映射与转发。
4. **视频硬解运行时阶梯自动降级 (`DecoderConfigLadder`)**：连续解码失败阈值检测，自动降级分辨率/编码格式并重连自愈。

**Gate**：热点切换自动重连秒级生效；负经纬度与日夜切换精准；蓝牙按键操控车机无延迟；解码故障平滑自动降级。

---

## 8. Test strategy

### 8.1 Automated tests (`HeadunitPadTests`)

- **协议分帧与重组测试**：验证 `AapMessageFraming` 与 `AapMessageReassembler` 对跨包分片、乱序及超大报文的重组准确性。
- **屏幕几何与触控映射测试**：验证 `HeadUnitScreenConfig` 与 `TouchCoordinateMapper` 在 `Fit`、`FillMargin`、`Stretch` 及不同 DPI/分辨率下的坐标反算精度。
- **视频解析与自愈测试**：验证 H.264/HEVC 参数集提取（SPS/PPS/VPS）、NAL 分片组装及丢包状态下 `KeyframeRepairTracker` 的状态机转换。
- **音频缓冲与重采样测试**：验证 `AdaptivePcmBuffer` 水位调节、`MixerDuckingEnvelope` 增益曲线以及 `MicPcmDecimator` 48kHz 转 16kHz 输出长度与精度。
- **看门狗与重连测试**：验证 `LinkGapMonitor`、`VideoStarvationPolicy` 与 `AutomaticReconnect` 的超时判定与重连触发逻辑。
- **Phase 6 诊断与体验测试**：验证 HUD 格式化、测试音正弦波采样、连接故障横幅策略、日志导出截断与设置备份 JSON 容错。

### 8.2 Physical device acceptance tests

- 在未越狱的 iPad 真机上安装标准打包的 `.ipa`，配合 Android 手机在 Wi-Fi 局域网与手机个人热点两种环境下实测。
- 验证 4:3 满屏显示、不同 DPI 下的 Coolwalk 分屏切换、HEVC 60fps 流畅度、导航压低音乐音量、语音助手收音、日夜模式自动切换、前后台恢复及断线重连。

---

## 9. Completion criteria

只有同时满足以下所有条件方可宣告整体移植完成：

- 所有 USB 与 TrollStore 私有特权代码已彻底清除，Xcode 编译与全部 XCTest 单元测试 100% 通过。
- Phase 0 至 Phase 6 的所有功能模块均已对照 `open-headunit` 完成移植（核心业务与策略覆盖率达 80% 以上）。
- iPad 真机无线连接下，满屏比例裁切、Coolwalk 分屏预览、HEVC 视频、AAC 多音轨混音压音、麦克风、定位、日夜模式、HUD 导航与外设按键全部通过实机验收。
- 连续无线投屏播放至少 30 分钟、前后台切换及热点闪断重连测试零崩溃。
- `README.md` 与工程文档已同步更新为最新的纯无线安装与使用指南。

---

## 10. Iteration & Hardening Changelog

### Phase 6 Finalization & Core Wireless Hardening (2026-10-16)
- **解决“重开 App 首次连接易失败 / 5277 Server 假死”根因**：
  - `MainViewController.connectionManager(_:didDiscoverDevice:)` 移除重复弹窗与二次连接触发，消除把正在握手的第 1 条连接腰斩的竞态。
  - `TcpHandler.adoptConnection` 同步触发 `delegate?.byteStreamConnectionDidConnect`，彻底消除首包被提前接收覆盖的竞态。
  - `AapTransport` 首包 `VERSION_REQUEST` 延时由 500ms 缩短至 50ms（`initialVersionRequestDelay = 0.05`），重试间隔由 2.0s 优化为 1.2s；第 2 次无响应时触发 `aapTransportDidDetectSilentPeerOnInitialHandshake` 快速破冰机制。
  - `ConnectionManager` 增加在途同端点去重（`SameEndpointConnectPolicy`）；增加对 5277 僵尸 Socket 的 0.25s 自动破冰重拨；增加 `disconnectForAppTermination()` 在 App 退出/断开时即刻发送 `ByeByeRequest`。
- **Auto 模式横竖屏旋转自动切换竖屏分辨率与满屏比例，且触控 100% 零漂移**：
  - 修复 `AnnouncedDensityPolicy` 竖屏 DPI 计算与 `huigMaxDpi` 长短边对称性。
  - 升级 `H264VideoRendererView`：新增 `activeClipView` 独立裁切容器并开启 `clipsToBounds = true`，使用本地 `overscanLayerFrame` 与 `.resize` 填充，彻底消除因 `resizeAspect` 缩小造成的 25% 触控漂移，实现任何分辨率/边距下像素级零漂移。
  - `MainViewController.viewWillTransition` 与 `presentOrientationMenu` 在 Auto 模式跨方向旋转时，自动重新初始化屏幕尺寸并触发平滑无感重握手，秒级完成原生竖屏/横屏切换。
- **Phase 6 纯净版全量交付**：
  - 零悬浮球纯净画面：投屏画面右上角 100% 纯净无遮挡。
  - `PerformanceOverlayView`：仅在用户开启 `Performance HUD: On` 时以黄色等宽字体穿透显示（`isUserInteractionEnabled = false`），实时展示 RES、FPS、RX Mbps、DEC Latency (median/p95)、AUD Buffer、PLI、DROP。
  - `AudioStreamTester`：纯数学合成 16-bit LE PCM 正弦波测试音（支持 Media 440Hz、Guidance 587Hz、System 880Hz 与导航压音序列）。
  - `AudioDiagnostics`：64 条循环事件缓冲环，记录声道生命周期与压音事件。
  - `ConnectionIssues` & `ConnectionIssueBannerPolicy`：自动记录连接失败根因并在主页提供可关闭的建议诊断横幅。
  - `AppLog` & `LogExporter`：内存 4000 行缓冲环与文件轮转日志，一键生成诊断报告与剪贴板导出（250KB 安全截断）。
  - `SettingsBackupManager`：全量配置 JSON 序列化导出、剪贴板一键恢复与恢复出厂设置。
  - `Phase6DiagnosticsAndPolishTests`：全量 Phase 6 单元测试。

---

## 8. Test strategy

### 8.1 Automated tests (`HeadunitPadTests`)

- **协议分帧与重组测试**：验证 `AapMessageFraming` 与 `AapMessageReassembler` 对跨包分片、乱序及超大报文的重组准确性。
- **屏幕几何与触控映射测试**：验证 `HeadUnitScreenConfig` 与 `TouchCoordinateMapper` 在 `Fit`、`FillMargin`、`Stretch` 及不同 DPI/分辨率下的坐标反算精度。
- **视频解析与自愈测试**：验证 H.264/HEVC 参数集提取（SPS/PPS/VPS）、NAL 分片组装及丢包状态下 `KeyframeRepairTracker` 的状态机转换。
- **音频缓冲与重采样测试**：验证 `AdaptivePcmBuffer` 水位调节、`MixerDuckingEnvelope` 增益曲线以及 `MicPcmDecimator` 48kHz 转 16kHz 输出长度与精度。
- **看门狗与重连测试**：验证 `LinkGapMonitor`、`VideoStarvationPolicy` 与 `AutomaticReconnect` 的超时判定与重连触发逻辑。

### 8.2 Physical device acceptance tests

- 在未越狱的 iPad 真机上安装标准打包的 `.ipa`，配合 Android 手机在 Wi-Fi 局域网与手机个人热点两种环境下实测。
- 验证 4:3 满屏显示、不同 DPI 下的 Coolwalk 分屏切换、HEVC 60fps 流畅度、导航压低音乐音量、语音助手收音、日夜模式自动切换、前后台恢复及断线重连。

---

## 9. Completion criteria

只有同时满足以下所有条件方可宣告整体移植完成：

- 所有 USB 与 TrollStore 私有特权代码已彻底清除，Xcode 编译与全部 XCTest 单元测试 100% 通过。
- Phase 0 至 Phase 6 的所有功能模块均已对照 `open-headunit` 完成移植（核心业务与策略覆盖率达 80% 以上）。
- iPad 真机无线连接下，满屏比例裁切、Coolwalk 分屏预览、HEVC 视频、AAC 多音轨混音压音、麦克风、定位、日夜模式、HUD 导航与外设按键全部通过实机验收。
- 连续无线投屏播放至少 30 分钟、前后台切换及热点闪断重连测试零崩溃。
- `README.md` 与工程文档已同步更新为最新的纯无线安装与使用指南。

---

## 10. Iteration & Hardening Changelog

### Phase 5 Hardening & Regression Bugfix (2026-10-16)
- **开屏 2 秒断连修复**：
  - 修复 `UpdateUiConfigRequest (0x8009)`：严格对标 `open-headunit UpdateUiConfigRequest.kt`，`UiConfig` 仅设置 Field 1 (`margins`)，彻底移除 Field 4 (`ui_theme`)，防止手机端 Gearhead 在握手开屏阶段触发协议异常断开连接。
  - `AapTransport` 增加 `isVideoChannelStarted` 门禁，在 `sendUpdateUiConfigRequest` 中拦截首帧前的过早配置包并补发 `VideoFocusNotification (0x8008)`；握手及断连时彻底重置 `startedSensors`、`lastSentNightMode` 与 `isVideoChannelStarted`。
  - 彻底移除 `ConnectionManager.updateNightMode` 中误调用 `sendUpdateUiConfigRequest` 的逻辑，防止日夜模式刷新并发射非法的 0x8009 轰炸。
- **WPP 5299 / 5288 状态机与双模式配对**：
  - 修复 `WppHandshakeSession`：收到 `versionResponse` 时忽略 status（真机常返回 -8），无条件推进到 `.awaitInfoRequest`；在 `.awaitInfoRequest` 增加对 `startResponse` 与 `connectStatus` 的直接响应；增加 3 秒单次超时自动回退机制发送 `WifiStartRequest (Type 1, port: 5288)`。
  - 保持 `5299`（WPP）与 `5288`（AAP Helper）双端口在应用生命周期内常驻同步监听，防止因连接状态重置导致手机无处连入。
  - 修复 `WppMessages.carInfo()`：将 Field 9 `bodyType` 移除（传 `nil`），与 `open-headunit` 协议规范 100% 对齐。
  - 重构主界面无线配对弹窗为双模式切换（`Phone Hotspot / Helper (5288)` 与 `Native QR (Router / Car AP)`），严格拦截假占位符（`02:00:00:00:00:00` / `AA:BB:CC:DD:EE:FF`），提供清晰配置引导。
- **跨方向旋转自适应与触控对齐**：
  - 消除 `MainViewController` 中使用 H.264 SPS 宏块对齐高度（1088）覆盖握手高度（1080）引发的边距畸变 Bug。
  - `HeadUnitScreenConfig.getMargins()` 增加跨方向旋转保护，当分辨率锁定且屏幕旋转导致方向不匹配时，保留已协商边距，避免畸变裁切；`checkAndNotifyMarginDivergence()` 增加方向不匹配拦截。
  - `TouchCoordinateMapper` 在 `.fill` / `.fillMargin` 发生跨方向旋转降级为 `.resizeAspect` 时，增加黑边偏移扣除算法，确保竖屏状态下触控坐标 100% 精确对齐。

### Product Simplification & UI Experience Hardening (2026-10-16)
- **移除前端 QR / 原生 WPP 冗余入口**：
  - 将 `ProjectionSettings.connectionMode` 默认回退值统一设为 `.hotspotServer`，专注于最稳定可靠的手机 `Port 5277 Head Unit Server` 直连与自动扫描链路。
  - 从主界面 `MainViewController` 中彻底移除 `wirelessSetupButton` 与 `presentWirelessSetupModal` 扫码弹窗；从设置菜单中移除 `Connection Mode` 与 `Wireless Setup` 项；保留底层 `QR/` 与 `WPP/` 模块及枚举定义以确保 CI 单元测试 100% 编译与执行通过。
  - 停用 `ConnectionManager` 中的 `wppServer (5299)` 默认常驻启动，避免不必要的端口占用与后台会话竞争。
- **投屏画面 100% 纯净无遮挡**：
  - 彻底删除主视图层级上的悬浮设置按钮（`floatingSettingsButton`）及其布局约束与显隐控制代码。
  - 仅保留挂载在 `homeContentView` 上的主页面设置按钮（`settingsButton`），进入 Android Auto（`.running`）投屏后随主页面自动全屏隐藏，杜绝投屏画面右上角的任何控件遮挡。
- **新增手机端 Head Unit Server 英文新手引导卡片**：
  - 在主页面 `connectButton` 正下方新增圆角卡片 `serverGuideContainer`（`How to Start Head Unit Server on Android`），以清晰地道的 4 步英文指引引导用户：开启 Android Auto 开发者模式、启动 `Head unit server`、开启手机个人热点并连接 iPad。
  - 仅在 `.disconnected` 与 `.error` 状态下展示，连接中与投屏状态下自动隐藏，保证界面清爽高效。

### Phase 6 Production Hardening & Connection Loop Bugfix (2026-10-16)
- **恢复设备发现确认弹窗与防后台抢跑**：
  - 在 `MainViewController` 中恢复弹出 `"Device Found"` `UIAlertController`（含 Connect 与 Cancel），赋予用户主动连接控制权，彻底杜绝后台静默自动连接引发的 Socket 竞争与手机端 5277 服务端半开连接死锁。
  - 在 `.discovering` 与 `.connecting` 状态下展示 `disconnectButton`（`isHidden = false`），允许用户在扫描超时或选错设备时一键取消并重置状态。
- **探活 Socket 解耦与全新独立 TCP 链路**：
  - 彻底废除 `Discovery.probePort` 生成的跨队列 `preparedConnection` 交付给 `TcpHandler.adoptConnection` 的复用逻辑；探活端口成功响应后立即调用 `conn.cancel()` 释放临时探活 Socket。
  - 正式连接始终由 `TcpHandler.connect(host:port:)` 在自身的 `TcpHandler.queue` 上创建带 KeepAlive 的全新干净 TCP 连接，彻底解决调度队列分裂导致的死锁问题。
- **稳态握手时序恢复与消除 1.25s 抢跑自杀**：
  - 将 `AapTransport` 的首包延迟 `initialVersionRequestDelay` 恢复为经真机验证的稳态值 `0.5s`，重试间隔 `versionRetryInterval` 恢复为 `2.0s`，满足手机端 Android Auto 5277 建立连接后异步绑定内部 CarService 读线程所需的 300~500ms 准备时间。
  - 移除在 `versionRequestAttempts == 2` 时过早触发 `aapTransportDidDetectSilentPeerOnInitialHandshake` 强行掐断连接的自杀逻辑，彻底消除每隔 1~2 秒无限断开重连的死循环；仅保留第 2 次尝试时的 `triggerLauncherPokeIfNeeded()`。
- **消除断开连接延迟误杀竞态**：
  - 在 `ConnectionManager.disconnect()` 中移除 `0.1s` 异步延迟，同步调用 `activeConnection?.disconnect()`，杜绝毫秒级内重连时新连接被旧断连回调误杀的竞态 Bug。
- **旋转自适应与触控对齐保护**：
  - `MainViewController.viewWillTransition` 记录 `wasResolutionLocked` 与 `wasCodecPortrait`，仅在连接处于 `.running` 状态且检测到屏幕方向与协商分辨率真正反转时才触发 `0.25s` 防抖重连，避免在握手阶段误触发重连。
- **CI 测试套件 100% 绿色通行**：
  - 更新 `HeadunitPadTests/Phase6DiagnosticsAndPolishTests.swift` 中的时序断言，全量单元测试（Phase 1 至 Phase 6）100% 通过。

### 5277 Connection Handshake Fix & Diagnostic Trace Hardening & App Icon (2026-10-16)
- **探活连接复用与 3.0s 静默双保险重拨**：
  - 修复 `Discovery.probePort`：为探活连接补齐 Keepalive 与端口复用参数；探活成功后保存至 `preparedConnections` 供后续连接直接复用，避免重新 `connect` 引发 5277 单会话状态机挂死；为 `stopScan` 增加 `cancelPrepared: Bool = false` 参数，停止广播扫描时不误杀已探活成功的待连接 Socket。
  - 在 `ConnectionManager.connect(to:userInitiated:)` 中优先提取 `preparedConnection` 并在 `TcpHandler.adoptConnection` 中以非阻塞主线程异步方式通知 delegate，杜绝 `sync` 死锁。
  - 在 `AapTransport.sendVersionRequestWithRetry()` 中建立 3.0s 静默重拨双保险：首包 `0.5s` + 重试 `2.0s`（第 2 包在 2.5s 发出），若在 3.0s 时仍处于 `.waitingForVersion` 且未收到任何来自手机的 RX 报文，则立即触发 `aapTransportDidDetectSilentPeerOnInitialHandshake` 进行全新 TCP 重拨。
- **全链路 AppLog 替换与 AAP 握手轨迹持久化**：
  - 将 `Discovery.swift`、`TcpHandler.swift`、`ConnectionManager.swift`、`AapTransport.swift` 及 `OpenSslTlsHandler.swift` 中的全部 `print` 替换为分级结构化 `AppLog`（含 `tag: "Discovery"`、`tag: "TcpHandler"`、`tag: "ConnectionManager"`、`tag: "AapTransport"`、`tag: "OpenSslTls"`）。
  - 在 `AapTransport.dumpRecentAapTrace` 中将最近 32 条全通道报文按 `[AapTrace]` 输出至 `AppLog.w(..., tag: "AapTrace")`；在 `videoDiagnosticLines` 中输出最近 20 条全通道报文轨迹。
  - `ConnectionManager` 在断连释放 `aapTransport` 前持久化保留 `lastSessionDiagnosticLines`；`LogExporter.generateFullReport()` 新增 `--- CONNECTION & AAP DIAGNOSTICS ---` 板块，完整导出握手与全通道 trace。
- **全新 App Icon 应用图标集成**：
  - 将 AppIcon 转换为标准 1024x1024 24-bit RGB（无 Alpha 透明通道）PNG 格式，更新 `Contents.json` 包含 universal、dark 和 tinted 规格，彻底杜绝 `actool` 编译警告与提交黑底问题。

### Rotation Aspect Distortion Fix via Zero-Disconnect 0x8009 Margin Reflow (2026-10-16)
- **方案 C 零断连 0x8009 跨方向动态 Margin 重排与 1:1 满屏裁剪**：
  - 修复 `HeadUnitScreenConfig.getMargins()` 与 `checkAndNotifyMarginDivergence()`：放开 `.fillMargin` 模式在 `isResolutionLocked` 下跨方向旋转（例如 1920x1080 底层编码流在 3:4 竖屏 iPad 旋转）时的动态边距计算门禁，精准算出竖屏有效视口 `810x1080`（`widthMargin = 1110, heightMargin = 0`），使有效视口比例与屏幕比例（0.75）完全一致，保持 1:1 正方形像素无损满屏显示。
  - 触发 `onMarginsDivergedDetailed` 动态向手机发送 `UpdateUiConfigRequest (0x8009)`，驱动手机 Gearhead 内部布局即时重排适配竖屏，零断连、零闪烁、触控坐标零漂移。
  - 优化 `Auto`（`.system`）方向下的初始推荐 DPI：当协商分辨率短边为 1080p 时钳制推荐 DPI `<= 160`（720p 钳制 `<= 120`，1440p 钳制 `<= 210`），确保旋转至 810px 窄边时拥有充足 dp 宽度展示 Coolwalk 舒展卡片布局。
- **消除 `viewWillTransition` 篡改分辨率与自锁重连 Bug**：
  - 彻底删除在旋转回调中调用 `clearCustomNegotiatedResolution()`、`clearAnnouncedMargins()`、`initScreen(...)` 及 `orientationReconnectTimer` 强行重连的代码，杜绝分辨率被反向篡改为竖屏引发 4.21:1 畸变拉伸的致命 Bug。
  - 仅在旋转动画 alongside 及 completion 中调用 `updateDimensions` 与 `syncVideoAndTouchGeometry()` + `videoRenderer.applyGeometry()`，平滑过渡。
- **物理级 SPS 真实视频流尺寸防变形兜底**：
  - 在 `H264VideoRendererView` 的 `GeometryCache` 中引入 `streamSize: CGSize`；当实际解码流的横竖方向与配置的 `codecWidth x codecHeight` 相反时，强制走 `.resizeAspect` 等比缩放，彻底杜绝任何极端情况下画面被拉长或压扁。
  - 接收到新 SPS 参数集时触发主线程 `applyGeometry()` 确保尺寸即时同步。
- **修复 `reconnectForOrientationChange()` 解锁时机与延迟**：
  - 将分辨率与边距清空移至 `requestGracefulDisconnect` 回调完成、旧连接断开之后执行，避免被自身 `isResolutionLocked` 检查拦截；重连延迟调整为稳态 `0.65s`。
- **HUD 视口与编码分辨率双重显式显示**：
  - 当存在 Margin 裁剪时，Performance Overlay 实时显示有效视口与编码分辨率（例如 `810x1080 (1920x1080)`），清晰呈现裁剪视口状态。
- **单元测试验证**：
  - 在 `Phase1ScreenAndFramingTests` 中新增跨方向动态 Margin 计算、1:1 视口比例、0x8009 边距分发与系统方向 DPI 钳制的全套断言。

