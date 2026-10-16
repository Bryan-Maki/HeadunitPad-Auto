# HeadunitPad-Auto

**Transform your iPad into a High-Performance, Pure Wireless Android Auto Receiver.**

[![Platform](https://img.shields.io/badge/Platform-iPadOS%2016.6%2B-blue?logo=apple)](https://www.apple.com/ipados/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-100%25%20Pure%20Wireless-success)]()
[![Sideloading](https://img.shields.io/badge/Install-AltStore%20%7C%20SideStore%20%7C%20Sideloadly%20%7C%20TrollStore-purple)]()
[![CI Build](https://github.com/andyching168/HeadunitPad-Auto/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/andyching168/HeadunitPad-Auto/actions)
[![License](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE)

---

## Overview

**HeadunitPad-Auto** is a native, high-performance wireless Android Auto Head Unit receiver built specifically for iPadOS. Engineered to benchmark against the core protocol stack and policy engine of [open-headunit](https://github.com/open-headunit/open-headunit), it transforms any regular iPad (especially iPad mini 6, iPad Air, or iPad Pro) into a responsive, edge-to-edge in-car dashboard display.

By completely decoupling from private USB accessory entitlements (`com.apple.developer.usb`) and jailbreak/TrollStore requirements, **HeadunitPad-Auto** runs seamlessly inside the standard iOS application sandbox. It can be installed using popular sideloading utilities (AltStore, SideStore, Sideloadly) or a personal Apple ID developer certificate.

---

## Key Features

### 1. Pure Wireless 5277 Headunit Server Engine
- **Direct & Zero-Overhead Connection**: Connects directly to Android Auto's native Head Unit Server on TCP port `5277` over personal hotspot or local Wi-Fi.
- **Smart Concurrent Subnet Probing**: Automatically discovers the head unit server across subnet ranges, featuring probe socket zero-loss reuse and a 3.0-second silent redial dual-insurance mechanism.
- **One-Tap Direct Connect**: Automatically identifies phone hotspot gateway addresses (`192.168.43.1`, `172.20.10.1`, etc.) for instant, zero-configuration connection.

### 2. Zero-Disconnect Orientation Adaptation & 1:1 Full-Screen Display
- **Edge-to-Edge Margin Cropping (`FillMargin`)**: Eliminates 16:9 black letterbox bars on iPad 4:3 and 3:2 displays by reporting custom geometric margins to Android Auto for native full-screen rendering without distortion.
- **Dynamic Cross-Orientation Margin Reflow**: When rotating the iPad between landscape and portrait, the app dynamically dispatches `UpdateUiConfigRequest (0x8009)` across the video channel and adjusts `overscanLayerFrame` clipping in real time—**no session teardown, no reconnection, and zero aspect distortion**.
- **Pixel-Perfect Touch Reverse-Mapping**: The `TouchCoordinateMapper` accurately reverse-maps normalized UIKit touch points to Android Auto display coordinates:
  $$\text{X}_{\text{AA}} = \frac{\text{widthMargin}}{2} + \text{normX} \times (\text{containerWidth} - \text{widthMargin})$$
- **Multi-Touch & Pinch-to-Zoom**: Full multi-pointer tracking supporting fluid two-finger map gestures (pinch-to-zoom, pan, rotate).

### 3. Hardware-Accelerated Low-Latency Video Pipeline
- **Dual Hardware Video Decoders (H.264 & HEVC / H.265)**: Native hardware-accelerated video decoding via Apple's `VideoToolbox` (`VTDecompressionSession` + `AVSampleBufferDisplayLayer`) supporting up to 4K @ 60 FPS. HEVC cuts wireless bandwidth consumption by up to 50%.
- **Wireless Packet Loss Healing**: Active NAL continuity monitoring via `KeyframeRepairTracker`. If packet drop occurs over Wi-Fi, corrupted frames are concealed immediately and Picture Loss Indication (PLI / `VideoFocusEvent`) keyframe refreshes are requested within milliseconds to prevent green screens or macroblocking.
- **Warm Relaunch Recovery**: Automatically requests a fresh keyframe when returning to the app from background or multitasking.

### 4. Multi-Track Audio Engine with Smart Ducking
- **Independent Audio Channels**: Managed by `AVAudioEngine`, routing Media (`Channel.ID_AUD`), Guidance (`Channel.ID_AU1`), and System alerts (`Channel.ID_AU2`) separately.
- **Navigation Audio Ducking**: Background music volume smoothly attenuates to 30% during turn-by-turn voice prompts (`MixerDuckingEnvelope`) and seamlessly restores once speech finishes.
- **Dual Audio Codec Support**: Supports compressed AAC-LC hardware decoding via `AudioToolbox` alongside raw PCM.
- **Anti-Aliased Microphone Decimator**: Downsamples the iPad's 48 kHz hardware microphone input to 16 kHz mono PCM (`MicPcmDecimator`) with chunk accumulation for Google Assistant voice input.

### 5. Day/Night Mode & Sensor Interlock
- **Multi-Mode Lighting**: Sends `SensorBatch (0x8003)` over `Channel.ID_SEN (1)` supporting:
  - **Auto**: Timed switching between 07:00 and 19:00.
  - **System**: Follows iPadOS Dark/Light appearance.
  - **Day / Night**: Manually forces light or dark map themes.
- **CoreLocation GPS Passthrough**: Streams real-time latitude, longitude, altitude, bearing, and speed from cellular iPad GPS to Android Auto navigation apps.
- **Unrestricted Driving Status**: Asserts `DrivingStatus = UNRESTRICTED (0)` upon channel negotiation, permanently bypassing phone keyboard input lockouts while stopped or parked.
- **Bi-Directional Media Synchronization**: Synchronizes track title, artist, album name, and album artwork with iOS Control Center and Lockscreen via `MPNowPlayingInfoCenter`, and relays remote playback commands (play/pause/prev/next).

### 6. Distraction-Free Fullscreen & Phase 6 Diagnostics
- **100% Clean Projection Viewport**: Zero floating buttons or translucent balls obstructing your in-car map display. The settings button is exclusively accessible from the home screen.
- **Pass-Through Performance HUD**: A translucent top-left overlay providing real-time FPS, incoming bitrate (Mbps), frame size, decode latency, and link health without blocking touch interactions.
- **Independent Audio Stream Tester**: Built-in 440 Hz / 880 Hz / 1200 Hz tone generator to test Media, Guidance, System streams and ducking behavior individually.
- **Connection Issue Diagnostic Banner**: Real-time diagnostic banner displaying actionable troubleshooting guidance when port 5277 is refused or TLS handshake encounters issues.
- **Full AppLog Sharing & JSON Configuration Backup**: Export ring-buffered application logs via the iOS system Share Sheet, with full JSON settings export, restore, and reset capabilities.

---

## Architecture & Channel Breakdown

```
┌─────────────────────────────────┐                     ┌─────────────────────────────────┐
│        Android Phone            │                     │          iPad (Receiver)        │
│    (Hotspot / Wi-Fi Client)     │                     │        (HeadunitPad-Auto)       │
└────────────────┬────────────────┘                     └────────────────┬────────────────┘
                 │                                                       │
                 │ ── 1. TCP Connection (Target Port: 5277) ───────────► │
                 │ ◄─ 2. AAP Version Negotiation (v1.6) ───────────────► │
                 │ ◄─ 3. OpenSSL TLS Handshake (Channel 0, Type 3) ────► │
                 │ ── 4. Service Discovery Request ────────────────────► │
                 │ ◄─ 5. Service Discovery Response (DPI, Margin, Codec) │
                 │ ── 6. Channel Open Requests (Video, Audio, Input, Mic)►│
                 │                                                       │
                 │ ════════════════ Encrypted AAP Streams ══════════════ │
                 │ ── Video Stream (H.264 / HEVC) ─────────────────────► │ ── VideoToolbox Hardware Decode
                 │ ── Audio Stream (AAC-LC / PCM) ─────────────────────► │ ── AVAudioEngine & Ducking
                 │ ◄─ Multi-Touch Events (Normalized Coordinates) ────── │ ◄─ TouchCoordinateMapper
                 │ ◄─ Voice Input (16 kHz Resampled PCM) ─────────────── │ ◄─ MicPcmDecimator
                 │ ◄─ Sensor & Driving Status (Unrestricted) ─────────── │ ◄─ SensorBatch (0x8003)
                 │ ◄─ Dynamic Margin Reflow ──────────────────────────── │ ◄─ UpdateUiConfig (0x8009)
                 │ ◄─ Heartbeat Ping/Pong Watchdogs ───────────────────► │ ◄─ LinkGapMonitor & Recovery
```

### AAP Channel Mapping

| Channel ID | Identifier | Purpose | Description |
| :---: | :---: | :---: | :--- |
| **0** | `ID_CTR` (Control) | Session Lifecycle & TLS | OpenSSL TLS handshake, version exchange, service discovery, ping/pong |
| **1** | `ID_SEN` (Sensors) | Vehicle & Environment | GPS coordinates, speed, day/night mode, and unrestricted driving status |
| **2** | `ID_VID` (Video) | Video & Dynamic UI | H.264 / HEVC hardware decoding, dynamic margin updates (`0x8009`), keyframe requests |
| **3** | `ID_INP` (Input) | Touch & Media Keys | Multi-pointer touch reports (`TouchEvent`), remote media key events (`KeyEvent`) |
| **6** | `ID_AUD` (Media) | Music & Audio | High-fidelity 48 kHz stereo audio stream (AAC-LC or uncompressed PCM) |
| **4** | `ID_AU1` (Guidance) | Spoken Navigation | 16 kHz mono turn-by-turn prompts, triggers smooth media ducking |
| **5** | `ID_AU2` (System) | System Audio | 16 kHz mono system notification chimes and ringtones |
| **7** | `ID_MIC` (Microphone) | Voice Input | 48 kHz $\rightarrow$ 16 kHz decimated mono PCM upstream audio |
| **9** | `ID_MPB` (Media Playback) | Playback Metadata | Track title, artist, album name, and album artwork synced to iOS Lockscreen |
| **10**| `ID_NAV` (Navigation) | Navigation Metadata | Next turn road name, maneuver icon, distance, and ETA |

---

## How to Start Head Unit Server on Android

Connecting requires only four simple steps:

```
  [Step 1: Developer Mode] ──► [Step 2: Start Server] ──► [Step 3: Enable Hotspot] ──► [Step 4: Connect on iPad]
```

### Step 1: Unlock Android Auto Developer Settings
1. On your Android phone, go to **Settings** $\rightarrow$ search for **Android Auto**.
2. Scroll to the bottom to find the **Version** information.
3. **Tap the Version information 10 consecutive times** until a prompt confirms Developer Mode has been enabled.

### Step 2: Start Head Unit Server
1. In Android Auto settings, tap the **three dots menu (⋮)** in the top right corner.
2. Select **Start head unit server**. A persistent notification will appear in your Android notification shade confirming the server is running.

### Step 3: Enable Personal Hotspot
1. Turn on **Personal Hotspot** on your Android phone (5 GHz AP band recommended for optimal low-latency streaming).
2. Connect your iPad's Wi-Fi to this hotspot network.

### Step 4: Launch HeadunitPad & Connect
1. Open **HeadunitPad** on your iPad.
2. The app automatically detects the hotspot gateway address (e.g., `192.168.43.1` or `172.20.10.1`).
3. Tap **Direct Connect (Phone Hotspot IP)** or tap **Scan for Headunit Server (Port 5277)**.
4. On first launch, grant **Local Network** and **Microphone** permissions when prompted by iPadOS. Android Auto projection will start within 1–2 seconds!

---

## Installation & Sideloading

Because HeadunitPad-Auto requires **no private entitlements and no jailbreak**, you can install it on any iPad running iPadOS 16.6 or later:

### Option 1: Sideloading via AltStore / SideStore / Sideloadly (Recommended)

1. Download the unsigned `HeadunitPad.ipa` artifact from the latest [GitHub Actions](https://github.com/andyching168/HeadunitPad-Auto/actions) run or release page.
2. Install the IPA onto your iPad using your preferred sideloading utility:
   - **[AltStore](https://altstore.io/)** / **[SideStore](https://sidestore.io/)**: Wireless on-device refreshing.
   - **[Sideloadly](https://sideloadly.io/)**: One-click desktop signing and installation.
   - **[TrollStore](https://github.com/opa334/TrollStore)** (if supported by your iOS version): Permanent installation without certificate expiration.
   - **Personal Apple ID / Developer Certificate**: Re-sign with Xcode or iOS App Signer.
3. On your iPad, navigate to **Settings $\rightarrow$ General $\rightarrow$ VPN & Device Management** and trust your developer certificate.

### Option 2: Build from Source with Xcode

1. Clone the repository:
   ```bash
   git clone https://github.com/andyching168/HeadunitPad-Auto.git
   cd HeadunitPad-Auto
   ```
2. Install CocoaPods dependencies:
   ```bash
   pod install
   ```
3. Open `HeadunitPad.xcworkspace` in Xcode.
4. Select the `HeadunitPad` target, go to **Signing & Capabilities**, and select your personal Apple ID or Developer Team.
5. Select your iPad as the run destination and click **Run** ($\mathbf{\Command + R}$).

### Option 3: Package Unsigned IPA via Script

Build an unsigned IPA package locally using the provided release packaging script:

```bash
chmod +x scripts/build_unsigned_ipa.sh
./scripts/build_unsigned_ipa.sh build_output
```

The script compiles the project in Release configuration, strips code signatures, verifies entitlement purity, and produces an unsigned `.ipa` ready for sideloading.

---

## Settings Reference

Access the settings menu by tapping the gear icon on the home screen (the projection view remains completely clean and button-free):

| Setting | Options | Description |
| :--- | :--- | :--- |
| **Display Fit Mode** | `Fill (Margin Crop)` *(Default)*, `Fit`, `Stretch` | `Fill (Margin Crop)` reports custom margins to Android Auto for native full-screen rendering on 4:3 iPads without distortion; `Fit` preserves original 16:9 ratio with letterbox bars; `Stretch` stretches video to fill screen dimensions. |
| **Coolwalk DPI Preview** | `100` – `320` (Default: `160`) | Interactive visual layout editor. Simulates Android Auto's Coolwalk multi-card split-screen dashboard, sidebar positioning, and card scaling in real time. |
| **Video Codec** | `Auto`, `H.264`, `HEVC (H.265)` | Choose between H.264 or HEVC hardware decoding. HEVC saves approximately 50% bandwidth on high-resolution streams. |
| **Resolution** | `Auto`, `480p`, `720p`, `1080p`, `1440p`, `4K` | Automatically negotiates or manually forces projection resolution. |
| **FPS Limit** | `60 FPS`, `30 FPS` | Select 60 FPS for maximum fluidity, or 30 FPS to reduce power consumption on older iPad hardware. |
| **Driving Position** | `LHD (Left-Hand Drive)`, `RHD (Right-Hand Drive)` | Toggles the docking side of the Coolwalk dashboard sidebar (left vs. right). |
| **Night Mode** | `Auto (07:00–19:00)`, `System`, `Day`, `Night` | Controls map day/night theme. `Auto` switches based on time; `System` follows iPadOS Dark Mode appearance. |
| **GPS Source** | `Phone GPS`, `iPad GPS` | Cellular iPad models can stream high-accuracy iPad GPS data directly to Android Auto. |
| **Audio Output Target** | `iPad (Speaker / iPad BT)`, `Phone (Original Device)` | Switch between iPad audio output or phone native audio (useful when the phone is paired directly to your car's factory Bluetooth speaker system). |
| **Performance HUD** | `On`, `Off` | Displays a lightweight, translucent diagnostic HUD at the top-left showing FPS, bitrate, frame size, and latency. Fully pass-through to touch. |
| **Configuration Backup** | `Export JSON`, `Import JSON`, `Reset Defaults` | Export your personalized configuration as a JSON string, restore backups, or reset settings to factory defaults. |

---

## Troubleshooting

<details>
<summary><b>1. App displays "iPad IP: No Wi-Fi"</b></summary>

Ensure your iPad is connected to your phone's personal hotspot or to the same Wi-Fi network. On first launch, grant HeadunitPad permission to access the **Local Network** when prompted. If inadvertently denied, navigate to iPad **Settings $\rightarrow$ Privacy & Security $\rightarrow$ Local Network $\rightarrow$ HeadunitPad** and enable it.
</details>

<details>
<summary><b>2. "Connection Refused (Port 5277)"</b></summary>

This indicates the Head Unit Server is not currently running or listening on your phone:
1. Open Android Auto settings on your Android phone.
2. Tap the three-dot menu (⋮) in the top-right corner and verify that **Start head unit server** is active.
3. Ensure the notification shade displays an active Android Auto server notification.
4. Verify that the IP address matches your phone's personal hotspot gateway (typically `192.168.43.1` or `172.20.10.1`).
</details>

<details>
<summary><b>3. Does rotating the iPad interrupt or disconnect projection?</b></summary>

No. HeadunitPad-Auto features seamless zero-disconnect rotation. Rotating your iPad triggers dynamic `UpdateUiConfigRequest (0x8009)` margin recalculation and `overscanLayerFrame` clipping, keeping your video session uninterrupted and free from geometric distortion.
</details>

<details>
<summary><b>4. Audio stutters, drops, or has high latency</b></summary>

Wi-Fi 2.4 GHz environments are prone to vehicular interference:
1. Configure your phone's personal hotspot to use the **5 GHz band** for lower latency and higher bandwidth.
2. Set **Audio Codec** to `AAC-LC` in settings to reduce audio bandwidth consumption.
3. If you prefer vehicle factory speakers, select **Phone** as the **Audio Output Target** so your phone directly streams audio to your car via Bluetooth.
</details>

---

## Disclaimers

This project is an independent open-source receiver intended for personal, educational, and research use:
- Android Auto is a trademark of Google LLC.
- Apple, iPad, iPadOS, and VideoToolbox are trademarks of Apple Inc.
- This project is not affiliated with, sponsored by, or endorsed by Google LLC or Apple Inc.

---

## Acknowledgments

- **[open-headunit](https://github.com/open-headunit/open-headunit)** by André Rinas & contributors: The foundational reference architecture, Protobuf schema definitions, and policies that made this project possible.
- **[Headunit Revived](https://github.com/andreknieriem/headunit-revived)** by Andre Knieriem: The Android Auto Server engine powering wireless projection.
- **Mike Reid** (In Memoriam): Original open-source headunit pioneer whose protocol reverse-engineering paved the way for the ecosystem.
- **[OpenSSL](https://www.openssl.org/)** & [OpenSSL-Universal](https://github.com/krzyzanowskim/OpenSSL): Industry-standard TLS cryptography toolkit.

---

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See the [LICENSE](LICENSE) file for complete details.
