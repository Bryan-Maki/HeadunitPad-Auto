# HeadunitPad

**Transform your iPad into an Android Auto display screen.**

> This project enables iPads (especially iPad mini 6) to act as a Headunit display/host for Android Auto, over a USB cable or wirelessly.

> **Wired USB requires a TrollStore install.** It needs USB Host entitlements that an ordinary re-signed sideload cannot keep. Wireless works on any install.

## Features

### Core Functionality
- **Wired USB Connection** *(TrollStore only)* - Talks to the phone directly over the cable using Android Open Accessory, with no Android Auto Server, no WiFi, and no helper app
- **Wireless Connection** - Connects to Android Auto Server via WiFi (TCP port 5277)
- **Video Streaming** - Receives and renders H.264 video frames from Android Auto
- **Audio Playback** - PCM audio output via AVAudioEngine
- **Touch Input** - Sends touch events back to Android Auto
- **Microphone Support** - Captures and streams microphone input
- **GPS Location** - Shares iPad or phone GPS location with Android Auto

### Settings
- **Orientation** - Landscape or Portrait mode (Portrait has known issues)
- **Resolution** - Configurable video resolution
- **FPS** - 30 or 60 fps options
- **DPI** - Custom DPI adjustment
- **GPS Source** - Use iPad GPS or phone GPS

## How It Works

### Connection Flow

Two transports, one protocol. Both feed the same AAP session, so video, audio,
touch, microphone, and GPS behave identically once connected.

**Wired (USB)** — the iPad is the USB host:

```
┌─────────────┐   USB-C cable   ┌─────────────────┐
│    iPad     │ ◄─────────────► │  Android Phone  │
│   (host)    │                 │   (accessory)   │
└──────┬──────┘                 └────────┬────────┘
       │  1. AOA negotiation (GET_PROTOCOL, identity, START)
       │  2. Phone re-enumerates as 0x18D1:0x2D01
       │  3. Claim the accessory interface, bulk IN/OUT
       │  4. Same AAP handshake as below, over the bulk pipe
       ▼                                 ▼
```

**Wireless (WiFi)**:

```
┌─────────────┐         WiFi          ┌─────────────────┐
│   iPad      │ ◄──────────────────► │ Android Phone   │
│  (Client)   │                     │  (Server)       │
│             │   Port 5277/TCP      │                 │
└──────┬──────┘                     └────────┬────────┘
       │                                       │
       │  1. TCP Connection                    │
       │  2. Version Request/Response          │
       │  3. TLS Handshake (wrapped in AAP)    │
       │  4. Status OK                         │
       │  5. BINDING_RESPONSE                  │
       │  6. Running (encrypted AAP messages)  │
       ▼                                       ▼
┌─────────────────────────────────────────────────────┐
│                   iPad Display                       │
│  • Renders H.264 video frames                        │
│  • Sends touch events to phone                      │
│  • Plays audio from phone                           │
│  • Provides microphone and GPS data                  │
└─────────────────────────────────────────────────────┘
```

### Protocol Details

The Android Auto Protocol (AAP) uses:
- **Channel 0** - Control messages (handshake, binding)
- **Channel 1** - Sensor data
- **Channel 2** - Video stream (H.264)
- **Channel 3** - Input (touch, key events)
- **Channel 4/5** - Audio streams
- **Channel 6** - Primary audio
- **Channel 7** - Microphone

TLS is encapsulated inside AAP messages (Channel 0, Type 3), not at the socket layer.

## Known Issues
Well, You told me

## Requirements

- **iPad** (iPad mini 6 recommended for best performance)
- **iOS/iPadOS 16.6+**
- **Android phone** with Android Auto

For **wired USB**:

- **TrollStore**, to install the IPA with its USB Host entitlements intact
- A **USB-C data cable** (charge-only cables do not enumerate)
- A **USB-C iPad**; the iPad acts as USB host, so the phone appears as an accessory

For **wireless**:

- **Android Auto Server** from the phone's developer options, or Headunit Revived's Wireless Helper
- **WiFi network** (both devices on the same network)

## Installation

### TrollStore (required for wired USB)

1. Download `HeadunitPad.ipa` from the [latest release](https://github.com/andyching168/HeadunitPad/releases/latest)
2. Open it with TrollStore and install

The wired path needs three entitlements that only a TrollStore install keeps:
`com.apple.vm.device-access`, the `AppleUSBHostDeviceUserClient` /
`AppleUSBHostInterfaceUserClient` IOKit user-client exceptions, and
`com.apple.system.diagnostics.iokit-properties`. The app reads its own code
signature at launch, so on an install without them the wired button says so
instead of failing with a misleading "no USB device found".

To build the IPA yourself:

```bash
scripts/build_trollstore_ipa.sh
```

It builds unsigned, applies the entitlements with `ldid`, and refuses to produce
an IPA whose packaged executable lost any of them.

### Sideloading (wireless only)

1. Clone this repository
2. Open `iPadOS/HeadunitPad/HeadunitPad.xcworkspace` in Xcode
3. Configure your development team in Signing & Capabilities
4. Build and run on your iPad

Re-signing strips the USB Host entitlements, so the wired button will tell you
it needs TrollStore. Everything wireless works normally.

### Dependencies

- [OpenSSL-Universal](https://github.com/krzyzanowskim/OpenSSL) via CocoaPods
- [Socket.io](https://github.com/mikezellers/SocketIO-Android-Swift) (not currently used, for future WiFi Direct)
- [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) (not currently used)

## Architecture

```
iPadOS/HeadunitPad/HeadunitPad/
├── Core/
│   ├── AAP/
│   │   ├── AapTransport.swift      # Main transport layer with TLS
│   │   ├── AapMessage.swift        # Message framing
│   │   └── Protocol/Channel.swift   # Channel definitions
│   ├── Network/
│   │   ├── TcpHandler.swift        # TCP connection management
│   │   ├── OpenSslTlsHandler.swift # OpenSSL TLS implementation
│   │   ├── Discovery.swift          # Network device discovery
│   │   └── ConnectionManager.swift  # Connection lifecycle
│   ├── Audio/
│   │   ├── PCMAudioPlayer.swift     # PCM audio playback
│   │   └── MicrophoneCapture.swift  # Microphone input
│   ├── Video/
│   │   └── H264VideoRendererView.swift # Video rendering
│   └── Location/
│       └── LocationCapture.swift     # GPS location
└── Resources/Raw/
    ├── cert                          # Client certificate
    └── privkey                       # Private key
```

## Disclaimer

This project is for educational and personal use only. Android Auto is a trademark of Google LLC. This project is not affiliated with or endorsed by Google.

## Acknowledgments

### Special Thanks

- **Andre Knieriem** - Developer of [Headunit Revived](https://github.com/andreknieriem/headunit-revived), the Android Auto Server application that makes this project possible

### Inspiration

- **Mike Reid** - Original [Headunit](https://github.com/mikereidis/headunit) developer. His pioneering work on the Android Auto protocol laid the foundation for all subsequent projects in this space. Mike passed away; his contributions to the open-source community will be remembered.

### Open Source Libraries

- [OpenSSL](https://www.openssl.org/) - Cryptography toolkit
- [VideoToolbox](https://developer.apple.com/documentation/videotoolbox) - Apple's hardware-accelerated video decoding

## License

AGPL-v3 - See LICENSE file for details.

---

**If you find this project useful, consider supporting the developers of Headunit Revived who make this ecosystem possible.**
