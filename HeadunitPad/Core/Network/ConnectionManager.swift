//
//  ConnectionManager.swift
//  HeadunitPad
//
//  Manages device discovery and connection lifecycle for wireless Android Auto
//  Integrated with WPP Handshake, ConnectionArbiter, TeardownGuard, Watchdogs & AutoReconnect
//

import Foundation
import AVFoundation
import Network
import UIKit

enum ConnectionState: Equatable {
    case disconnected
    case discovering
    case waitingForWirelessHelper
    case connecting
    case handshaking
    case running
    case disconnecting
    case error(String)

    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Scanning..."
        case .waitingForWirelessHelper:
            return "Waiting for Wireless Helper / WPP..."
        case .connecting:
            return "Connecting..."
        case .handshaking:
            return "Handshaking..."
        case .running:
            return "Connected"
        case .disconnecting:
            return "Disconnecting..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

protocol ConnectionManagerDelegate: AnyObject {
    func connectionManager(_ manager: ConnectionManager, didChangeState state: ConnectionState)
    func connectionManager(_ manager: ConnectionManager, didUpdateStatus status: String)
    func connectionManager(_ manager: ConnectionManager, didDiscoverDevice device: DiscoveredDevice)
    func connectionManager(_ manager: ConnectionManager, didReceiveVideoData data: Data)
    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8)
    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool)
    func connectionManager(_ manager: ConnectionManager, didReceiveAudioCodecConfig data: Data, on channel: UInt8)
}

extension ConnectionManagerDelegate {
    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool) {
        connectionManager(manager, didReceiveAudioData: data, on: channel)
    }
    func connectionManager(_ manager: ConnectionManager, didReceiveAudioCodecConfig data: Data, on channel: UInt8) {}
}

class ConnectionManager {
    weak var delegate: ConnectionManagerDelegate?

    private let discovery = Discovery()
    private let tcpHandler = TcpHandler()
    private let wirelessHelperServer = WirelessHelperServer()
    private let wppServer = WppTcpServer()
    private let arbiter = ConnectionArbiter()
    // TeardownGuard is used via its static methods (e.g. TeardownGuard.runThenClose(...))
    private let playbackSnapshot = ReconnectPlaybackSnapshot()
    private let microphoneCapture = MicrophoneCapture()
    private let locationCapture = LocationCapture()

    private var aapTransport: AapTransport?
    private var activeConnection: ByteStreamConnection?
    private var isUserInitiatedDisconnect = false
    private var hasTriggeredWirelessHelper = false
    private var hasReceivedAaMediaMetadata = false
    private var lastPlayingState: Bool = false
    private var consecutiveStarvedSessions: Int = 0
    private var consecutiveSilentFailures: Int = 0
    private var lastTriedEndpoint: String?

    private lazy var autoReconnect = AutomaticReconnect(
        currentState: { [weak self] in self?.activeConnection },
        isStopping: { [weak self] in self?.isUserInitiatedDisconnect ?? false }
    )

    private(set) var state: ConnectionState = .disconnected {
        didSet {
            print("ConnectionManager: state changed from \(oldValue.description) to \(state.description)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.connectionManager(self, didChangeState: self.state)
            }
        }
    }

    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var connectedDevice: DiscoveredDevice?
    private(set) var statusDetail = "Ready to connect"

    init() {
        discovery.delegate = self
        wirelessHelperServer.delegate = self
        wppServer.delegate = self
        installAapTransport(connection: tcpHandler)
        microphoneCapture.onPCMData = { [weak self] data in
            self?.aapTransport?.sendMicrophoneAudioData(data)
        }
        locationCapture.onLocation = { [weak self] location in
            self?.aapTransport?.sendLocationUpdate(location)
        }
        NowPlayingCoordinator.shared.onRemoteCommand = { [weak self] command in
            self?.sendRemoteMediaCommand(command)
        }
    }

    func requestLocationPermissionIfNeeded() {
        guard ProjectionSettings.gpsSource == .ipad else { return }
        guard ProjectionSettings.supportsCellularIpad() else { return }
        locationCapture.requestPermissionIfNeeded()
    }

    func startDiscovery() {
        print("ConnectionManager: startDiscovery called")
        autoReconnect.cancel()
        isUserInitiatedDisconnect = false
        let canStart: Bool
        switch state {
        case .disconnected, .error, .waitingForWirelessHelper:
            canStart = true
        default:
            canStart = false
        }

        guard canStart else {
            print("ConnectionManager: Cannot start discovery, current state: \(state.description)")
            return
        }

        discoveredDevices.removeAll()
        hasTriggeredWirelessHelper = false
        state = .discovering

        let stationIp = NetworkAddresses.stationIpv4() ?? "No Wi-Fi"
        updateStatus("iPad IP: \(stationIp) | 正在扫描手机热点...")

        // Awake iOS 14+ local network permission
        Discovery.triggerLocalNetworkPermission()

        wppServer.start()
        discovery.startScan(ports: [Discovery.headunitPort])
    }

    func stopDiscovery() {
        print("ConnectionManager: stopDiscovery called")
        autoReconnect.cancel()
        discovery.stopScan()
        wppServer.stop()
        if state == .discovering || state == .waitingForWirelessHelper {
            state = .disconnected
            updateStatus("Ready to connect")
        }
    }

    func connect(to device: DiscoveredDevice) {
        print("ConnectionManager: connect(to:) called with device: \(device.displayName)")
        autoReconnect.cancel()
        isUserInitiatedDisconnect = false

        let inFlight = (state == .connecting || state == .handshaking || state == .running)
        guard ConnectionAdmission.admits(inFlight: inFlight, userInitiated: true) else {
            print("ConnectionManager: Admission refused connection to \(device.displayName)")
            return
        }
        guard arbiter.claim(tier: .user, owner: .manual, what: device.displayName) != nil else {
            print("ConnectionManager: Arbiter refused connection claim for \(device.displayName)")
            return
        }

        lastTriedEndpoint = "\(device.ip):\(device.port)"
        let preparedConnection = discovery.takePreparedConnection(ip: device.ip, port: device.port)
        stopDiscovery()
        state = .connecting
        connectedDevice = device
        updateStatus("Connecting to \(device.displayName)...")
        installAapTransport(connection: tcpHandler)
        aapTransport?.configurePeer(host: device.ip, port: device.port)

        if let preparedConnection = preparedConnection {
            print("ConnectionManager: Using prepared connection from discovery for \(device.ip):\(device.port)")
            tcpHandler.adoptConnection(preparedConnection, host: device.ip, port: device.port)
        } else {
            print("ConnectionManager: Calling tcpHandler.connect(host: \(device.ip), port: \(device.port))")
            tcpHandler.connect(host: device.ip, port: device.port)
        }
    }

    func connect(to ip: String, port: UInt16 = 5277) {
        print("ConnectionManager: connect(to:port:) called with ip: \(ip), port: \(port)")
        let device = DiscoveredDevice(ip: ip, port: port, name: nil)
        connect(to: device)
    }

    func disconnect() {
        print("ConnectionManager: disconnect called")
        isUserInitiatedDisconnect = true
        autoReconnect.cancel()

        TeardownGuard.runThenClose(
            teardown: { [weak self] in
                guard let self = self else { return }
                NowPlayingCoordinator.shared.deactivate()
                self.microphoneCapture.stop()
                self.locationCapture.stop()
                self.wirelessHelperServer.stop()
                self.wppServer.stop()
                self.connectedDevice = nil
                self.state = .disconnected
                self.updateStatus("Ready to connect")
            },
            close: { [weak self] in
                self?.activeConnection?.disconnect()
            },
            onError: { phase, error in
                print("ConnectionManager: disconnect error during \(phase): \(error.localizedDescription)")
            }
        )
    }

    func send(_ data: Data) {
        guard state == .running else { return }
        aapTransport?.send(message: AapMessage(channel: 0, flags: 0, type: 0, payload: data))
    }

    func sendTouchEvent(x: Int, y: Int, action: TouchAction) {
        guard state == .running else { return }
        aapTransport?.sendTouchEvent(x: x, y: y, action: action)
    }

    func sendTouchEvent(pointers: [(id: Int, x: Int, y: Int)], action: TouchAction, actionIndex: Int) {
        guard state == .running else { return }
        aapTransport?.sendTouchEvent(pointers: pointers, action: action, actionIndex: actionIndex)
    }

    func requestVideoRecovery() {
        guard state == .running else { return }
        aapTransport?.requestVideoRecovery()
    }

    func requestVideoRecoveryForNewDisplay() {
        guard state == .running else { return }
        aapTransport?.requestVideoRecoveryForNewDisplay()
    }

    func sendRemoteMediaCommand(_ command: RemoteMediaCommand) {
        guard state == .running else { return }
        let keyCode: Int
        switch command {
        case .play:
            keyCode = 126
        case .pause:
            keyCode = 127
        case .playPause:
            keyCode = 85
        case .next:
            keyCode = 87
        case .previous:
            keyCode = 88
        case .stop:
            keyCode = 86
        }
        aapTransport?.sendMediaKeyEvent(keyCode: keyCode)
    }

    func sendUpdateUiConfigRequest(left: Int, top: Int, right: Int, bottom: Int) {
        aapTransport?.sendUpdateUiConfigRequest(left: left, top: top, right: right, bottom: bottom)
    }

    func diagnosticLines() -> [String] {
        let device = connectedDevice
        let liveVideoLines = aapTransport?.videoDiagnosticLines() ?? []
        let connectionLines = [
            "State: \(state.description)",
            "Status: \(statusDetail)",
            "Mode: \(ProjectionSettings.connectionMode.title)",
            "Auto reconnect: \(ProjectionSettings.autoReconnect ? "On" : "Off")",
            "Auto resume playback: \(ProjectionSettings.autoResumePlayback ? "On" : "Off")",
            "Local IP: \(NetworkAddresses.currentWifiIPv4Address() ?? "Unknown")",
            "Wireless helper: \(wirelessHelperServer.isRunning ? "Listening" : "Stopped") (5288)",
            "WPP server: \(wppServer.isRunning ? "Listening" : "Stopped") (5299)",
            "Consecutive silent failures: \(consecutiveSilentFailures)",
            "Consecutive starved sessions: \(consecutiveStarvedSessions)",
            "Audio output: \(currentAudioOutputDescription())",
            "Now Playing owner: \(state == .running ? "HeadunitPad" : "Inactive")",
            "Discovered headunits: \(discoveredDevices.count)",
            "Helper triggered: \(hasTriggeredWirelessHelper ? "Yes" : "No")",
            "Connected device: \(device?.displayName ?? "None")",
            "Connected endpoint: \(device.map { "\($0.ip):\($0.port)" } ?? "None")",
            "",
        ]
        return connectionLines + liveVideoLines
    }

    private func installAapTransport(connection: ByteStreamConnection) {
        activeConnection = connection
        let transport = AapTransport(
            connection: connection,
            handshakeProfile: .network
        )
        transport.delegate = self
        aapTransport = transport
    }

    private func updateStatus(_ status: String) {
        statusDetail = status
        print("ConnectionManager: status = \(status)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.connectionManager(self, didUpdateStatus: status)
        }
    }

    private func scheduleReconnectIfNeeded(reason: String) {
        guard ProjectionSettings.autoReconnect else { return }
        guard !isUserInitiatedDisconnect else { return }

        let delayMs = UnresponsivePeerPolicy.rescanDelayMs(consecutiveSilentFailures: consecutiveSilentFailures)
        if UnresponsivePeerPolicy.shouldExplain(consecutiveSilentFailures: consecutiveSilentFailures) {
            print("ConnectionManager: UnresponsivePeerPolicy backing off to \(delayMs)ms after \(consecutiveSilentFailures) silent attempts")
        }

        updateStatus("\(reason). Reconnecting in \(delayMs / 1000)s...")
        if let session = activeConnection as AnyObject? {
            autoReconnect.schedule(endedSession: session, delayMs: delayMs) { [weak self] in
                guard let self = self else { return }
                switch self.state {
                case .disconnected, .error:
                    self.startDiscovery()
                default:
                    break
                }
            }
        }
    }

    private func currentAudioOutputDescription() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard !outputs.isEmpty else {
            return "None"
        }
        return outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
    }
}

extension ConnectionManager: DiscoveryDelegate {
    func discoveryDidFindDevice(_ device: DiscoveredDevice) {
        print("ConnectionManager: discovered device: \(device.displayName)")
        discoveredDevices.append(device)
        updateStatus("Found Headunit Server at \(device.ip):\(device.port)")
        delegate?.connectionManager(self, didDiscoverDevice: device)

        // Auto-connect immediately to the discovered headunit server!
        if state == .discovering {
            print("ConnectionManager: Auto-connecting immediately to \(device.displayName)...")
            connect(to: device)
        }
    }

    func discoveryDidFinish() {
        print("ConnectionManager: discovery finished, found \(discoveredDevices.count) devices")
        if state == .discovering {
            if !discoveredDevices.isEmpty {
                return
            }
            state = .disconnected
            updateStatus("未发现车机服务器，请确认手机已开启热点并在 Android Auto 中启动 Headunit Server (5277)")
            scheduleReconnectIfNeeded(reason: "Scan finished")
        }
    }

    func discoveryDidFail(_ error: Error) {
        print("ConnectionManager: discovery failed with error: \(error.localizedDescription)")
        state = .error(error.localizedDescription)
        updateStatus(error.localizedDescription)
        scheduleReconnectIfNeeded(reason: "Discovery failed")
    }
}

extension ConnectionManager: AapTransportDelegate {
    func aapTransport(_ transport: AapTransport, didRequestMicrophoneCapture isOpen: Bool) {
        if isOpen {
            microphoneCapture.start(sampleRate: 16_000, channels: 1)
        } else {
            microphoneCapture.stop()
        }
    }

    func aapTransport(_ transport: AapTransport, didRequestLocationUpdates isEnabled: Bool) {
        if isEnabled {
            locationCapture.start()
        } else {
            locationCapture.stop()
        }
    }

    func aapTransport(_ transport: AapTransport, didReceiveVideoData data: Data) {
        delegate?.connectionManager(self, didReceiveVideoData: data)
    }

    func aapTransport(_ transport: AapTransport, didReceiveAudioData data: Data, on channel: UInt8) {
        delegate?.connectionManager(self, didReceiveAudioData: data, on: channel)
    }

    func aapTransport(_ transport: AapTransport, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool) {
        delegate?.connectionManager(self, didReceiveAudioData: data, on: channel, isAac: isAac)
    }

    func aapTransport(_ transport: AapTransport, didReceiveAudioCodecConfig data: Data, on channel: UInt8) {
        delegate?.connectionManager(self, didReceiveAudioCodecConfig: data, on: channel)
    }

    func aapTransport(_ transport: AapTransport, didReceiveMediaMetadata metadata: AapMediaMetadata) {
        hasReceivedAaMediaMetadata = true
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = metadata.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artwork = metadata.albumArt.flatMap { UIImage(data: $0) }

        NowPlayingCoordinator.shared.updateMetadata(
            NowPlayingMetadata(
                title: title?.isEmpty == false ? title! : "Android Auto",
                artist: artist?.isEmpty == false ? artist! : "Unknown Artist",
                album: album?.isEmpty == false ? album! : "Projection",
                durationSeconds: metadata.durationSeconds,
                artworkImage: artwork
            )
        )
    }

    func aapTransport(_ transport: AapTransport, didReceivePlaybackStatus status: AapPlaybackStatus) {
        let isPlaying = status.state == .playing
        lastPlayingState = isPlaying

        if !hasReceivedAaMediaMetadata,
           let source = status.mediaSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty {
            NowPlayingCoordinator.shared.updateMetadata(
                NowPlayingMetadata(
                    title: source,
                    artist: "Android Auto",
                    album: "Projection",
                    durationSeconds: nil,
                    artworkImage: nil
                )
            )
        }
        NowPlayingCoordinator.shared.updatePlaybackState(
            NowPlayingPlaybackState(
                isPlaying: isPlaying,
                elapsedSeconds: status.playbackSeconds ?? 0
            )
        )
    }

    func aapTransport(_ transport: AapTransport, didChangeState state: AapTransportState) {
        guard transport === aapTransport else { return }
        switch state {
        case .running:
            NowPlayingCoordinator.shared.activate()
            self.state = .running
            updateStatus("Android Auto is running over wireless")
            consecutiveSilentFailures = 0
            consecutiveStarvedSessions = VideoStarvationPolicy.nextStreak(
                current: consecutiveStarvedSessions,
                reachedHandshake: true,
                renderedAnyFrame: true
            )

            // Auto resume playback evaluation
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let resume = playbackSnapshot.consume(now: nowMs)
            if AutoResumePlaybackPolicy.shouldResume(
                enabled: ProjectionSettings.autoResumePlayback,
                wasPlayingBeforeDisconnect: resume.wasPlaying,
                elapsedSinceDisconnectMs: resume.elapsedMs
            ) {
                print("ConnectionManager: AutoResumePlaybackPolicy satisfied, resuming playback")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.sendRemoteMediaCommand(.play)
                }
            }

        case .error(let msg):
            NowPlayingCoordinator.shared.deactivate()
            microphoneCapture.stop()
            locationCapture.stop()
            self.state = .error(msg)
            updateStatus(msg)

            consecutiveSilentFailures = UnresponsivePeerPolicy.countAfterSilentFailure(
                previousCount: consecutiveSilentFailures,
                previousEndpoint: lastTriedEndpoint,
                endpoint: lastTriedEndpoint
            )

            scheduleReconnectIfNeeded(reason: "Android Auto error")

        default:
            break
        }
    }

    func aapTransportDidDisconnect(_ transport: AapTransport) {
        guard transport === aapTransport else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        playbackSnapshot.onDisconnected(
            lastPlaying: lastPlayingState,
            now: nowMs,
            deliberate: isUserInitiatedDisconnect
        )

        aapTransport = nil
        NowPlayingCoordinator.shared.deactivate()
        microphoneCapture.stop()
        locationCapture.stop()
        connectedDevice = nil
        state = .disconnected
        updateStatus("Android Auto disconnected")

        consecutiveStarvedSessions = VideoStarvationPolicy.nextStreak(
            current: consecutiveStarvedSessions,
            reachedHandshake: transport.didReachRunning,
            renderedAnyFrame: false
        )
        if VideoStarvationPolicy.shouldAdvise(consecutiveStarvedSessions: consecutiveStarvedSessions) {
            print("ConnectionManager: VideoStarvationPolicy advises lowering resolution/fps")
        }

        scheduleReconnectIfNeeded(reason: "Android Auto disconnected")
    }
}

extension ConnectionManager: WirelessHelperServerDelegate {
    func wirelessHelperServer(_ server: WirelessHelperServer, didAccept connection: NWConnection, remoteHost: String?) {
        let canAccept: Bool
        switch state {
        case .discovering, .waitingForWirelessHelper, .disconnected, .error:
            canAccept = true
        case .connecting, .handshaking, .running, .disconnecting:
            canAccept = false
        }

        guard canAccept else {
            print("ConnectionManager: dropping inbound wireless helper connection while state=\(state.description)")
            connection.cancel()
            return
        }

        discovery.stopScan()
        state = .connecting

        let host = remoteHost ?? "Wireless Helper"
        connectedDevice = DiscoveredDevice(ip: host, port: WirelessHelperServer.port, name: "Wireless Helper")
        updateStatus("Wireless Helper connected. Starting Android Auto...")
        installAapTransport(connection: tcpHandler)
        aapTransport?.configurePeer(host: host, port: WirelessHelperServer.port)
        tcpHandler.acceptConnection(connection, host: host, port: WirelessHelperServer.port)
    }

    func wirelessHelperServer(_ server: WirelessHelperServer, didFail error: Error) {
        print("ConnectionManager: wireless helper server failed with error: \(error.localizedDescription)")
        if state == .discovering {
            state = .error(error.localizedDescription)
            updateStatus(error.localizedDescription)
            scheduleReconnectIfNeeded(reason: "Wireless Helper listener failed")
        }
    }
}

extension ConnectionManager: WppTcpServerDelegate {
    func wppTcpServer(_ server: WppTcpServer, didCompleteHandshakeFor clientIp: String) {
        print("ConnectionManager: WPP Handshake completed successfully with \(clientIp)")
        updateStatus("WPP Handshake completed with \(clientIp). Starting Android Auto...")
        connect(to: clientIp)
    }

    func wppTcpServer(_ server: WppTcpServer, didFailWith error: Error) {
        print("ConnectionManager: WPP server session error: \(error.localizedDescription)")
    }
}
