# HeadunitPad-Auto 开发指南 (AGENTS.md)

## 0. 核心开发铁律与自动化构建验证 (CRITICAL MANDATE)

**【最高优先级指令：代码修改 -> 本地/云端测试 -> 自动推送 -> GitHub Actions 云端打包验证 完整闭环】**

在本项目的每一个阶段（Phase）或每一次任务中，当你完成代码编写或修改后，**绝对不允许仅仅停留在“修改完本地文件”就结束汇报**！你必须自主、全自动地执行以下完整的 CI/CD 验证闭环，直到确认云端构建 100% 成功：

1. **全面阅读理解**：在动手写任何一行代码前，必须完整阅读本 `AGENTS.md`、`PRD.md`、当前项目的全部相关源码，以及参考项目 `open-headunit` 的对应实现，确保 100% 理解上下文、协议细节与架构约束。
2. **编写与同步单元测试**：每完成一个模块的新增或重构，必须在 `HeadunitPadTests/` 下编写或更新对应的单元测试（XCTest），确保所有新增逻辑、边界条件和协议解析都有测试覆盖。
3. **同步更新文档**：在每次提交前，必须将当前已完成的功能状态、架构变更同步更新到 `PRD.md`、`AGENTS.md` 和 `README.md` 中。
4. **Git 自动提交与推送**：
   - 检查 `git status` 和 `git diff`，确保没有遗留无用文件、冲突标记或语法错误。
   - 使用清晰的 Commit Message 提交所有更改并推送到远端仓库：`git push origin main`。
5. **自动监控 GitHub Actions 构建直至成功 (Self-Healing CI Loop)**：
   - 推送完成后，立即监控最新触发的 GitHub Actions Workflow（`.github/workflows/build-ipa.yml`）。
   - **如果 GitHub Actions 报错（编译失败、链接错误、测试不通过、打包失败等）**：
     - 立即拉取失败的详细日志，自主定位根本原因并修复代码，再次 Commit & Push，重新监控构建。
     - **严禁将编译失败或测试未通过的代码留给用户！** 必须不断迭代修复，直到 GitHub Actions 显示 **`completed` / `success`（绿灯）**，且成功下载提取出最新的 `dist/HeadunitPad.ipa` 产物后，方可向用户汇报任务完成！

---

## 1. 项目愿景与阶段演进全景图 (Phase 0 ~ Phase 9 Roadmap)

`HeadunitPad-Auto` 旨在将 iPadOS 设备打造为媲美原厂新能源车机与 CarPlay 质感的**免越狱纯无线 Android Auto 车机接收端（Head Unit）**。

| 阶段编号 | 阶段名称 | 核心交付内容 | 当前状态 |
|---|---|---|---|
| **Phase 0** | 工程基建与免越狱适配 | 移除私有 USB 权限，配置普通 Apple ID 免费自签打包与 CI 流水线 | ✅ 已完成 |
| **Phase 1** | 协议层与 1:1 满屏自适应 | Protobuf 编解码、分片重组、`0x8009` 零断连横竖屏动态边距重排、触控零漂移映射 | ✅ 已完成 |
| **Phase 2** | 无线 5277 发现与重连状态机 | 网关直连、并发子网扫描、探活连接零损耗复用、3.0s 静默重拨双保险、看门狗与自动重连 | ✅ 已完成 |
| **Phase 3** | 视频硬解升级与丢包自愈 | `VideoToolbox` H.264/HEVC 硬解、PLI 关键帧自愈、`activeClipView` 局部裁剪与防拉伸护栏 | ✅ 已完成 |
| **Phase 4** | 多音轨混音、AAC 硬解与麦克风 | `AudioToolbox` AAC-LC 硬解、三声道独立混音、导航 30% 自动压音（Ducking）、48k->16k 麦克风降采样 | ✅ 已完成 |
| **Phase 5** | 日夜模式、GPS 与行车解除 | `SensorBatch (0x8003)` 日夜切换、`DrivingStatus = UNRESTRICTED`、CoreLocation GPS 透传 | ✅ 已完成 |
| **Phase 6** | 纯净全屏与诊断工具箱 | 移除投屏遮挡按钮、左上角穿透式 `PerformanceOverlayView`、`AudioStreamTester`、故障横幅、`AppLog` 导出与 JSON 备份、全新 AppIcon | ✅ 已完成 |
| **Phase 7** | **锁屏 Now Playing 修复与麦克风源路由** | **修复 `.mixWithOthers` 导致 iOS 锁屏/控制中心无歌曲信息 Bug、重构 `NowPlayingCoordinator`、新增 `MicrophoneSource`（Follow / iPad / Phone）与恒定 Car (1) 车载身份** | ✅ 已完成 |
| **Phase 8** | **现代车载仪表盘主页与原生分组设置中心** | **重构 `MainViewController` 为双栏卡片式车载仪表盘（含状态呼吸灯胶囊与 6 大配置速览磁贴）、新建 `.insetGrouped` 原生 `SettingsViewController`（内嵌实时 `DpiPreviewView`）、投屏防熄屏常亮** | ✅ 已完成 (100% 闭环收官) |
| **Phase 9** | **智能网络感知、天文日夜、方控映射与解码降级** | **实现 `F8` (`NetworkReachabilityMonitor`)、`F4` (`TwilightCalculator` 日出日落算法 + GPS 负经纬度修复)、`F3` (`KeymapManager` 蓝牙方控/键盘映射)、`F10` (`DecoderConfigLadder` 运行时自动降级闭环)** | 🎯 当前待执行 |

---

## 2. Phase 7 详细架构规范：音频焦点、锁屏 Now Playing 修复与麦克风源动态路由 (P1)

### 2.1 修复 iOS 锁屏与控制中心不显示歌曲信息与专辑封面
- **根因消除（移除 `.mixWithOthers`）**：
  - 在 iOS/iPadOS `MediaPlayer.framework` 规范中，携带 `.mixWithOthers` 的 `AVAudioSession` 会被系统判定为伴音音效，直接剥夺锁屏与控制中心的 Now Playing 展示权限。
  - 必须移除 `NowPlayingCoordinator.swift`、`PCMAudioPlayer.swift`、`MicrophoneCapture.swift` 中所有 `AVAudioSession.setCategory` 调用里的 `.mixWithOthers`：
    - `.playback` 模式统一传 `options: []`；
    - `.playAndRecord` 模式统一传 `options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]`。
  - 在 `PCMAudioPlayer.swift` 的 `routeChangeObserver` 与 `interruptionObserver` 入口检查 `guard ProjectionSettings.isAudioSinkEnabled else { return }`。
- **重构 `NowPlayingCoordinator.swift`**：
  - 移除局部 `MPNowPlayingSession(players:)`，统一使用全局 `MPNowPlayingInfoCenter.default()` + `MPRemoteCommandCenter.shared()` + `UIApplication.shared.beginReceivingRemoteControlEvents()`。
  - 移除 `activate()` 与 `ConnectionManager` 中对 `ProjectionSettings.isAudioSinkEnabled` 的拦截门禁：通过音量 `0.001` 的 `keepAlivePlayer` 静音音频流保活，确保即使 `AudioOutputTarget == .phone`（声音由手机/车载蓝牙输出），iPad 锁屏和控制中心依然能实时显示歌名、专辑封面并支持锁屏按键切歌！
  - 修复 `updatePlaybackState(_:)`：不再仅当 `didChangePlayingState` 为真时才发布，只要收到状态更新或播放进度变化，立即更新 `MPNowPlayingInfoCenter.default().nowPlayingInfo` 并同步设置 `MPNowPlayingInfoCenter.default().playbackState = playbackState.isPlaying ? .playing : .paused`。
- **强类型解析 `Channel.ID_MPB (9)`**：
  - 在 `AapTransport.swift` 的 `handleMediaPlaybackStatus` (`0x8001`) 与 `handleMediaPlaybackMetadata` (`0x8003`) 中，改用 `PlaybackProto.swift` 的 `ProtoReader` + `MediaPlaybackStatus(from:)` / `MediaMetaData(from:)` 进行强类型反序列化，防止未知扩展字段中断 `albumArt` 封面提取。

### 2.2 新增麦克风设备位置设定 (`MicrophoneSource`) 与恒定车载身份统一策略
- **配置模型 (`ProjectionSettings.swift` & `SettingsBackupManager.swift`)**：
  - 新增 `MicrophoneSource` 枚举：
    - `.followAudioOutput = 0`（`"Follow Audio Output"`，默认：当 `audioOutputTarget == .ipad` 时用 iPad 麦克风，为 `.phone` 时用手机麦克风）
    - `.ipad = 1`（`"iPad Microphone"`）
    - `.phone = 2`（`"Phone / Car BT Mic"`）
  - 新增计算属性 `ProjectionSettings.effectiveUseIpadMic: Bool`。
  - 在 `SettingsBackupManager.swift` 的 `SettingsPayload` 中补齐 `isAutoDpi: Bool?` 与 `microphoneSource: Int?` 的 JSON 导入导出与默认重置。
- **AAP 协议层恒定 Car 身份与麦克风动态路由**：
  - 彻底移除摩托车 `vehicleType = 3` 与 `"-moto"` 伪装，避免同一台 iPad 在切换声音/麦克风时被 Android Auto 识别为两台不同设备。
  - 始终保持 `HeadUnitInfo.vehicleType = 1`（`CAR`）与 `vehicleId = "iPad-HeadunitPad"`，并在握手时常驻宣告 `Channel.ID_MIC (7)`。
  - 在 `AapTransport.handleMicrophoneMessage` 中，当 `!ProjectionSettings.effectiveUseIpadMic` 时，拒绝启动 iPad 本地采集并回复错误码 `1`，在语音结束时主动恢复音频焦点，由手机本地麦克风或车载蓝牙 HFP 麦克风平滑收音。

---

## 3. Phase 8 详细架构规范：现代化双栏车载仪表盘主页与原生分组设置中心 (P1)

### 3.1 现代车载卡片式仪表盘主页 (`MainViewController.swift`)
- 彻底升级单调的 `340pt` 窄列堆叠布局，采用自适应宽度（最大 `880pt`）的现代深色/自适应车载卡片仪表盘：
  1. **顶部品牌与动态状态胶囊栏 (Header Bar)**：左侧展示应用图标与标题；中右侧展示带呼吸指示灯的状态胶囊（`Status Pill`：含连接状态文字与当前 `Wi-Fi IP` 徽标）及醒目的毛玻璃胶囊按钮 `Settings`。
  2. **故障诊断横幅 (`ConnectionIssueBannerView`)**：位于 Header 下方，出现故障时平滑展示。
  3. **双栏自适应主控网格 (`UIStackView`)**：横屏下左右双栏并排（`.horizontal`），竖屏下自动切换为上下单栏（`.vertical`）：
     - **左栏（Connection Hub Card）**：包含网关 IP 快速直连输入框（附带一键重置默认网关 IP 按钮 `arrow.counterclockwise`）、`"Direct Connect"` 按钮、以及高对比度主按钮 `"Scan for Headunit Server (Port 5277)"`（连接中展示加载指示器与红色 `"Cancel / Disconnect"` 按钮）。
     - **右栏（Android Server 4-Step Guide Card）**：采用 4 行带 SF Symbols 图标徽章的结构化步骤卡片，清晰引导用户在安卓手机开启开发者模式与 `Head unit server`。
  4. **底部当前配置速览磁贴栏 (Quick Spec Tiles, 6 个交互式磁贴)**：
     - 实时展示：`Display (Resolution & FPS)`、`Layout (FitMode & DPI)`、`Codecs (Video & Audio)`、`Audio Out`、`Microphone`、`Smart Mode (Night & LHD/RHD)`。点击任意磁贴直接打开 `SettingsViewController`。
  5. **车载投屏防熄屏常亮**：在 `updateUIForConnectionState` 中，当 `state == .running` 时设置 `UIApplication.shared.isIdleTimerDisabled = true`，断开返回主页时恢复 `false`。

### 3.2 原生 iPadOS 分组设置视图控制器 (`HeadunitPad/Core/UI/SettingsViewController.swift`)
- 彻底废弃多层嵌套的 `UIAlertController` ActionSheet，新建继承自 `UIViewController`（内嵌 `UITableView(style: .insetGrouped)`）的 `SettingsViewController`，以 `.formSheet` 模态导航弹出：
  - **Section 0: Active Session**（仅在 `.running` 时显示：连接详情与红色一键断开行）。
  - **Section 1: Display & Coolwalk Layout**：
    - 首行直接内嵌实时交互的 `DpiPreviewView`（高度 `200pt`）+ `Auto DPI` `UISwitch` + DPI `UISlider(100...320)` + `[120, 160, 200, 240, 280]` 快捷预设按钮；
    - 下方依次为：`Resolution`、`Frame Rate (60/30 FPS)`、`Display Fit Mode`、`Screen Orientation`、`Driving Position (LHD/RHD)`。
  - **Section 2: Video & Audio Pipeline**：
    - `Video Codec (H.264 / HEVC / Auto)`、`Audio Codec (AAC-LC / PCM)`、`Audio Output (iPad / Phone)`、`Microphone Source (Follow / iPad / Phone)`、以及 `Audio Stream Tester` 入口。
  - **Section 3: Smart Sensors & Night Mode**：
    - `Night Mode (Auto 07-19 / Twilight / Day / Night / System)`、`GPS Source (Phone / iPad)`。
  - **Section 4: Connection & Automation**：
    - `Auto Reconnect` (`UISwitch`)、`Auto Resume Playback` (`UISwitch`)。
  - **Section 5: Diagnostics, Logs & Backup**：
    - `Performance HUD Overlay` (`UISwitch`)、`Live Diagnostics Report`、`Export / Share Session Logs`、`Backup / Restore Settings (JSON)`、`Reset All Settings to Defaults`。

---

## 4. Phase 9 详细架构规范：智能网络感知、天文日夜、方控映射与解码阶梯自愈 (P2)

1. **F8 — 动态网络状态常驻监听器 (`HeadunitPad/Core/Network/NetworkReachabilityMonitor.swift`)**：
   - 基于 `NWPathMonitor` 常驻监听 Wi-Fi 状态（300ms 去抖）：Wi-Fi 断开时立即触发 `ConnectionIssueStore.shared.raise(issue: .wifiRadioOff)`；连上手机热点获取有效 IPv4 后自动清除故障横幅、刷新主页 IP 与默认网关，并在开启 `autoReconnect` 且处于 `.disconnected` 时自动触发 `startDiscovery()`。
2. **F4 — 天文日出日落自动日夜切换 (`HeadunitPad/Core/Location/TwilightCalculator.swift`) & GPS 负坐标修复**：
   - 1:1 移植 `open-headunit` 的 `TwilightCalculator`（NOAA 太阳赤纬/时角算法 + 提前 4 分钟防眩光修正），优先使用最近 GPS 坐标，无 GPS 时按系统时区中心经度离线估算；在 `NightModeSetting` 新增 `.twilight` 模式。
   - 修复 `AapTransport.sendLocationUpdate` 中使用 `max(latitude, 0)` 截断负经纬度的 Bug，改用 `SensorsProto.swift` 的 `SensorBatch(locationData:)` 标准补码编码。
3. **F3 — 物理键盘与蓝牙方控按键映射 (`HeadunitPad/Core/UI/KeymapManager.swift`)**：
   - 建立 `UIKeyboardHIDUsage` 到 Android `KeyCode` 的完整映射（上下左右方向键、Enter、ESC 返回、Home、Space 播放暂停、媒体上一曲/下一曲、V 键唤醒语音助手、`[` / `]` 旋钮滚动），在 `MainViewController` 重写 `pressesBegan` / `pressesEnded` 转发至 `AapTransport.sendKeyEvent`。
4. **F10 — 视频解码运行时阶梯自动降级 (`DecoderConfigLadder` Runtime Fallback)**：
   - 在 `H264VideoRendererView.swift` 监测连续解码失败（`formatFailures` / `sampleFailures` / `displayLayer.status == .failed`），达到阈值时触发 `onDecoderFallbackRequested`，联动 `DecoderConfigLadder.fallbackResolution` 自动下调分辨率（及高分 HEVC 回退 H.264）并重连保活。
