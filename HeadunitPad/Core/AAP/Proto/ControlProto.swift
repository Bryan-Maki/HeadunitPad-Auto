//
//  ControlProto.swift
//  HeadunitPad
//
//  Android Auto control.proto pure Swift models.
//

import Foundation

public enum ControlMsgType: Int32, CaseIterable {
    case messageVersionRequest = 1
    case messageVersionResponse = 2
    case messageEncapsulatedSsl = 3
    case messageAuthComplete = 4
    case messageServiceDiscoveryRequest = 5
    case messageServiceDiscoveryResponse = 6
    case messageChannelOpenRequest = 7
    case messageChannelOpenResponse = 8
    case messageChannelCloseNotification = 9
    case messagePingRequest = 11
    case messagePingResponse = 12
    case messageNavFocusRequest = 13
    case messageNavFocusNotification = 14
    case messageByebyeRequest = 15
    case messageByebyeResponse = 16
    case messageVoiceSessionNotification = 17
    case messageAudioFocusRequest = 18
    case messageAudioFocusNotification = 19
    case messageCarConnectedDevicesRequest = 20
    case messageCarConnectedDevicesResponse = 21
    case messageUserSwitchRequest = 22
    case messageBatteryStatusNotification = 23
    case messageCallAvailabilityStatus = 24
    case messageUserSwitchResponse = 25
    case messageServiceDiscoveryUpdate = 26
    case messageUnexpectedMessage = 255
    case messageFramingError = 65535

    public static let versionRequest = ControlMsgType.messageVersionRequest
    public static let versionResponse = ControlMsgType.messageVersionResponse
    public static let encapsulatedSsl = ControlMsgType.messageEncapsulatedSsl
    public static let authComplete = ControlMsgType.messageAuthComplete
    public static let serviceDiscoveryRequest = ControlMsgType.messageServiceDiscoveryRequest
    public static let serviceDiscoveryResponse = ControlMsgType.messageServiceDiscoveryResponse
    public static let channelOpenRequest = ControlMsgType.messageChannelOpenRequest
    public static let channelOpenResponse = ControlMsgType.messageChannelOpenResponse
    public static let channelCloseNotification = ControlMsgType.messageChannelCloseNotification
    public static let byebyeRequest = ControlMsgType.messageByebyeRequest
    public static let byebyeResponse = ControlMsgType.messageByebyeResponse
    public static let pingRequest = ControlMsgType.messagePingRequest
    public static let pingResponse = ControlMsgType.messagePingResponse
}

public enum BluetoothPairingMethod: Int32, CaseIterable {
    case unavailable = -1
    case oob = 1
    case numericComparison = 2
    case passkeyEntry = 3
    case pin = 4
}

public enum ByeByeReason: Int32, CaseIterable {
    case userSelection = 1
    case deviceSwitch = 2
    case notSupported = 3
    case notCurrentlySupported = 4
    case probeSupported = 5
}

public enum DriverPosition: Int32, CaseIterable {
    case left = 0
    case right = 1
    case center = 2
    case unknown = 3
}

public struct ControlService: ProtoCodable, Equatable {
    public struct SensorSourceService: ProtoCodable, Equatable {
        public struct Sensor: ProtoCodable, Equatable {
            public var type: SensorType
            public init(type: SensorType) { self.type = type }
            public func encode(to writer: inout ProtoWriter) { writer.writeEnum(fieldNumber: 1, value: type.rawValue) }
            public init(from reader: inout ProtoReader) throws {
                var t = SensorType.night
                while let (f, w) = try reader.readTag() {
                    if f == 1 { t = SensorType(rawValue: try reader.readInt32()) ?? .night } else { try reader.skipField(wireType: w) }
                }
                self.type = t
            }
        }
        public var sensors: [Sensor]
        public init(sensors: [Sensor] = []) { self.sensors = sensors }
        public func encode(to writer: inout ProtoWriter) {
            for s in sensors { writer.writeMessage(fieldNumber: 1, message: s) }
        }
        public init(from reader: inout ProtoReader) throws {
            var list: [Sensor] = []
            while let (f, w) = try reader.readTag() {
                if f == 1 { list.append(try reader.readMessage(Sensor.self)) } else { try reader.skipField(wireType: w) }
            }
            self.sensors = list
        }
    }

    public struct MediaSinkService: ProtoCodable, Equatable {
        public struct VideoConfiguration: ProtoCodable, Equatable {
            public enum VideoCodecResolutionType: Int32, CaseIterable {
                case _800x480 = 1
                case _1280x720 = 2
                case _1920x1080 = 3
                case _2560x1440 = 4
                case _3840x2160 = 5
                case _720x1280 = 6
                case _1080x1920 = 7
                case _1440x2560 = 8
                case _2160x3840 = 9
            }
            public enum VideoFrameRateType: Int32, CaseIterable {
                case _60 = 1
                case _30 = 2
            }
            public var codecResolution: VideoCodecResolutionType
            public var frameRate: VideoFrameRateType
            public var marginWidth: UInt32
            public var marginHeight: UInt32
            public var density: UInt32
            public var decoderAdditionalDepth: UInt32?
            public var viewingDistance: UInt32?
            public var pixelAspectRatioE4: UInt32?
            public var realDensity: UInt32?
            public var videoCodecType: MediaCodecType?

            public init(
                codecResolution: VideoCodecResolutionType = ._1280x720,
                frameRate: VideoFrameRateType = ._60,
                marginWidth: UInt32 = 0,
                marginHeight: UInt32 = 0,
                density: UInt32 = 160,
                decoderAdditionalDepth: UInt32? = nil,
                viewingDistance: UInt32? = nil,
                pixelAspectRatioE4: UInt32? = nil,
                realDensity: UInt32? = nil,
                videoCodecType: MediaCodecType? = nil
            ) {
                self.codecResolution = codecResolution
                self.frameRate = frameRate
                self.marginWidth = marginWidth
                self.marginHeight = marginHeight
                self.density = density
                self.decoderAdditionalDepth = decoderAdditionalDepth
                self.viewingDistance = viewingDistance
                self.pixelAspectRatioE4 = pixelAspectRatioE4
                self.realDensity = realDensity
                self.videoCodecType = videoCodecType
            }

            public func encode(to writer: inout ProtoWriter) {
                writer.writeEnum(fieldNumber: 1, value: codecResolution.rawValue)
                writer.writeEnum(fieldNumber: 2, value: frameRate.rawValue)
                writer.writeUInt32(fieldNumber: 3, value: marginWidth)
                writer.writeUInt32(fieldNumber: 4, value: marginHeight)
                writer.writeUInt32(fieldNumber: 5, value: density)
                if let depth = decoderAdditionalDepth { writer.writeUInt32(fieldNumber: 6, value: depth) }
                if let dist = viewingDistance { writer.writeUInt32(fieldNumber: 7, value: dist) }
                if let par = pixelAspectRatioE4 { writer.writeUInt32(fieldNumber: 8, value: par) }
                if let rd = realDensity { writer.writeUInt32(fieldNumber: 9, value: rd) }
                if let vct = videoCodecType { writer.writeEnum(fieldNumber: 10, value: vct.rawValue) }
            }

            public init(from reader: inout ProtoReader) throws {
                var res = VideoCodecResolutionType._1280x720
                var fps = VideoFrameRateType._60
                var mw: UInt32 = 0
                var mh: UInt32 = 0
                var dens: UInt32 = 160
                var depth: UInt32?
                var dist: UInt32?
                var par: UInt32?
                var rd: UInt32?
                var vct: MediaCodecType?
                while let (f, w) = try reader.readTag() {
                    switch f {
                    case 1: res = VideoCodecResolutionType(rawValue: try reader.readInt32()) ?? ._1280x720
                    case 2: fps = VideoFrameRateType(rawValue: try reader.readInt32()) ?? ._60
                    case 3: mw = try reader.readUInt32()
                    case 4: mh = try reader.readUInt32()
                    case 5: dens = try reader.readUInt32()
                    case 6: depth = try reader.readUInt32()
                    case 7: dist = try reader.readUInt32()
                    case 8: par = try reader.readUInt32()
                    case 9: rd = try reader.readUInt32()
                    case 10: vct = MediaCodecType(rawValue: try reader.readInt32())
                    default: try reader.skipField(wireType: w)
                    }
                }
                self.codecResolution = res
                self.frameRate = fps
                self.marginWidth = mw
                self.marginHeight = mh
                self.density = dens
                self.decoderAdditionalDepth = depth
                self.viewingDistance = dist
                self.pixelAspectRatioE4 = par
                self.realDensity = rd
                self.videoCodecType = vct
            }
        }

        public var availableType: MediaCodecType
        public var audioType: AudioStreamType?
        public var audioConfigs: [AudioConfiguration]
        public var videoConfigs: [VideoConfiguration]
        public var availableWhileInCall: Bool?

        public init(
            availableType: MediaCodecType = .mediaCodecVideoH264Bp,
            audioType: AudioStreamType? = nil,
            audioConfigs: [AudioConfiguration] = [],
            videoConfigs: [VideoConfiguration] = [],
            availableWhileInCall: Bool? = nil
        ) {
            self.availableType = availableType
            self.audioType = audioType
            self.audioConfigs = audioConfigs
            self.videoConfigs = videoConfigs
            self.availableWhileInCall = availableWhileInCall
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeEnum(fieldNumber: 1, value: availableType.rawValue)
            if let at = audioType { writer.writeEnum(fieldNumber: 2, value: at.rawValue) }
            for ac in audioConfigs { writer.writeMessage(fieldNumber: 3, message: ac) }
            for vc in videoConfigs { writer.writeMessage(fieldNumber: 4, message: vc) }
            if let inCall = availableWhileInCall { writer.writeBool(fieldNumber: 5, value: inCall) }
        }

        public init(from reader: inout ProtoReader) throws {
            var avType = MediaCodecType.mediaCodecVideoH264Bp
            var at: AudioStreamType?
            var acs: [AudioConfiguration] = []
            var vcs: [VideoConfiguration] = []
            var inCall: Bool?
            while let (f, w) = try reader.readTag() {
                switch f {
                case 1: avType = MediaCodecType(rawValue: try reader.readInt32()) ?? .mediaCodecVideoH264Bp
                case 2: at = AudioStreamType(rawValue: try reader.readInt32())
                case 3: acs.append(try reader.readMessage(AudioConfiguration.self))
                case 4: vcs.append(try reader.readMessage(VideoConfiguration.self))
                case 5: inCall = try reader.readBool()
                default: try reader.skipField(wireType: w)
                }
            }
            self.availableType = avType
            self.audioType = at
            self.audioConfigs = acs
            self.videoConfigs = vcs
            self.availableWhileInCall = inCall
        }
    }

    public struct InputSourceService: ProtoCodable, Equatable {
        public struct TouchConfig: ProtoCodable, Equatable {
            public var width: UInt32
            public var height: UInt32
            public init(width: UInt32 = 0, height: UInt32 = 0) {
                self.width = width
                self.height = height
            }
            public func encode(to writer: inout ProtoWriter) {
                writer.writeUInt32(fieldNumber: 1, value: width)
                writer.writeUInt32(fieldNumber: 2, value: height)
            }
            public init(from reader: inout ProtoReader) throws {
                var w: UInt32 = 0
                var h: UInt32 = 0
                while let (f, wt) = try reader.readTag() {
                    if f == 1 { w = try reader.readUInt32() }
                    else if f == 2 { h = try reader.readUInt32() }
                    else { try reader.skipField(wireType: wt) }
                }
                self.width = w
                self.height = h
            }
        }

        public var keycodesSupported: [UInt32]
        public var touchscreen: TouchConfig?
        public var touchpad: TouchConfig?

        public init(keycodesSupported: [UInt32] = [], touchscreen: TouchConfig? = nil, touchpad: TouchConfig? = nil) {
            self.keycodesSupported = keycodesSupported
            self.touchscreen = touchscreen
            self.touchpad = touchpad
        }

        public func encode(to writer: inout ProtoWriter) {
            for kc in keycodesSupported { writer.writeUInt32(fieldNumber: 1, value: kc) }
            if let ts = touchscreen { writer.writeMessage(fieldNumber: 2, message: ts) }
            if let tp = touchpad { writer.writeMessage(fieldNumber: 3, message: tp) }
        }

        public init(from reader: inout ProtoReader) throws {
            var kcs: [UInt32] = []
            var ts: TouchConfig?
            var tp: TouchConfig?
            while let (f, w) = try reader.readTag() {
                switch f {
                case 1:
                    if w == ProtoWireType.lengthDelimited {
                        kcs.append(contentsOf: try reader.readPackedUInt32())
                    } else {
                        kcs.append(try reader.readUInt32())
                    }
                case 2: ts = try reader.readMessage(TouchConfig.self)
                case 3: tp = try reader.readMessage(TouchConfig.self)
                default: try reader.skipField(wireType: w)
                }
            }
            self.keycodesSupported = kcs
            self.touchscreen = ts
            self.touchpad = tp
        }
    }

    public struct MediaSourceService: ProtoCodable, Equatable {
        public var type: MediaCodecType
        public var audioConfig: AudioConfiguration
        public var availableWhileInCall: Bool?

        public init(type: MediaCodecType = .mediaCodecAudioPcm, audioConfig: AudioConfiguration = AudioConfiguration(), availableWhileInCall: Bool? = nil) {
            self.type = type
            self.audioConfig = audioConfig
            self.availableWhileInCall = availableWhileInCall
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeEnum(fieldNumber: 1, value: type.rawValue)
            writer.writeMessage(fieldNumber: 2, message: audioConfig)
            if let inCall = availableWhileInCall { writer.writeBool(fieldNumber: 3, value: inCall) }
        }

        public init(from reader: inout ProtoReader) throws {
            var t = MediaCodecType.mediaCodecAudioPcm
            var ac = AudioConfiguration()
            var inCall: Bool?
            while let (f, w) = try reader.readTag() {
                switch f {
                case 1: t = MediaCodecType(rawValue: try reader.readInt32()) ?? .mediaCodecAudioPcm
                case 2: ac = try reader.readMessage(AudioConfiguration.self)
                case 3: inCall = try reader.readBool()
                default: try reader.skipField(wireType: w)
                }
            }
            self.type = t
            self.audioConfig = ac
            self.availableWhileInCall = inCall
        }
    }

    public struct BluetoothService: ProtoCodable, Equatable {
        public var carAddress: String
        public var supportedPairingMethods: [BluetoothPairingMethod]

        public init(carAddress: String = "", supportedPairingMethods: [BluetoothPairingMethod] = []) {
            self.carAddress = carAddress
            self.supportedPairingMethods = supportedPairingMethods
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeString(fieldNumber: 1, value: carAddress)
            for pm in supportedPairingMethods { writer.writeEnum(fieldNumber: 2, value: pm.rawValue) }
        }

        public init(from reader: inout ProtoReader) throws {
            var addr = ""
            var methods: [BluetoothPairingMethod] = []
            while let (f, w) = try reader.readTag() {
                switch f {
                case 1: addr = try reader.readString()
                case 2:
                    if let m = BluetoothPairingMethod(rawValue: try reader.readInt32()) {
                        methods.append(m)
                    }
                default: try reader.skipField(wireType: w)
                }
            }
            self.carAddress = addr
            self.supportedPairingMethods = methods
        }
    }

    public struct NavigationStatusService: ProtoCodable, Equatable {
        public enum ClusterType: Int32, CaseIterable {
            case customImageSupported = 1
            case imageCodesOnly = 2
        }

        public var minimumIntervalMs: UInt32
        public var type: ClusterType

        public init(minimumIntervalMs: UInt32 = 1000, type: ClusterType = .imageCodesOnly) {
            self.minimumIntervalMs = minimumIntervalMs
            self.type = type
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeUInt32(fieldNumber: 1, value: minimumIntervalMs)
            writer.writeEnum(fieldNumber: 2, value: type.rawValue)
        }

        public init(from reader: inout ProtoReader) throws {
            var interval: UInt32 = 1000
            var t = ClusterType.imageCodesOnly
            while let (f, w) = try reader.readTag() {
                switch f {
                case 1: interval = try reader.readUInt32()
                case 2: t = ClusterType(rawValue: try reader.readInt32()) ?? .imageCodesOnly
                default: try reader.skipField(wireType: w)
                }
            }
            self.minimumIntervalMs = interval
            self.type = t
        }
    }

    public struct MediaPlaybackStatusService: ProtoCodable, Equatable {
        public init() {}
        public func encode(to writer: inout ProtoWriter) {}
        public init(from reader: inout ProtoReader) throws {
            while let (_, w) = try reader.readTag() { try reader.skipField(wireType: w) }
        }
    }

    public var id: UInt32
    public var sensorSourceService: SensorSourceService?
    public var mediaSinkService: MediaSinkService?
    public var inputSourceService: InputSourceService?
    public var mediaSourceService: MediaSourceService?
    public var bluetoothService: BluetoothService?
    public var navigationStatusService: NavigationStatusService?
    public var mediaPlaybackService: MediaPlaybackStatusService?

    public init(
        id: UInt32 = 0,
        sensorSourceService: SensorSourceService? = nil,
        mediaSinkService: MediaSinkService? = nil,
        inputSourceService: InputSourceService? = nil,
        mediaSourceService: MediaSourceService? = nil,
        bluetoothService: BluetoothService? = nil,
        navigationStatusService: NavigationStatusService? = nil,
        mediaPlaybackService: MediaPlaybackStatusService? = nil
    ) {
        self.id = id
        self.sensorSourceService = sensorSourceService
        self.mediaSinkService = mediaSinkService
        self.inputSourceService = inputSourceService
        self.mediaSourceService = mediaSourceService
        self.bluetoothService = bluetoothService
        self.navigationStatusService = navigationStatusService
        self.mediaPlaybackService = mediaPlaybackService
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt32(fieldNumber: 1, value: id)
        if let sensor = sensorSourceService { writer.writeMessage(fieldNumber: 2, message: sensor) }
        if let mediaSink = mediaSinkService { writer.writeMessage(fieldNumber: 3, message: mediaSink) }
        if let inputSource = inputSourceService { writer.writeMessage(fieldNumber: 4, message: inputSource) }
        if let mediaSource = mediaSourceService { writer.writeMessage(fieldNumber: 5, message: mediaSource) }
        if let bluetooth = bluetoothService { writer.writeMessage(fieldNumber: 6, message: bluetooth) }
        if let nav = navigationStatusService { writer.writeMessage(fieldNumber: 8, message: nav) }
        if let playback = mediaPlaybackService { writer.writeMessage(fieldNumber: 9, message: playback) }
    }

    public init(from reader: inout ProtoReader) throws {
        var id: UInt32 = 0
        var sensor: SensorSourceService?
        var mediaSink: MediaSinkService?
        var inputSource: InputSourceService?
        var mediaSource: MediaSourceService?
        var bluetooth: BluetoothService?
        var nav: NavigationStatusService?
        var playback: MediaPlaybackStatusService?
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: id = try reader.readUInt32()
            case 2: sensor = try reader.readMessage(SensorSourceService.self)
            case 3: mediaSink = try reader.readMessage(MediaSinkService.self)
            case 4: inputSource = try reader.readMessage(InputSourceService.self)
            case 5: mediaSource = try reader.readMessage(MediaSourceService.self)
            case 6: bluetooth = try reader.readMessage(BluetoothService.self)
            case 8: nav = try reader.readMessage(NavigationStatusService.self)
            case 9: playback = try reader.readMessage(MediaPlaybackStatusService.self)
            default: try reader.skipField(wireType: w)
            }
        }
        self.id = id
        self.sensorSourceService = sensor
        self.mediaSinkService = mediaSink
        self.inputSourceService = inputSource
        self.mediaSourceService = mediaSource
        self.bluetoothService = bluetooth
        self.navigationStatusService = nav
        self.mediaPlaybackService = playback
    }
}

public struct ServiceDiscoveryRequestProto: ProtoCodable, Equatable {
    public var phoneName: String
    public var phoneBrand: String

    public init(phoneName: String = "", phoneBrand: String = "") {
        self.phoneName = phoneName
        self.phoneBrand = phoneBrand
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeString(fieldNumber: 4, value: phoneName)
        writer.writeString(fieldNumber: 5, value: phoneBrand)
    }

    public init(from reader: inout ProtoReader) throws {
        var name = ""
        var brand = ""
        while let (f, w) = try reader.readTag() {
            switch f {
            case 4: name = try reader.readString()
            case 5: brand = try reader.readString()
            default: try reader.skipField(wireType: w)
            }
        }
        self.phoneName = name
        self.phoneBrand = brand
    }
}

public struct PingConfiguration: ProtoCodable, Equatable {
    public var timeoutMs: UInt32?
    public var intervalMs: UInt32?
    public var highLatencyThresholdMs: UInt32?
    public var trackedPingCount: UInt32?

    public init(timeoutMs: UInt32? = nil, intervalMs: UInt32? = nil, highLatencyThresholdMs: UInt32? = nil, trackedPingCount: UInt32? = nil) {
        self.timeoutMs = timeoutMs
        self.intervalMs = intervalMs
        self.highLatencyThresholdMs = highLatencyThresholdMs
        self.trackedPingCount = trackedPingCount
    }

    public func encode(to writer: inout ProtoWriter) {
        if let to = timeoutMs { writer.writeUInt32(fieldNumber: 1, value: to) }
        if let intv = intervalMs { writer.writeUInt32(fieldNumber: 2, value: intv) }
        if let hl = highLatencyThresholdMs { writer.writeUInt32(fieldNumber: 3, value: hl) }
        if let count = trackedPingCount { writer.writeUInt32(fieldNumber: 4, value: count) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.timeoutMs = try reader.readUInt32()
            case 2: self.intervalMs = try reader.readUInt32()
            case 3: self.highLatencyThresholdMs = try reader.readUInt32()
            case 4: self.trackedPingCount = try reader.readUInt32()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WirelessTcpConfiguration: ProtoCodable, Equatable {
    public var socketReceiveBufferSizeKb: UInt32?
    public var socketSendBufferSizeKb: UInt32?
    public var socketReadTimeoutMs: UInt32?
    public var socketReceiveBufferSize: UInt32?
    public var socketSendBufferSize: UInt32?

    public init(
        socketReceiveBufferSizeKb: UInt32? = nil,
        socketSendBufferSizeKb: UInt32? = nil,
        socketReadTimeoutMs: UInt32? = nil,
        socketReceiveBufferSize: UInt32? = nil,
        socketSendBufferSize: UInt32? = nil
    ) {
        self.socketReceiveBufferSizeKb = socketReceiveBufferSizeKb
        self.socketSendBufferSizeKb = socketSendBufferSizeKb
        self.socketReadTimeoutMs = socketReadTimeoutMs
        self.socketReceiveBufferSize = socketReceiveBufferSize
        self.socketSendBufferSize = socketSendBufferSize
    }

    public func encode(to writer: inout ProtoWriter) {
        if let r = socketReceiveBufferSizeKb { writer.writeUInt32(fieldNumber: 1, value: r) }
        if let s = socketSendBufferSizeKb { writer.writeUInt32(fieldNumber: 2, value: s) }
        if let t = socketReadTimeoutMs { writer.writeUInt32(fieldNumber: 3, value: t) }
        if let rb = socketReceiveBufferSize { writer.writeUInt32(fieldNumber: 4, value: rb) }
        if let sb = socketSendBufferSize { writer.writeUInt32(fieldNumber: 5, value: sb) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.socketReceiveBufferSizeKb = try reader.readUInt32()
            case 2: self.socketSendBufferSizeKb = try reader.readUInt32()
            case 3: self.socketReadTimeoutMs = try reader.readUInt32()
            case 4: self.socketReceiveBufferSize = try reader.readUInt32()
            case 5: self.socketSendBufferSize = try reader.readUInt32()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct ConnectionConfiguration: ProtoCodable, Equatable {
    public var pingConfiguration: PingConfiguration?
    public var wirelessTcpConfiguration: WirelessTcpConfiguration?

    public init(pingConfiguration: PingConfiguration? = nil, wirelessTcpConfiguration: WirelessTcpConfiguration? = nil) {
        self.pingConfiguration = pingConfiguration
        self.wirelessTcpConfiguration = wirelessTcpConfiguration
    }

    public func encode(to writer: inout ProtoWriter) {
        if let ping = pingConfiguration { writer.writeMessage(fieldNumber: 1, message: ping) }
        if let tcp = wirelessTcpConfiguration { writer.writeMessage(fieldNumber: 2, message: tcp) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.pingConfiguration = try reader.readMessage(PingConfiguration.self)
            case 2: self.wirelessTcpConfiguration = try reader.readMessage(WirelessTcpConfiguration.self)
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct VersionResponseOptions: ProtoCodable, Equatable {
    public var connectionConfiguration: ConnectionConfiguration?

    public init(connectionConfiguration: ConnectionConfiguration? = nil) {
        self.connectionConfiguration = connectionConfiguration
    }

    public func encode(to writer: inout ProtoWriter) {
        if let cfg = connectionConfiguration { writer.writeMessage(fieldNumber: 1, message: cfg) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.connectionConfiguration = try reader.readMessage(ConnectionConfiguration.self)
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct ServiceDiscoveryResponseProto: ProtoCodable, Equatable {
    public var services: [ControlService]
    public var make: String
    public var model: String
    public var year: String
    public var vehicleId: String
    public var driverPosition: DriverPosition
    public var headUnitMake: String
    public var headUnitModel: String
    public var headUnitSoftwareBuild: String
    public var headUnitSoftwareVersion: String
    public var canPlayNativeMediaDuringVr: Bool
    public var hideProjectedClock: Bool?
    public var sessionConfiguration: Int32?
    public var displayName: String?
    public var probeForSupport: Bool?
    public var connectionConfiguration: ConnectionConfiguration?
    public var headunitInfo: HeadUnitInfo?

    public init(
        services: [ControlService] = [],
        make: String = "",
        model: String = "",
        year: String = "",
        vehicleId: String = "",
        driverPosition: DriverPosition = .left,
        headUnitMake: String = "",
        headUnitModel: String = "",
        headUnitSoftwareBuild: String = "1",
        headUnitSoftwareVersion: String = "0.1.0",
        canPlayNativeMediaDuringVr: Bool = false,
        hideProjectedClock: Bool? = nil,
        sessionConfiguration: Int32? = nil,
        displayName: String? = nil,
        probeForSupport: Bool? = nil,
        connectionConfiguration: ConnectionConfiguration? = nil,
        headunitInfo: HeadUnitInfo? = nil
    ) {
        self.services = services
        self.make = make
        self.model = model
        self.year = year
        self.vehicleId = vehicleId
        self.driverPosition = driverPosition
        self.headUnitMake = headUnitMake
        self.headUnitModel = headUnitModel
        self.headUnitSoftwareBuild = headUnitSoftwareBuild
        self.headUnitSoftwareVersion = headUnitSoftwareVersion
        self.canPlayNativeMediaDuringVr = canPlayNativeMediaDuringVr
        self.hideProjectedClock = hideProjectedClock
        self.sessionConfiguration = sessionConfiguration
        self.displayName = displayName
        self.probeForSupport = probeForSupport
        self.connectionConfiguration = connectionConfiguration
        self.headunitInfo = headunitInfo
    }

    public func encode(to writer: inout ProtoWriter) {
        for s in services { writer.writeMessage(fieldNumber: 1, message: s) }
        writer.writeString(fieldNumber: 2, value: make)
        writer.writeString(fieldNumber: 3, value: model)
        writer.writeString(fieldNumber: 4, value: year)
        writer.writeString(fieldNumber: 5, value: vehicleId)
        writer.writeEnum(fieldNumber: 6, value: driverPosition.rawValue)
        writer.writeString(fieldNumber: 7, value: headUnitMake)
        writer.writeString(fieldNumber: 8, value: headUnitModel)
        writer.writeString(fieldNumber: 9, value: headUnitSoftwareBuild)
        writer.writeString(fieldNumber: 10, value: headUnitSoftwareVersion)
        writer.writeBool(fieldNumber: 11, value: canPlayNativeMediaDuringVr)
        if let hide = hideProjectedClock { writer.writeBool(fieldNumber: 12, value: hide) }
        if let session = sessionConfiguration { writer.writeInt32(fieldNumber: 13, value: session) }
        if let dn = displayName { writer.writeString(fieldNumber: 14, value: dn) }
        if let probe = probeForSupport { writer.writeBool(fieldNumber: 15, value: probe) }
        if let conn = connectionConfiguration { writer.writeMessage(fieldNumber: 16, message: conn) }
        if let hu = headunitInfo { writer.writeMessage(fieldNumber: 17, message: hu) }
    }

    public init(from reader: inout ProtoReader) throws {
        var services: [ControlService] = []
        var make = ""
        var model = ""
        var year = ""
        var vehicleId = ""
        var driverPosition: DriverPosition = .left
        var headUnitMake = ""
        var headUnitModel = ""
        var headUnitSoftwareBuild = ""
        var headUnitSoftwareVersion = ""
        var canPlay = false
        var hideClock: Bool?
        var sessionConfig: Int32?
        var dn: String?
        var probe: Bool?
        var conn: ConnectionConfiguration?
        var hu: HeadUnitInfo?

        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: services.append(try reader.readMessage(ControlService.self))
            case 2: make = try reader.readString()
            case 3: model = try reader.readString()
            case 4: year = try reader.readString()
            case 5: vehicleId = try reader.readString()
            case 6: driverPosition = DriverPosition(rawValue: try reader.readInt32()) ?? .left
            case 7: headUnitMake = try reader.readString()
            case 8: headUnitModel = try reader.readString()
            case 9: headUnitSoftwareBuild = try reader.readString()
            case 10: headUnitSoftwareVersion = try reader.readString()
            case 11: canPlay = try reader.readBool()
            case 12: hideClock = try reader.readBool()
            case 13: sessionConfig = try reader.readInt32()
            case 14: dn = try reader.readString()
            case 15: probe = try reader.readBool()
            case 16: conn = try reader.readMessage(ConnectionConfiguration.self)
            case 17: hu = try reader.readMessage(HeadUnitInfo.self)
            default: try reader.skipField(wireType: w)
            }
        }
        self.services = services
        self.make = make
        self.model = model
        self.year = year
        self.vehicleId = vehicleId
        self.driverPosition = driverPosition
        self.headUnitMake = headUnitMake
        self.headUnitModel = headUnitModel
        self.headUnitSoftwareBuild = headUnitSoftwareBuild
        self.headUnitSoftwareVersion = headUnitSoftwareVersion
        self.canPlayNativeMediaDuringVr = canPlay
        self.hideProjectedClock = hideClock
        self.sessionConfiguration = sessionConfig
        self.displayName = dn
        self.probeForSupport = probe
        self.connectionConfiguration = conn
        self.headunitInfo = hu
    }
}

public struct ChannelOpenRequest: ProtoCodable, Equatable {
    public var priority: Int32
    public var serviceId: Int32

    public init(priority: Int32 = 0, serviceId: Int32 = 0) {
        self.priority = priority
        self.serviceId = serviceId
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeSInt32(fieldNumber: 1, value: priority)
        writer.writeInt32(fieldNumber: 2, value: serviceId)
    }

    public init(from reader: inout ProtoReader) throws {
        var pri: Int32 = 0
        var sid: Int32 = 0
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: pri = try reader.readSInt32()
            case 2: sid = try reader.readInt32()
            default: try reader.skipField(wireType: w)
            }
        }
        self.priority = pri
        self.serviceId = sid
    }
}

public struct ChannelOpenResponse: ProtoCodable, Equatable {
    public var status: MessageStatus

    public init(status: MessageStatus = .statusSuccess) {
        self.status = status
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: status.rawValue)
    }

    public init(from reader: inout ProtoReader) throws {
        var status: MessageStatus = .statusSuccess
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: status = MessageStatus(rawValue: try reader.readInt32()) ?? .statusSuccess
            default: try reader.skipField(wireType: w)
            }
        }
        self.status = status
    }
}

public struct PingRequest: ProtoCodable, Equatable {
    public var timestamp: Int64
    public var bugReport: Int32?

    public init(timestamp: Int64 = 0, bugReport: Int32? = nil) {
        self.timestamp = timestamp
        self.bugReport = bugReport
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeInt64(fieldNumber: 1, value: timestamp)
        if let br = bugReport { writer.writeInt32(fieldNumber: 2, value: br) }
    }

    public init(from reader: inout ProtoReader) throws {
        var ts: Int64 = 0
        var br: Int32?
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: ts = try reader.readInt64()
            case 2: br = try reader.readInt32()
            default: try reader.skipField(wireType: w)
            }
        }
        self.timestamp = ts
        self.bugReport = br
    }
}

public struct PingResponse: ProtoCodable, Equatable {
    public var timestamp: Int64

    public init(timestamp: Int64 = 0) {
        self.timestamp = timestamp
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeInt64(fieldNumber: 1, value: timestamp)
    }

    public init(from reader: inout ProtoReader) throws {
        var ts: Int64 = 0
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: ts = try reader.readInt64()
            default: try reader.skipField(wireType: w)
            }
        }
        self.timestamp = ts
    }
}

public struct ByeByeRequest: ProtoCodable, Equatable {
    public var reason: ByeByeReason

    public init(reason: ByeByeReason = .userSelection) {
        self.reason = reason
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: reason.rawValue)
    }

    public init(from reader: inout ProtoReader) throws {
        var r: ByeByeReason = .userSelection
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: r = ByeByeReason(rawValue: try reader.readInt32()) ?? .userSelection
            default: try reader.skipField(wireType: w)
            }
        }
        self.reason = r
    }
}

public struct ByeByeResponse: ProtoCodable, Equatable {
    public init() {}
    public func encode(to writer: inout ProtoWriter) {}
    public init(from reader: inout ProtoReader) throws {
        while let (_, w) = try reader.readTag() { try reader.skipField(wireType: w) }
    }
}
