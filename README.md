# HeadunitPad-Auto

[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)
[![Build Unsigned IPA](https://img.shields.io/github/actions/workflow/status/bryan-maki/headunitpad-auto/build-ipa.yml?branch=main&style=flat-square&label=Build%20IPA)](.github/workflows/build-ipa.yml)
[![Platform](https://img.shields.io/badge/platform-iPadOS-blue.svg?style=flat-square)]()
[![Release](https://img.shields.io/badge/version-v0.4.1--beta-orange.svg?style=flat-square)]()

A native, pure-wireless Android Auto head unit receiver for iPadOS with full-screen adaptation.

**HeadunitPad-Auto** transforms your iPad into a high-performance, wireless Android Auto head unit without requiring jailbreak, TrollStore, or wired USB hardware privileges. Built natively in Swift, it features a complete AAP (Android Auto Protocol) and WPP (Wireless Projection Protocol) stack, hardware-accelerated low-latency video decoding, multi-channel audio mixing with adaptive jitter buffering, and end-to-end watchdog recovery mechanisms.

## Table of Contents

- [Security](#security)
- [Background](#background)
- [Features](#features)
- [Install](#install)
  - [Option 1: Sideload Prebuilt IPA (Recommended)](#option-1-sideload-prebuilt-ipa-recommended)
  - [Option 2: Build from Source](#option-2-build-from-source)
- [Usage](#usage)
  - [Wireless Connection](#wireless-connection)
  - [Display & Geometry Configuration](#display--geometry-configuration)
  - [Interaction Modes & Diagnostics](#interaction-modes--diagnostics)
- [Architecture](#architecture)
- [Testing](#testing)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Security

**HeadunitPad-Auto** performs local TLS handshakes required by the Android Auto protocol using embedded credentials (`HeadunitPad/Resources/Raw/cert` and `privkey`) managed by `OpenSslTlsHandler`. All projection streams, touch inputs, microphone audio, and location updates are transmitted strictly over your local Wi-Fi network or personal hotspot between your iPad and Android phone—no external servers or cloud relays are involved.

## Background

Running Android Auto on an iPad traditionally suffers from wired USB accessory limitations, 16:9 letterboxed black bars, audio routing glitches, and stream freezes over unstable wireless links. **HeadunitPad-Auto** was engineered from the ground up across six development phases to provide a pure-wireless experience over Wi-Fi hotspot or LAN subnet discovery (`WPP-over-TCP`), native iPad aspect ratio and DPI geometry negotiation, and resilient audio/video pipelines tailored for in-vehicle environments.

## Features

- **Pure-Wireless Connectivity & Auto-Reconnect**: Full Wireless Projection Protocol support (`WppTcpServer`, `WppHandshakeSession`), helper server discovery (`WirelessHelperServer`), and seamless link-loss auto-reconnect with playback state restoration (`AutomaticReconnect`, `AutoResumePlaybackPolicy`).
- **Modern Dual-Column Dashboard & Native Settings Center**: Refactored `MainViewController` featuring an automotive card-based dashboard with breathing status pill, direct connection IP hub with one-tap reset, step-by-step Android setup guide, 6 interactive quick-spec tiles, screen keep-awake prevention during projection, and a dedicated `.insetGrouped` modal `SettingsViewController`.
- **Full-Screen iPad Geometry & Live DPI Preview**: Eliminates black bars via dynamic resolution negotiation (`NegotiatedResolutionPolicy`), canvas/margin policies (`ProjectionCanvasPolicy`, `MarginStrategyPolicy`), orientation handling (`ScreenOrientationPolicy`), and an embedded real-time interactive DPI previewer (`DpiPreviewView`).
- **Hardware-Accelerated Video & Self-Healing Pipeline**: Low-latency rendering (`H264VideoRendererView`, `VideoFrameBus`) backed by an adaptive decoder configuration ladder (`DecoderConfigLadder`), SPS/PPS tracking (`ParameterSetTracker`), keyframe scanning/repair (`VideoKeyframeScanner`, `KeyframeRepairTracker`), and stall/corruption recovery policies.
- **Lockscreen Now Playing & Flexible Microphone Routing**: Restores iOS lockscreen and Control Center Now Playing album artwork and track info via `NowPlayingCoordinator` (zero `.mixWithOthers` interference, keep-alive audio sink), flexible microphone source routing (`Follow Audio`, `iPad Mic`, `Phone / Car BT Mic`), and unified constant Car (CAR 1) identity preventing dual-vehicle split in Android Auto.
- **Multi-Channel Audio Engine & Voice Assistant Uplink**: Supports AAC and PCM decoding (`AacAudioDecoder`, `PCMAudioPlayer`), adaptive jitter buffering (`AdaptiveJitterPolicy`, `AdaptivePcmBuffer`), multi-stream audio mixing with smooth ducking and soft clipping (`AudioMixer`, `MixerDuckingEnvelope`, `MixerSoftClipper`), and flow-controlled microphone capture with PCM decimation (`MicSessionController`, `MicPcmDecimator`).
- **Multiple Interaction Modes & Vehicle Integration**: Switch between the main dashboard (`MainViewController`), immersive full-screen projection (`VideoOnlyViewController`), and gesture trackpad mode (`TrackpadViewController`, `TrackpadInputBridge`), complete with CoreLocation GPS forwarding (`LocationCapture`).
- **Built-In Diagnostics & Configuration Backup**: Real-time performance HUD (`PerformanceOverlayView`), standalone audio pipeline tester (`AudioStreamTester`), connection issue guidance banners (`ConnectionIssueBannerPolicy`), settings backup/restore (`SettingsBackupManager`), and one-tap log export (`LogExporter`).

## Install

### Option 1: Sideload Prebuilt IPA (Recommended)

1. Download the latest unsigned `HeadunitPad.ipa` from the [Releases](../../releases) page (current release: `v0.4.1-beta`).
2. Sign and install the `.ipa` onto your iPad using your preferred sideloading tool (**SideStore**, **AltStore**, **Sideloadly**, or an Apple Developer certificate).
3. On first launch, grant **Local Network**, **Microphone**, and **Location** permissions when prompted.

### Option 2: Build from Source

**Prerequisites:**
- macOS with Xcode 15.0 or later
- CocoaPods

```bash
# 1. Clone the repository
git clone https://github.com/Bryan-Maki/HeadunitPad-Auto.git
cd headunitpad-auto

# 2. Install CocoaPods dependencies
pod install

# 3. Open the workspace in Xcode
open HeadunitPad.xcworkspace

# Or build an unsigned IPA directly via the helper script:
bash scripts/build_unsigned_ipa.sh

```

## Usage

### Wireless Connection

1. **Network Setup**: Connect your iPad to your Android phone's personal Wi-Fi hotspot, or connect both devices to the same local Wi-Fi subnet (`DiscoverySubnetPolicy` automatically detects gateway and subnet addresses).
2. **Start Projection**:
* **Automatic / WPP Discovery**: Enable Wireless Android Auto on your phone. `ConnectionManager` and `WppTcpServer` on the iPad will automatically negotiate protocol versions, complete the TLS handshake, and open media/input channels.



### Display & Geometry Configuration

* Open the Settings panel to customize target resolution, screen density (DPI), video fit mode (`VideoFitPolicy`), and margin strategy (`MarginStrategyPolicy`).
* Use the **Live DPI Preview (`DpiPreviewView`)** to inspect UI scaling and layout proportions in real time before starting a projection session.
* Export or restore your custom head unit profile anytime via `SettingsBackupManager`.

### Interaction Modes & Diagnostics

* **View Modes**: Use `MainViewController` for connection management and diagnostics, `VideoOnlyViewController` for distraction-free driving, or `TrackpadViewController` for relative cursor/trackpad input.
* **Performance & Troubleshooting**: Toggle `PerformanceOverlayView` to monitor live FPS, decode latency, network throughput, and audio buffer levels. Use `AudioStreamTester` to verify audio output routing, or tap **Export Logs** (`LogExporter`) to generate a diagnostic bundle for bug reports.

## Architecture

```text
HeadunitPad/
├── Core/
│   ├── AAP/          # Frame reassembly, custom ProtoWire codec, channel multiplexing & 18 link watchdogs
│   ├── Audio/        # AAC/PCM decoders, adaptive jitter buffers, multi-track mixer, NowPlaying & mic uplink
│   ├── Diagnostics/  # AppLog, audio stream tester, connection issue banners & log exporter
│   ├── Location/     # CoreLocation GPS capture & AAP sensor channel reporting
│   ├── Network/      # ConnectionArbiter, subnet/gateway discovery, WPP server, TCP & OpenSSL TLS handlers
│   ├── Settings/     # Resolution, DPI, margin, canvas geometry policies & settings backup manager
│   ├── UI/           # Touch coordinate mapping, trackpad bridge, live DPI preview & HUD overlay
│   └── Video/        # H.264 NAL parser, decoder config ladder, 20 video recovery policies & renderer view
├── Resources/Raw/    # Embedded TLS certificate and private key for AAP handshakes
├── MainViewController.swift
├── VideoOnlyViewController.swift
└── TrackpadViewController.swift

```

## Testing

The repository includes a comprehensive unit and smoke test suite in `HeadunitPadTests/` covering all six engineering phases:

* `ByteStreamConnectionTests` & `H264NALParserTests`: Core byte stream and NAL unit parsing verification
* `Phase1ScreenAndFramingTests`: Screen geometry adaptation and AAP fragmented frame reassembly
* `Phase2WirelessAndWatchdogTests`: Wireless discovery, WPP handshakes, and link watchdog policies
* `Phase3VideoAndRecoveryTests`: Decoder configuration ladder, keyframe repair, and stall recovery
* `Phase4AudioAndMicTests`: Adaptive audio jitter buffering, mixer ducking, and microphone decimation
* `Phase5SystemIntegrationTests`: Location forwarding, playback focus leases, and system integration
* `Phase6DiagnosticsAndPolishTests` & `ViewControllersSmokeTests`: Diagnostics, backup management, and UI smoke tests

Run all tests in Xcode by pressing `Cmd + U`.

## Maintainers

* [@bryan-maki](https://github.com/Bryan-Maki)

## Contributing

Issues and Pull Requests are welcome! When submitting a bug report, please attach a diagnostic log exported via `LogExporter`. Before opening a Pull Request, please ensure:

1. New protocol or recovery logic follows the modular `*Policy` architecture.
2. All unit test suites under `HeadunitPadTests` pass without regressions.

## Acknowledgments

- [open-headunit](https://github.com/andreknieriem/open-headunit) - The Android Auto Server engine powering wireless projection.
- [HeadunitPad](https://github.com/andyching168/HeadunitPad) - The original project.

## License

See [LICENSE.txt](LICENSE.txt) for license details.
