# HeadunitPad-Auto

**Transform your iPad into a native, high-performance Android Auto wireless display.**

> `HeadunitPad-Auto` is a complete 1:1 port of the open-source [`open-headunit`](https://github.com/andrerinas/open-headunit) Android receiver to iPadOS (Swift / UIKit / VideoToolbox / AVFoundation).
> Designed from the ground up for a **100% pure wireless architecture** (Wi-Fi LAN / Personal Hotspot / WPP Wireless Projection Protocol) that requires **no USB cable, no jailbreak, and no TrollStore private entitlements**.
> Simply sideload with standard tools (**AltStore**, **SideStore**, **Sideloadly**, or Xcode personal certificates) onto any modern iPad.

---

## 🌟 Key Highlights

- **Pure Wireless Architecture**:
  - Connects seamlessly via Wi-Fi LAN, Phone Hotspot, or the WPP Wireless Projection Protocol.
  - Subnet client discovery, QR code pairing, and automatic link-loss recovery (`AutomaticReconnect` & `PlaybackSnapshot`).
- **Hardware-Accelerated Video Pipeline**:
  - Native **H.264** and **HEVC / H.265** decoding via Apple's `VideoToolbox`.
  - Supports 480p, 720p, 1080p, 1440p, and 4K presets up to 60 FPS.
  - Configurable screen margins (`Fit`, `FillMargin`, `Stretch`) and Coolwalk DPI adjustment (100–320 DPI) for perfect full-screen display on iPad 4:3 / 3:2 aspect ratios without black bars.
  - Video fragment reassembly and instant keyframe repair on packet loss or app resume.
- **Multi-Stream Audio & Smart Ducking Engine**:
  - Hardware **AAC-LC** decoding and PCM streaming via `AVAudioEngine`.
  - 3 independent audio channels: **Media (Music)**, **Guidance (Navigation/Speech)**, and **System (Sounds)**.
  - Smooth navigation audio ducking (background music automatically ducks to 30% during turn announcements and smoothly ramps back).
  - Soft-clipping limiter and adaptive jitter buffer for jitter-free audio over wireless links.
  - Microphone capture with 48kHz → 16kHz decimator and upstream flow control.
- **Smart Sensors, Location & Geofencing**:
  - Real-time GPS sharing from iPad or phone.
  - Astronomical sunrise/sunset (`TwilightCalculator`) for automatic day/night mode based on your coordinates.
  - Circular geofence manager (`GeofenceLocation`) for automatic dark mode when entering tunnels or underground parking.
  - Driving status policy unblocking in-car keyboard input restrictions (`UNRESTRICTED = 0`).
- **In-Car Navigation HUD & External Input**:
  - Semi-transparent blur HUD card displaying turn maneuvers, distance, and road names.
  - Custom key mapping (`KeymapManager`) with media key debouncing (`KeyDebouncePolicy`) for Bluetooth steering wheel controls and keyboards.
  - Vehicle identity spoofing (Car, Truck, Motorcycle) and custom Make/Model/Year reporting.
- **Diagnostics, HUD Overlays & Backup**:
  - Draggable, edge-snapping floating control button (`FloatingButtonView`) with auto-idle dimming.
  - Real-time performance HUD overlay (`PerformanceOverlayView`) showing FPS, CPU load, thermal state, latency, and bitrate.
  - Standalone audio channel auditioning (`AudioStreamTester`).
  - Diagnostic ring-buffer logger (`AppLog`) and sharing export (`LogExporter`).
  - JSON configuration backup, restore, and reset (`SettingsBackupManager`).

---

## 📐 Architecture Overview

```
HeadunitPad/
├── Core/
│   ├── AAP/
│   │   ├── Proto/                  # Swift Protobuf specifications (Common, Control, Input, Media, etc.)
│   │   ├── Framing/                # AapMessage, AapMessageReassembler, FragmentedMessageAudit
│   │   ├── Channels/               # AapNavigation, AapMediaPlayback
│   │   ├── Messages/               # ServiceDiscoveryResponse, NightModeEvent, DrivingStatusEvent, KeyCodeEvent
│   │   └── Policies/               # LinkGapMonitor, VehicleIdentityPolicy, VehicleTypePolicy
│   ├── Connection/
│   │   ├── ConnectionManager.swift # Wireless state machine, watchdog & reconnection
│   │   ├── TcpHandler.swift        # POSIX/NW socket transport
│   │   ├── OpenSslTlsHandler.swift # Embedded TLS session handshake
│   │   ├── Discovery.swift         # Subnet client & gateway scanner
│   │   ├── WirelessHelperServer.swift
│   │   └── WppServer/              # Wireless Projection Protocol (WPP) TCP Server
│   ├── Video/
│   │   ├── VideoRendererView.swift # Metal / VideoToolbox H.264 & HEVC renderer
│   │   ├── NalParser.swift         # SPS, PPS, VPS parameter set parsing
│   │   ├── VideoFrameBus.swift     # Low-latency pub/sub frame dispatcher
│   │   └── Recovery/               # KeyframeRepairTracker, VideoFragmentAssembler
│   ├── Audio/
│   │   ├── Codec/                  # AacAudioDecoder (AudioConverter AAC-LC -> PCM)
│   │   ├── Mixer/                  # AudioMixer, MixerDuckingEnvelope, SoftClipper, Catalog
│   │   ├── Buffer/                 # AdaptivePcmBuffer, AdaptiveJitterPolicy
│   │   ├── Mic/                    # MicrophoneCapture, MicPcmDecimator (48k -> 16k)
│   │   └── NowPlayingCoordinator.swift # Lock screen & Control Center media metadata
│   ├── SensorsAndLocation/
│   │   ├── LocationCapture.swift   # CoreLocation GPS
│   │   ├── GeofenceManager.swift   # Circular geofences (tunnels & parking)
│   │   ├── NightModeManager.swift  # System, Manual, Twilight & Geofence day/night engine
│   │   ├── TwilightCalculator.swift# Astronomical solar calculation
│   │   └── DrivingStatusPolicy.swift# Enforces UNRESTRICTED = 0 driving status
│   ├── Input/
│   │   ├── TouchCoordinateMapper.swift # Margin-aware touch normalization
│   │   ├── KeymapManager.swift     # Hardware keyboard & Bluetooth wheel control
│   │   └── KeyDebouncePolicy.swift # Debouncing & repeat suppression
│   ├── UI/
│   │   ├── FloatingButtonWindow.swift # Draggable quick-action button
│   │   ├── FloatingButtonOpacityPolicy.swift
│   │   ├── NavigationHudView.swift # Turn-by-turn navigation card
│   │   └── PerformanceOverlayView.swift # Real-time FPS, latency & bitrate overlay
│   ├── Settings/
│   │   ├── ProjectionSettings.swift# ScreenConfig, DPI, Codec, Margins, Vehicle Info
│   │   └── SettingsBackupManager.swift # JSON export & restore
│   └── Diagnostics/
│       ├── AppLog.swift            # Thread-safe ring buffer logger
│       ├── AudioStreamTester.swift # Multi-channel sine wave auditioning
│       ├── ConnectionIssues.swift  # Failure diagnostics & remedies
│       ├── ConnectionIssueBannerPolicy.swift
│       └── LogExporter.swift       # Export & Share sheet
```

---

## 🚀 Getting Started

### Prerequisites

1. An **iPad** (iPad mini 6, iPad Pro, or iPad Air recommended; any iPad running iOS/iPadOS 16.0+ is supported).
2. An **Android smartphone** running Android 9.0+ with **Android Auto** installed.
3. Both devices connected to the **same Wi-Fi network** or the **phone's Personal Hotspot**.

### Wireless Android Auto Setup

1. On your Android phone, enable **Developer settings** in Android Auto:
   - Open Android Auto settings on the phone.
   - Tap the **Version** number 10 times until developer mode is unlocked.
   - Tap the top-right three dots menu `⋮` and select **Start head unit server**.
2. Launch **HeadunitPad-Auto** on your iPad.
3. The app will automatically discover the phone on your local subnet, or you can enter the phone's IP address directly.
4. Tap **Connect** to begin wireless projection!

---

## 🛠️ Building & Packaging

### Building with CocoaPods & Xcode

```bash
# Install CocoaPods dependencies
pod install

# Open the workspace in Xcode
open HeadunitPad.xcworkspace
```

### Creating an Unsigned IPA

To package a standard `.ipa` for AltStore, SideStore, or Sideloadly:

```bash
chmod +x scripts/build_unsigned_ipa.sh
./scripts/build_unsigned_ipa.sh
```

The resulting `HeadunitPad.ipa` will be output to `.build/UnsignedIPA/`.

---

## 🧪 Unit Testing

The test suite covers all 6 phases:

```bash
# Run tests on the iPad Simulator
xcodebuild test \
  -workspace HeadunitPad.xcworkspace \
  -scheme HeadunitPad \
  -destination "platform=iOS Simulator,name=iPad mini (6th generation)" \
  CODE_SIGNING_ALLOWED=NO
```

Test suites included:
- `Phase1ScreenAndFramingTests`: Protobuf framing, reassembler, screen config & DPI policies.
- `Phase2WirelessAndWatchdogTests`: Subnet discovery, WPP handshake, link-gap watchdog & reconnect.
- `Phase3VideoAndRecoveryTests`: NAL parser (H.264 & HEVC), codec selection, keyframe repair tracker.
- `Phase4AudioAndMicTests`: AAC-LC decoding, multi-channel mixer ducking, adaptive jitter buffer, mic decimator.
- `Phase5SensorsAndNavigationTests`: Twilight calculation, geofencing, key debouncing, vehicle identity & nav parsing.
- `Phase6DiagnosticsAndOverlayTests`: Floating button opacity, performance HUD, audio stream testing & settings backup.

---

## 📄 License & Attribution

- Licensed under **AGPL-v3**.
- Ported from [`open-headunit`](https://github.com/andrerinas/open-headunit) by Andre Rinas and Andre Knieriem.
- Android Auto is a trademark of Google LLC.
