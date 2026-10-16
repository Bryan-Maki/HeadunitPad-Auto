//
//  WppTcpServer.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppTcpServer.kt
//  TCP listener on port 5299 for modern Android Auto WiFi Projection Protocol (WPP) handshakes.
//

import Foundation
import Network

public protocol WppTcpServerDelegate: AnyObject {
    func wppTcpServer(_ server: WppTcpServer, didCompleteHandshakeFor clientIp: String)
    func wppTcpServer(_ server: WppTcpServer, didFailWith error: Error)
}

public final class WppTcpServer {
    public static let defaultPort: UInt16 = 5299

    public weak var delegate: WppTcpServerDelegate?
    public var onRawAapConnectionDetected: ((NWConnection, Data) -> Void)?

    private let queue = DispatchQueue(label: "com.headunitpad.wpp.tcp", qos: .userInitiated)
    private var listener: NWListener?
    public private(set) var isListening: Bool = false
    public var isRunning: Bool { isListening }
    public private(set) var listeningPort: Int? = nil

    public var carInfo: WppCarInfo
    public var projectionPort: Int = 5288
    public var ssid: String = "HeadunitPad-AP"
    public var passkey: String = "12345678"
    public var bssid: String? = nil

    private var activeSessions: [ObjectIdentifier: ClientSession] = [:]

    private final class ClientSession {
        let connection: NWConnection
        let session: WppHandshakeSession
        var buffer = Data()
        var timeoutWorkItem: DispatchWorkItem?
        var isTlsActive: Bool = false
        var tlsHandler: OpenSslTlsHandler?
        var probeWorkItem: DispatchWorkItem?
        var isReceiving: Bool = false

        init(connection: NWConnection, session: WppHandshakeSession) {
            self.connection = connection
            self.session = session
        }
    }

    public init(carInfo: WppCarInfo = WppMessages.carInfo()) {
        self.carInfo = carInfo
    }

    public func start(port: UInt16 = WppTcpServer.defaultPort) {
        if isListening && listeningPort == Int(port) && listener != nil {
            return
        }
        if let existing = listener {
            existing.cancel()
            listener = nil
        }
        isListening = false
        listeningPort = nil

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.noDelay = true

            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw WppFramingError.invalidType(Int(port))
            }
            let nwListener = try NWListener(using: parameters, on: nwPort)

            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isListening = true
                    self.listeningPort = Int(port)
                    print("WppTcpServer: listening on port \(port)")
                case .failed(let err):
                    self.isListening = false
                    self.listeningPort = nil
                    print("WppTcpServer: failed on port \(port): \(err)")
                    DispatchQueue.main.async {
                        self.delegate?.wppTcpServer(self, didFailWith: err)
                    }
                case .cancelled:
                    self.isListening = false
                    self.listeningPort = nil
                    print("WppTcpServer: stopped")
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            self.listener = nwListener
            nwListener.start(queue: queue)
        } catch {
            isListening = false
            listeningPort = nil
            DispatchQueue.main.async {
                self.delegate?.wppTcpServer(self, didFailWith: error)
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
        listeningPort = nil

        for (_, client) in activeSessions {
            client.probeWorkItem?.cancel()
            client.timeoutWorkItem?.cancel()
            client.connection.cancel()
        }
        activeSessions.removeAll()
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        let handshakeSession = WppHandshakeSession(credentialsKnown: true)
        let client = ClientSession(connection: connection, session: handshakeSession)
        activeSessions[key] = client

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            switch state {
            case .ready:
                print("WppTcpServer: Client connected: \(conn.endpoint)")
                let probe = DispatchWorkItem { [weak self, weak client] in
                    guard let self = self, let client = client else { return }
                    if !client.isTlsActive && client.buffer.isEmpty {
                        print("WppTcpServer: 150ms probe timer expired without plaintext WPP, initiating TLS client-mode wrapping")
                        self.startTlsHandshake(for: client)
                    }
                }
                client.probeWorkItem = probe
                self.queue.asyncAfter(deadline: .now() + 0.15, execute: probe)
                self.readNextChunk(client)

            case .failed, .cancelled:
                print("WppTcpServer: Client disconnected: \(conn.endpoint)")
                client.probeWorkItem?.cancel()
                self.processActions(handshakeSession.on(event: .peerClosed), for: client)
                self.activeSessions.removeValue(forKey: ObjectIdentifier(conn))

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func readNextChunk(_ client: ClientSession) {
        if client.isReceiving { return }
        client.isReceiving = true
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak client] content, _, isComplete, error in
            guard let self = self, let client = client else { return }
            client.isReceiving = false

            if let data = content, !data.isEmpty {
                if !client.isTlsActive {
                    if client.buffer.isEmpty && data[0] == 0x16 {
                        client.probeWorkItem?.cancel()
                        print("WppTcpServer: Detected TLS handshake header 0x16, starting TLS handshake")
                        self.startTlsHandshake(for: client, initialTlsData: data)
                        return
                    }

                    if self.isRawAapPacket(data) {
                        client.probeWorkItem?.cancel()
                        let initialData = data
                        let conn = client.connection
                        self.activeSessions.removeValue(forKey: ObjectIdentifier(conn))
                        conn.stateUpdateHandler = nil
                        print("WppTcpServer: Detected raw AAP connection on port \(self.listeningPort ?? 5299), delegating to ConnectionManager")
                        DispatchQueue.main.async { [weak self] in
                            self?.onRawAapConnectionDetected?(conn, initialData)
                        }
                        return
                    }

                    client.probeWorkItem?.cancel()
                    client.buffer.append(data)
                    if client.session.stage == .new {
                        self.processActions(client.session.on(event: .socketReady), for: client)
                    }
                    self.drainFrames(client)
                } else {
                    guard let tls = client.tlsHandler else { return }
                    if !tls.isHandshakeComplete {
                        self.continueTlsHandshake(for: client, with: data)
                        return
                    } else {
                        if let decrypted = tls.decrypt(data: data), !decrypted.isEmpty {
                            client.buffer.append(decrypted)
                            self.drainFrames(client)
                        }
                    }
                }
            }

            if isComplete || error != nil {
                client.probeWorkItem?.cancel()
                self.processActions(client.session.on(event: .peerClosed), for: client)
                self.activeSessions.removeValue(forKey: ObjectIdentifier(client.connection))
                return
            }

            self.readNextChunk(client)
        }
    }

    private func isRawAapPacket(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        if data[0] == 0x00 {
            if data.count >= 6 && data[4] == 0x00 && data[5] == 0x01 {
                return true
            }
            let wppType = (Int(data[2]) << 8) | Int(data[3])
            let isWppType = (wppType >= 1 && wppType <= 11)
            if !isWppType && (data[1] == 0x01 || data[1] == 0x03 || data[1] == 0x05) {
                return true
            }
        }
        return false
    }

    private func drainFrames(_ client: ClientSession) {
        while client.buffer.count >= WppFraming.headerSize {
            guard let payloadLen = try? WppFraming.decodePayloadSize(header: client.buffer.prefix(WppFraming.headerSize)),
                  let msgType = try? WppFraming.decodeType(header: client.buffer.prefix(WppFraming.headerSize)) else {
                client.buffer.removeAll()
                break
            }

            let fullFrameLen = WppFraming.headerSize + payloadLen
            guard client.buffer.count >= fullFrameLen else {
                break // Wait for remainder
            }

            let payload = client.buffer.subdata(in: WppFraming.headerSize..<fullFrameLen)
            client.buffer.removeSubrange(0..<fullFrameLen)

            // Parse status if present in payload
            var status: Int? = nil
            var reader = ProtoReader(data: payload)
            if msgType == WppMessageType.versionResponse {
                if let resp = try? WifiVersionResponse(from: &reader) {
                    status = resp.status.map { Int($0) }
                }
            } else if msgType == WppMessageType.connectStatus {
                if let resp = try? WifiConnectStatus(from: &reader) {
                    status = resp.status.map { Int($0) }
                }
            } else if msgType == WppMessageType.startResponse {
                if let resp = try? WifiStartResponse(from: &reader) {
                    status = resp.status.map { Int($0) }
                }
            }

            let event = WppEvent.messageReceived(type: msgType, status: status, rawPayload: payload)
            processActions(client.session.on(event: event), for: client)
        }
    }

    private func processActions(_ actions: [WppAction], for client: ClientSession) {
        for action in actions {
            switch action {
            case .sendVersionRequest:
                let stationIp = NetworkAddresses.stationIpv4() ?? "0.0.0.0"
                let endpoint = WppEndpoint(ip: stationIp, port: Int(Self.defaultPort))
                let req = WppMessages.versionRequest(
                    carInfo: carInfo,
                    endpoint: endpoint,
                    channelType: .channelsDualBand,
                    channels: [2412, 2437, 2462, 5180, 5240]
                )
                if let framed = try? WppMessages.frame(req, type: WppMessageType.versionRequest) {
                    sendData(framed, to: client)
                }

            case .sendStartRequest:
                let stationIp = NetworkAddresses.stationIpv4() ?? "0.0.0.0"
                let req = WppMessages.startRequest(ip: stationIp, port: projectionPort)
                if let framed = try? WppMessages.frame(req, type: WppMessageType.startRequest) {
                    sendData(framed, to: client)
                }

            case .sendInfoResponse:
                let effectiveSsid = ProjectionSettings.wifiSsid.isEmpty ? ssid : ProjectionSettings.wifiSsid
                let effectivePasskey = ProjectionSettings.wifiPasskey.isEmpty ? passkey : ProjectionSettings.wifiPasskey
                let effectiveBssid = ProjectionSettings.wifiBssid.isEmpty ? bssid : ProjectionSettings.wifiBssid
                let resp = WppMessages.infoResponse(
                    ssid: effectiveSsid,
                    key: effectivePasskey,
                    bssid: effectiveBssid,
                    identity: .stable
                )
                if let framed = try? WppMessages.frame(resp, type: WppMessageType.infoResponse) {
                    sendData(framed, to: client)
                }

            case .sendPingResponse(let payload):
                if let framed = try? WppFraming.encodeFrame(payload: payload, type: WppMessageType.pingResponse) {
                    sendData(framed, to: client)
                }

            case .extendSettle:
                client.timeoutWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self, weak client] in
                    guard let self = self, let client = client else { return }
                    self.processActions(client.session.on(event: .settleTimeout), for: client)
                }
                client.timeoutWorkItem = work
                queue.asyncAfter(deadline: .now() + Double(WppHandshakeSession.settleWindowMs) / 1000.0, execute: work)

            case .completeSuccess:
                client.timeoutWorkItem?.cancel()
                let clientIp = extractClientIp(from: client.connection.endpoint)
                print("WppTcpServer: Handshake complete for \(clientIp)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.wppTcpServer(self, didCompleteHandshakeFor: clientIp)
                }

            case .fail(let reason, _, _):
                print("WppTcpServer: Handshake failed: \(reason)")
                client.timeoutWorkItem?.cancel()
                client.connection.cancel()
            }
        }

        if client.session.stage == .awaitVersion || client.session.stage == .awaitInfoRequest {
            client.timeoutWorkItem?.cancel()
            let timeoutMs = client.session.currentStageTimeoutMs ?? 3_000
            let work = DispatchWorkItem { [weak self, weak client] in
                guard let self = self, let client = client else { return }
                let timeoutActions = client.session.on(event: .stageTimeout)
                self.processActions(timeoutActions, for: client)
            }
            client.timeoutWorkItem = work
            queue.asyncAfter(deadline: .now() + Double(timeoutMs) / 1000.0, execute: work)
        }
    }

    public func notifyTcpSessionUp() {
        queue.async { [weak self] in
            guard let self = self else { return }
            for (_, client) in self.activeSessions {
                self.processActions(client.session.on(event: .tcpSessionUp), for: client)
            }
        }
    }

    private func startTlsHandshake(for client: ClientSession, initialTlsData: Data? = nil) {
        client.isTlsActive = true
        let tls = OpenSslTlsHandler()
        guard tls.setup() else {
            print("WppTcpServer: Failed to setup TLS handler")
            return
        }
        _ = tls.loadDefaultBundleCertificate()
        client.tlsHandler = tls

        do {
            let step = try tls.startHandshakeSession()
            if !step.outgoingData.isEmpty {
                sendRawData(step.outgoingData, to: client)
            }
            if let initial = initialTlsData, !initial.isEmpty {
                continueTlsHandshake(for: client, with: initial)
            } else {
                readNextChunk(client)
            }
        } catch {
            print("WppTcpServer: startTlsHandshake failed: \(error)")
        }
    }

    private func continueTlsHandshake(for client: ClientSession, with data: Data) {
        guard let tls = client.tlsHandler else { return }
        do {
            let step = try tls.continueHandshake(with: data)
            if !step.outgoingData.isEmpty {
                sendRawData(step.outgoingData, to: client)
            }
            if step.isComplete {
                print("WppTcpServer: TLS handshake complete, triggering WPP socketReady")
                tls.postHandshakeReset()
                self.processActions(client.session.on(event: .socketReady), for: client)
            }
            readNextChunk(client)
        } catch {
            print("WppTcpServer: continueTlsHandshake error: \(error)")
        }
    }

    private func sendData(_ data: Data, to client: ClientSession) {
        if client.isTlsActive, let tls = client.tlsHandler, tls.isHandshakeComplete {
            if let encrypted = tls.encrypt(data: data) {
                sendRawData(encrypted, to: client)
            }
        } else {
            sendRawData(data, to: client)
        }
    }

    private func sendRawData(_ data: Data, to client: ClientSession) {
        client.connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("WppTcpServer: send error: \(error)")
            }
        })
    }

    private func extractClientIp(from endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr): return "\(addr)"
            case .ipv6(let addr): return "\(addr)"
            case .name(let name, _): return name
            @unknown default: return "unknown"
            }
        default:
            return "unknown"
        }
    }
}
