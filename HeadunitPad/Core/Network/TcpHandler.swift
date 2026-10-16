//
//  TcpHandler.swift
//  HeadunitPad
//
//  Plain TCP connection handler (no TLS at socket level)
//  Note: Android Auto uses TLS inside the AAP protocol, not at socket level
//

import Foundation
import Network

enum TcpHandlerError: Error {
    case connectionFailed(String)
    case connectionClosed
    case invalidState
    case writeFailed
    case readFailed
    case timeout
}

class TcpHandler: ByteStreamConnection, @unchecked Sendable {
    weak var delegate: ByteStreamConnectionDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.headunitpad.tcp", qos: .userInitiated)
    private let receiveQueue = DispatchQueue(label: "com.headunitpad.tcp.receive", qos: .userInitiated)
    private var connectionTimer: DispatchWorkItem?
    private let connectionTimeout: TimeInterval = 15.0

    private(set) var isConnected = false

    private var pendingData = Data()
    private let pendingDataLock = NSLock()
    private let dataAvailableSemaphore = DispatchSemaphore(value: 0)

    init() {}

    func adoptConnection(_ existingConnection: NWConnection, host: String, port: UInt16) {
        AppLog.i("TcpHandler: adopting prepared connection for \(host):\(port)", tag: "TcpHandler")
        disconnect()
        connection = existingConnection
        isConnected = true
        setupStateHandler(host: host, port: port)
        startReceiving()
        if Thread.isMainThread {
            delegate?.byteStreamConnectionDidConnect(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.byteStreamConnectionDidConnect(self)
            }
        }
    }

    func acceptConnection(_ acceptedConnection: NWConnection, host: String, port: UInt16) {
        AppLog.i("TcpHandler: accepting inbound connection for host=\(host), port=\(port)", tag: "TcpHandler")

        disconnect()
        connection = acceptedConnection
        setupStateHandler(host: host, port: port)
        connection?.start(queue: queue)
        startConnectionTimeout()
    }

    public func accept(connection incomingConnection: NWConnection, initialData: Data = Data()) {
        var remoteHost = "unknown"
        var remotePort: UInt16 = 5000
        if case .hostPort(let host, let port) = incomingConnection.endpoint {
            switch host {
            case .name(let name, _): remoteHost = name
            case .ipv4(let addr): remoteHost = "\(addr)"
            case .ipv6(let addr): remoteHost = "\(addr)"
            @unknown default: remoteHost = "\(host)"
            }
            remotePort = port.rawValue
        }
        AppLog.i("TcpHandler: accepting incoming connection from \(remoteHost):\(remotePort) with \(initialData.count) initial bytes", tag: "TcpHandler")

        disconnect()
        connection = incomingConnection

        if !initialData.isEmpty {
            pendingDataLock.lock()
            pendingData.append(initialData)
            pendingDataLock.unlock()
        }

        setupStateHandler(host: remoteHost, port: remotePort)

        switch incomingConnection.state {
        case .ready:
            connectionTimer?.cancel()
            isConnected = true
            delegate?.byteStreamConnectionDidConnect(self)
            if !initialData.isEmpty {
                delegate?.byteStreamConnection(self, didReceive: initialData)
            }
            startReceiving()
        case .setup:
            incomingConnection.start(queue: queue)
            startConnectionTimeout()
        default:
            startConnectionTimeout()
        }
    }

    func connect(host: String, port: UInt16) {
        AppLog.i("TcpHandler: connect called with host=\(host), port=\(port)", tag: "TcpHandler")

        disconnect()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)

        AppLog.i("TcpHandler: Creating NWConnection (plain TCP) to \(endpoint)", tag: "TcpHandler")
        connection = NWConnection(to: endpoint, using: parameters)

        setupStateHandler(host: host, port: port)

        AppLog.i("TcpHandler: Starting connection...", tag: "TcpHandler")
        connection?.start(queue: queue)
        AppLog.i("TcpHandler: connection.start() called", tag: "TcpHandler")

        startConnectionTimeout()
    }

    private func setupStateHandler(host: String, port: UInt16) {
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            AppLog.i("TcpHandler: connection state changed to: \(String(describing: state))", tag: "TcpHandler")

            switch state {
            case .setup:
                AppLog.d("TcpHandler: state = setup", tag: "TcpHandler")

            case .preparing:
                AppLog.d("TcpHandler: state = preparing", tag: "TcpHandler")

            case .ready:
                AppLog.i("TcpHandler: state = ready, connected!", tag: "TcpHandler")
                self.connectionTimer?.cancel()
                self.isConnected = true
                self.delegate?.byteStreamConnectionDidConnect(self)
                self.startReceiving()

            case .failed(let error):
                AppLog.e("TcpHandler: state = failed, error=\(error)", tag: "TcpHandler")
                self.connectionTimer?.cancel()
                self.isConnected = false
                DispatchQueue.main.async {
                    self.delegate?.byteStreamConnection(self, didDisconnect: error)
                }

            case .cancelled:
                AppLog.w("TcpHandler: state = cancelled", tag: "TcpHandler")
                self.connectionTimer?.cancel()
                self.isConnected = false
                DispatchQueue.main.async {
                    self.delegate?.byteStreamConnection(self, didDisconnect: nil)
                }

            case .waiting(let error):
                AppLog.w("TcpHandler: state = waiting, error=\(error)", tag: "TcpHandler")

            @unknown default:
                AppLog.w("TcpHandler: state = unknown", tag: "TcpHandler")
            }
        }
    }

    private func startConnectionTimeout() {
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !self.isConnected {
                AppLog.w("TcpHandler: Connection timeout after \(self.connectionTimeout)s", tag: "TcpHandler")
                DispatchQueue.main.async {
                    self.delegate?.byteStreamConnection(self, didDisconnect: TcpHandlerError.timeout)
                }
                self.disconnect()
            }
        }
        connectionTimer = timer
        queue.asyncAfter(deadline: .now() + connectionTimeout, execute: timer)
    }

    func disconnect() {
        AppLog.i("TcpHandler: disconnect called", tag: "TcpHandler")
        connectionTimer?.cancel()
        connectionTimer = nil
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    func send(_ data: Data, completion: ((Error?) -> Void)?) {
        guard let connection = connection, isConnected else {
            AppLog.w("TcpHandler: send called but not connected", tag: "TcpHandler")
            completion?(TcpHandlerError.invalidState)
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                AppLog.e("TcpHandler: send error: \(error)", tag: "TcpHandler")
            }
            completion?(error)
        })
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.receiveQueue.async {
                    self.delegate?.byteStreamConnection(self, didReceive: data)
                }
            }

            if let error = error {
                AppLog.e("TcpHandler: receive error: \(error)", tag: "TcpHandler")
                self.disconnect()
                return
            }

            if isComplete {
                AppLog.i("TcpHandler: connection complete", tag: "TcpHandler")
                self.disconnect()
                return
            }

            self.startReceiving()
        }
    }
}
