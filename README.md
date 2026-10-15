# HeadunitPad-Auto

**Transform your iPad into a Pure Wireless Android Auto Receiver.**

[![Platform](https://img.shields.io/badge/Platform-iPadOS%2016.6%2B-blue?logo=apple)](https://www.apple.com/ipados/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-100%25%20Pure%20Wireless-success)]()
[![Sideloading](https://img.shields.io/badge/Install-AltStore%20%7C%20SideStore%20%7C%20Sideloadly-purple)]()
[![License](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE)

> **HeadunitPad-Auto** turns your iPad (especially iPad mini 6, iPad Air, or iPad Pro) into a high-performance, full-screen Android Auto display over Wi-Fi or phone hotspot.
>
> **100% Pure Wireless & Non-Jailbroken**: Zero private hardware entitlements, no USB cables, and no TrollStore required. You can install it on any regular iPad using standard sideloading tools (AltStore, SideStore, Sideloadly) or a personal Apple ID developer certificate.

---

## Highlights

- **100% Pure Wireless Connection**: Wirelessly stream Android Auto via Phone Hotspot, Local Wi-Fi, or Wireless Projection Protocol (WPP).
- **Edge-to-Edge iPad Display (Fill / Margin Cropping)**: Eliminates 16:9 black letterbox bars on iPad 4:3 and 3:2 displays by reporting custom margins to Android Auto for native full-screen rendering.
- **Coolwalk Split-Screen & Live DPI Preview**: Freely adjust DPI (100–320) to trigger Android Auto Coolwalk multi-card dashboard layouts, complete with an in-app visual layout previewer (`DpiPreviewView`).
- **Dual Hardware Video Decoders (H.264 & HEVC / H.265)**: Apple VideoToolbox hardware-accelerated decoding up to 4K @ 60 FPS with automatic resolution ladder fallbacks.
- **Wireless Packet Loss Healing**: Real-time NAL fragment reassembly and Keyframe Repair Tracker (`KeyframeRepairTracker`) eliminate green screens, mosaic artifacts, and background resume freezes.
- **Multi-Track Audio Engine with Smart Ducking**: AAC-LC hardware decoding + PCM playback via `AVAudioEngine`, managing Media, Navigation Guidance, and System audio streams independently with smooth volume ducking during voice prompts.
- **Voice Assistant Microphone Decimator**: High-quality anti-aliased downsampling (48 kHz iPad mic $\rightarrow$ 16 kHz mono PCM) for responsive Google Assistant speech recognition.
- **Connection Watchdogs & Seamless Auto-Reconnect**: Heartbeat jitter tracking (`LinkGapMonitor`), video starvation detection, exponential backoff reconnect, and automatic music resume.
- **Ergonomics & Navigation**: LHD/RHD driver orientation, HUD turn-by-turn guidance overlay, lockscreen media controls with album artwork (`MPNowPlayingInfoCenter`), and multi-mode day/night switching (System / Astronomical Twilight / GPS Geofencing).

---

## Comparison: HeadunitPad-Auto vs. Legacy HeadunitPad

| Feature | Legacy HeadunitPad | HeadunitPad-Auto (Current) |
| :--- | :--- | :--- |
| **Connection Method** | Wired USB (AOA) + Basic Wi-Fi | **100% Pure Wireless** (Hotspot, LAN, WPP, QR Pairing) |
| **Installation Requirements** | TrollStore & USB Host entitlements | **Standard Sideloading** (AltStore, SideStore, Sideloadly, Free Apple ID) |
| **Display Aspect Ratio** | Fixed 16:9 (Heavy black bars on iPads) | **Native 4:3 / 3:2 Full-Screen** via Protocol Margin Cropping |
| **Touch Precision** | Susceptible to aspect ratio drift | **Sub-pixel Coordinate Reverse-Mapping** (`TouchCoordinateMapper`) |
| **Coolwalk Split-Screen** | Hardcoded DPI | **Dynamic 100–320 DPI** with live visual layout simulator |
| **Video Decoding** | H.264 only | **Hardware H.264 & HEVC (H.265)** via VideoToolbox |
| **Packet Loss Handling** | Stutters or turns green | **Intelligent Keyframe Repair** & corruption concealment |
| **Audio Processing** | Raw PCM only, single track | **AAC-LC Hard-decode + Multi-track Mixer + Auto Ducking** |
| **Voice Recognition** | Basic capture | **48 kHz $\rightarrow$ 16 kHz Anti-aliasing Decimator** for Google Assistant |
| **Night Mode** | Manual toggle | **Follow System, GPS Twilight, or Geofencing (Tunnels)** |
| **Architecture Base** | Custom minimal implementation | **80%+ 1:1 Swift port of `open-headunit`** |

---

## How It Works

### Connection Flow

HeadunitPad-Auto uses a unified `ByteStreamConnection` architecture. Whether connecting over a Phone Hotspot, Local Wi-Fi network, or WPP listener, the transport feeds the Android Auto Protocol (AAP) session identically:

```
┌─────────────────────────────────┐                     ┌─────────────────────────────────┐
│        Android Phone            │                     │          iPad (Receiver)        │
│  (Hotspot or Wi-Fi Client)      │                     │        (HeadunitPad-Auto)       │
└────────────────┬────────────────┘                     └────────────────┬────────────────┘
                 │                                                       │
                 │ ── 1. TCP Handshake (Default Port: 5277) ───────────► │
                 │ ◄─ 2. AAP Version Negotiation (v1.6) ───────────────► │
                 │ ◄─ 3. OpenSSL TLS Handshake (AAP Channel 0, Type 3) ─► │
                 │ ── 4. Service Discovery Request ────────────────────► │
                 │ ◄─ 5. Service Discovery Response (DPI, Margin, Codec) │
                 │ ── 6. Channel Open Requests (Video, Audio, Input, Mic)►│
                 │                                                       │
                 │ ════════════════ Encrypted AAP Streams ══════════════ │
                 │ ── Video Stream (H.264 / HEVC) ─────────────────────► │ ── VideoToolbox Hardware Decode
                 │ ── Audio Stream (AAC-LC / PCM) ─────────────────────► │ ── AudioMixerEngine & Ducking
                 │ ◄─ Multi-Touch Events (Normalized Coordinates) ────── │ ◄─ TouchCoordinateMapper
                 │ ◄─ Voice Input (16 kHz Resampled PCM) ─────────────── │ ◄─ MicPcmDecimator
                 │ ◄─ Sensor & Driving Status (Unrestricted) ─────────── │ ◄─ Location & Twilight Policy
                 │ ◄─ Heartbeat Ping/Pong Watchdogs ───────────────────► │ ◄─ LinkGapMonitor & Recovery
```

### Channel Breakdown

| Channel | Identifier | Purpose | Description |
| :---: | :---: | :---: | :--- |
| **0** | Control | Session Lifecycle & TLS | Encapsulates OpenSSL TLS handshake, version exchange, ping/pong |
| **1** | Sensors | Vehicle & Environment | GPS location, day/night mode, and unrestricted driving status |
| **2** | Video | Video Streaming | H.264 / HEVC video frames decoded via `AVSampleBufferDisplayLayer` |
| **3** | Input | Touch & Peripherals | Multi-touch pointers, keypresses, rotary knob, and scroll events |
| **4** | Media Audio | Music & Podcasts | High-fidelity music stream (AAC-LC or PCM 48 kHz stereo) |
| **5** | Guidance Audio | Navigation Prompts | Turn-by-turn spoken directions with automatic ducking |
| **6** | System Audio | Alerts & Notifications | System chimes and ringtones |
| **7** | Microphone | Voice Input | Upstream voice stream decimated to 16 kHz mono PCM |

---

## Features in Detail

### 1. iPad Edge-to-Edge Display & Coolwalk Split-Screen
Most iPads feature a 4:3 or 3:2 aspect ratio, whereas Android Auto outputs 16:9 by default, producing unsightly black bars on the top and bottom.
- **Protocol-Level Margin Cropping (`FillMargin`)**: The app calculates `width_margin` and `height_margin` dynamically and advertises them in `ServiceDiscoveryResponse`. Android Auto renders directly into the target active viewport, giving you a full-screen experience with zero geometric distortion.
- **Accurate Touch Reverse-Mapping (`TouchCoordinateMapper`)**:
  $$\text{X}_{\text{AA}} = \frac{\text{widthMargin}}{2} + \text{normX} \times (\text{containerWidth} - \text{widthMargin})$$
  Ensures every touch, tap, drag, and pinch aligns pixel-perfectly with Android Auto UI elements.
- **Dynamic Coolwalk DPI & Live Visual Preview**: Adjust DPI between `100` and `320`. The built-in `DpiPreviewView` renders an accurate simulation of Android Auto's Coolwalk dashboard (sidebar, multi-card split layout, status bar) in real-time before you connect.

### 2. Low-Latency Video Pipeline with Wireless Packet Loss Healing
- **H.264 & HEVC (H.265) Hardware Decoding**: Native hardware decoding powered by Apple's `VideoToolbox`. HEVC cuts wireless bandwidth usage by up to 50% for pristine 1080p and 1440p 60fps streaming.
- **Keyframe Repair Tracker (`KeyframeRepairTracker`)**: Wireless Wi-Fi connections can occasionally drop UDP/TCP packets. The video pipeline actively monitors NAL sequence continuity:
  - Immediately conceals corrupted frames to prevent jarring green screens or macroblock tears.
  - Automatically sends rapid keyframe refresh requests (`VideoFocusEvent`) to restore smooth playback within fractions of a second.
- **Warm Relaunch Recovery**: When returning to HeadunitPad from the iPad home screen or another app, the video feed instantly requests a keyframe refresh, eliminating frozen video frames.

### 3. Multi-Track Audio Engine with Smart Ducking
- **Hardware AAC-LC Decoding**: Decodes compressed wireless audio frames via `AVAudioConverter` alongside uncompressed PCM.
- **Independent Channels**: `Media`, `Guidance`, and `System` streams are mixed independently inside `AudioMixerEngine`.
- **Navigation Ducking (`MixerDuckingEnvelope`)**: When Google Maps or Waze speaks a direction on the Guidance channel, background music volume is smoothly attenuated (ducked) to 30%, then seamlessly restored once navigation finishes.
- **Adaptive Jitter Buffer (`AdaptivePcmBuffer`)**: Dynamic watermark management compensates for Wi-Fi timing jitter, preventing clicks, pops, and audio buffer underruns.

### 4. Smart Sensors & Peripherals
- **Multi-Mode Day/Night Switching**:
  1. Follow iPadOS System Dark/Light appearance
  2. Force Day / Force Night mode
  3. **Astronomical Twilight**: Automatically calculates sunrise and sunset based on GPS coordinates
  4. **Geofencing**: Automatically engages night mode when entering designated tunnels or underground parking areas
- **Unrestricted Driving Status**: Continuously asserts unrestricted parking status so soft keyboards and text inputs remain accessible while stopped.
- **Lockscreen Media Synchronization (`NowPlayingCoordinator`)**: Syncs currently playing track title, artist, album name, and album artwork with iOS Control Center and lockscreen playback controls.
- **External Keyboards & Steering Wheel Controls**: Supports hardware keyboard shortcuts, Bluetooth steering wheel buttons, and trackpad/mouse scroll wheel emulation for car knob control.

---

## Connection Modes

| Mode | Best For | Description |
| :--- | :--- | :--- |
| **Hotspot Server Mode** *(Recommended)* | In-Car Driving | Enable Personal Hotspot on your Android phone, connect the iPad to the hotspot, and HeadunitPad automatically connects to the gateway IP (`192.168.43.1` or detected hotspot gateway) on port `5277`. |
| **Auto Wireless (WPP / Discovery)** | Home / Office Wi-Fi | Scans local subnet or listens on the Wireless Projection Protocol (WPP) port for compatible Android Auto clients. |
| **Manual IP Direct** | Custom Subnets | Enter any phone IP and port directly, with connection history memory. |
| **QR Code Pairing** | Quick Setup | Generates a quick pairing QR code containing connection parameters. |

---

## Getting Started

### Prerequisites

1. **iPad**: Any iPad running **iPadOS 16.6 or later** (iPad mini 6, iPad Pro, iPad Air, or standard iPad).
2. **Android Phone**: Running Android 11+ with Android Auto installed.
3. **Connectivity**: Wi-Fi network or Phone Mobile Hotspot (no internet connection required for the projection itself).

### In-Car Hotspot Setup (Recommended)

1. On your Android phone:
   - Turn on **Personal Hotspot**.
   - Open **Android Auto Settings** $\rightarrow$ scroll to Version $\rightarrow$ tap 10 times to unlock **Developer Settings** $\rightarrow$ tap the 3 dots in the top right $\rightarrow$ select **Start Head Unit Server**.
     *(Alternatively, use Headunit Revived's companion Wireless Helper app).*
2. On your iPad:
   - Connect Wi-Fi to your Android phone's Personal Hotspot.
   - Launch **HeadunitPad**.
   - Tap **Connect** (or tap **Direct Connect** with the auto-filled gateway IP).
   - Grant Local Network and Microphone permissions on first launch.
3. Android Auto will start projecting onto your iPad screen within seconds!

---

## Installation & Sideloading

Because HeadunitPad-Auto requires **no private entitlements and no jailbreak**, you can install it using any standard iOS sideloading method:

### Option 1: AltStore / SideStore / Sideloadly (Recommended)

1. Download the latest `HeadunitPad.ipa` from the [Releases](https://github.com/andyching168/HeadunitPad/releases) page or from the GitHub Actions CI artifact.
2. Sideload the IPA onto your iPad using:
   - [AltStore](https://altstore.io/)
   - [SideStore](https://sidestore.io/)
   - [Sideloadly](https://sideloadly.io/)
3. On your iPad, navigate to **Settings $\rightarrow$ General $\rightarrow$ VPN & Device Management** and trust your developer certificate.
4. Open HeadunitPad and enjoy!

### Option 2: Build from Source with Xcode

1. Clone this repository:
   ```bash
   git clone https://github.com/andyching168/HeadunitPad-Auto.git
   cd HeadunitPad-Auto
   ```
2. Install CocoaPods dependencies:
   ```bash
   pod install
   ```
3. Open `HeadunitPad.xcworkspace` in Xcode.
4. Select the `HeadunitPad` target, navigate to **Signing & Capabilities**, and select your Apple Developer Team.
5. Connect your iPad, select it as the run destination, and click **Run** ($\mathbf{\Command + R}$).

### Option 3: Build Unsigned IPA via Script

If you want to package an unsigned `.ipa` for distribution or personal signing:

```bash
chmod +x scripts/build_unsigned_ipa.sh
./scripts/build_unsigned_ipa.sh
```

The script compiles the project in Release configuration, packages the `.app` bundle into a clean `.ipa`, and validates that no private entitlements are present.

---

## Project Architecture

```text
HeadunitPad/
├── AppDelegate.swift
├── SceneDelegate.swift
├── MainViewController.swift          # Primary UI, connection states & gesture routing
├── VideoOnlyViewController.swift     # Immersive video projection view with HUD
├── TrackpadViewController.swift      # Rotary knob & trackpad input simulation
└── Core/
    ├── AAP/                          # Android Auto Protocol layer
    │   ├── AapTransport.swift        # Encapsulated TLS & message pump
    │   ├── AapMessage.swift          # Message framing & header packing
    │   ├── Framing/                  # Multi-channel reassembly & audit
    │   ├── Proto/                    # Protobuf message serialization
    │   ├── Messages/                 # ServiceDiscovery, UIConfig, TouchEvent
    │   └── Watchdog/                 # LinkGapMonitor, VideoStarvation, AutoReconnect
    ├── Network/                      # Networking & transport abstraction
    │   ├── ByteStreamConnection.swift# Stream protocol interface
    │   ├── TcpHandler.swift          # Active TCP client
    │   ├── OpenSslTlsHandler.swift   # OpenSSL TLS implementation
    │   ├── Discovery.swift           # Subnet scanning & Bonjour
    │   ├── WPP/                      # Wireless Projection Protocol server
    │   ├── Arbiter/                  # Connection lifecycle state machine
    │   └── Discovery/                # Gateway formatting & reconnect policies
    ├── Video/                        # Video decoding & rendering
    │   ├── H264VideoRendererView.swift# VideoToolbox display layer
    │   ├── H264NALParser.swift       # H.264 / HEVC NAL parser
    │   ├── VideoFrameBus.swift       # Frame backpressure & queue management
    │   ├── Codec/                    # Codec selection & capability profiling
    │   └── Recovery/                 # KeyframeRepairTracker & corruption recovery
    ├── Audio/                        # Audio decoding & mixing
    │   ├── PCMAudioPlayer.swift      # Audio engine & multi-channel routing
    │   ├── NowPlayingCoordinator.swift# iOS Lockscreen NowPlaying sync
    │   ├── Codec/                    # AAC-LC decoder & sync watchdog
    │   ├── Mixer/                    # AudioMixer with Ducking & SoftClipper
    │   ├── Buffer/                   # Adaptive jitter buffer & latency recovery
    │   └── Mic/                      # 48kHz -> 16kHz decimator & flow control
    ├── Settings/                     # User preferences & display geometry
    │   ├── ProjectionSettings.swift  # Resolution, FPS, DPI, Codec, Margins
    │   ├── HeadUnitScreenConfig.swift# Dynamic aspect ratio & geometry calculator
    │   └── VideoFitPolicy.swift      # FillMargin / Fit / Stretch modes
    ├── UI/                           # Interactive UI components
    │   ├── DpiPreviewView.swift      # Coolwalk split-screen DPI visualizer
    │   ├── TouchCoordinateMapper.swift# Precise touch reverse-mapping
    │   ├── TouchInputView.swift      # Multi-pointer touch overlay
    │   └── QR/                       # Pair code generator & deep links
    └── Location/
        └── LocationCapture.swift     # CoreLocation GPS provider
```

---

## Settings Reference

Access the settings menu by tapping the gear icon on the home screen:

- **Display Fit Mode**:
  - `Fill (Margin Crop)` *(Recommended for iPads)*: Protocol-level edge cropping for seamless edge-to-edge display with no distortion.
  - `Fit`: Preserves original 16:9 ratio with letterbox bars.
  - `Stretch`: Stretches video to fill screen dimensions.
- **Coolwalk Split-Screen & DPI Preview**: Interactive visual editor to select DPI (100–320). See your Coolwalk layout changes update in real time.
- **Video Codec**: Choose between `Auto`, `H.264`, or `HEVC (H.265)`.
- **Audio Codec**: Choose between `Auto`, `AAC-LC` (low bandwidth), or `PCM` (uncompressed).
- **Resolution**: Supports `Auto`, `480p`, `720p`, `1080p`, `1440p`, and `4K`.
- **FPS**: Choose `60 FPS` or `30 FPS`.
- **Driving Position**: Toggle between `LHD` (Left-Hand Drive) and `RHD` (Right-Hand Drive).
- **GPS Source**: Select `Phone GPS` or `iPad GPS` (cellular iPad models with GPS hardware).
- **Auto Reconnect**: Automatically re-establishes connection and resumes music playback if Wi-Fi drops.

---

## Troubleshooting

<details>
<summary><b>The app shows "iPad IP: No Wi-Fi"</b></summary>

Ensure your iPad is connected to your phone's personal hotspot or the same Wi-Fi router. When prompted on first launch, grant HeadunitPad permission to access the **Local Network** (Settings $\rightarrow$ Privacy & Security $\rightarrow$ Local Network $\rightarrow$ HeadunitPad).
</details>

<details>
<summary><b>Android Auto does not connect / Connection Refused</b></summary>

Ensure the Android Auto Head Unit Server is running on your phone:
1. Open Android Auto Settings on your phone.
2. Tap the three dots in the top right corner and verify that **Start Head Unit Server** has been selected.
3. If using Personal Hotspot, verify the IP address matches your phone's hotspot gateway (commonly `192.168.43.1` or `172.20.10.1`).
</details>

<details>
<summary><b>Audio stutters or drops over Wi-Fi</b></summary>

HeadunitPad includes an **Adaptive Jitter Buffer**. If your environment has significant 2.4 GHz interference, switch your phone's hotspot to the **5 GHz band** in hotspot settings for lower latency and jitter.
</details>

<details>
<summary><b>Touch position is offset on the screen</b></summary>

Ensure your Display Fit Mode is set to `Fill (Margin Crop)`. HeadunitPad automatically synchronizes touch coordinates with the negotiated margin boundaries. If using custom resolutions, allow 1–2 seconds for the geometry handshake to finish.
</details>

---

## Disclaimers

This project is an independent open-source receiver intended for personal, educational, and research use.
- Android Auto is a trademark of Google LLC.
- Apple, iPad, iPadOS, and VideoToolbox are trademarks of Apple Inc.
- This project is not affiliated with, authorized, or endorsed by Google LLC or Apple Inc.

---

## Acknowledgments

- **[open-headunit](https://github.com/open-headunit/open-headunit)** by André Rinas & contributors: The foundational reference architecture, Protobuf definitions, and policies that made this complete port possible.
- **[Headunit Revived](https://github.com/andreknieriem/headunit-revived)** by Andre Knieriem: The Android Auto Server engine powering wireless projection.
- **Mike Reid** (In Memoriam): Original [Headunit](https://github.com/mikereidis/headunit) developer whose groundbreaking protocol reverse-engineering paved the way for the open-source Android Auto ecosystem.
- **[OpenSSL](https://www.openssl.org/)** & [OpenSSL-Universal](https://github.com/krzyzanowskim/OpenSSL): Industry-standard TLS cryptography toolkit.

---

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See the [LICENSE](LICENSE) file for full details.

