//
//  WirelessHelperServer.swift
//  HeadunitPad
//
//  TCP listener for Headunit Revived Wireless Helper mode.
//

import Foundation
import Network

protocol WirelessHelperServerDelegate: AnyObject {
    func wirelessHelperServer(_ server: WirelessHelperServer, didAccept connection: NWConnection, remoteHost: String?, initialData: Data)
    func wirelessHelperServer(_ server: WirelessHelperServer, didFail error: Error)
}

final class WirelessHelperServer {
    weak var delegate: WirelessHelperServerDelegate?

    private let queue = DispatchQueue(label: "com.headunitpad.wireless-helper-server", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var isRunning = false

    public static let defaultPort: UInt16 = 5000
    public static let serviceType = "_aawireless._tcp"
    public private(set) var listeningPort: UInt16 = 5000

    func start(port: UInt16 = WirelessHelperServer.defaultPort, enableBonjour: Bool = true) {
        if isRunning && self.listeningPort == port && self.listener != nil {
            return
        }
        if let existing = listener {
            existing.cancel()
            listener = nil
        }
        self.isRunning = false
        self.listeningPort = port

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.noDelay = true

            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: parameters, on: nwPort)
            if enableBonjour {
                listener.service = NWListener.Service(name: "HeadunitPad", type: Self.serviceType)
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    print("WirelessHelperServer: listening on \(port)")
                case .failed(let error):
                    self.isRunning = false
                    print("WirelessHelperServer: failed: \(error)")
                    DispatchQueue.main.async {
                        self.delegate?.wirelessHelperServer(self, didFail: error)
                    }
                case .cancelled:
                    self.isRunning = false
                    print("WirelessHelperServer: stopped")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else {
                    connection.cancel()
                    return
                }
                let remoteHost = Self.hostString(from: connection.endpoint)
                print("WirelessHelperServer: accepted connection from \(remoteHost ?? "unknown")")
                self.sniffAndRoute(connection: connection, remoteHost: remoteHost)
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            isRunning = false
            DispatchQueue.main.async {
                self.delegate?.wirelessHelperServer(self, didFail: error)
            }
        }
    }

    private func sniffAndRoute(connection: NWConnection, remoteHost: String?) {
        var completed = false
        let lock = NSLock()

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            lock.unlock()

            guard let self = self, let conn = connection else { return }
            print("WirelessHelperServer: Sniff timeout 200ms reached without data from \(remoteHost ?? "unknown"). Routing as raw AAP.")
            DispatchQueue.main.async {
                self.delegate?.wirelessHelperServer(self, didAccept: conn, remoteHost: remoteHost, initialData: Data())
            }
        }

        queue.asyncAfter(deadline: .now() + 0.2, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { [weak connection] state in
            if case .failed = state {
                timeoutWorkItem.cancel()
            }
        }
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] content, _, _, _ in
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            lock.unlock()
            timeoutWorkItem.cancel()

            guard let self = self, let conn = connection else { return }
            let data = content ?? Data()

            // Sniff if WPP control frame
            let isWpp: Bool
            if data.count >= 4 {
                let wppType = (Int(data[2]) << 8) | Int(data[3])
                isWpp = (wppType >= 1 && wppType <= 11)
            } else {
                isWpp = false
            }

            if isWpp {
                print("WirelessHelperServer: Sniffed WPP control frame from \(remoteHost ?? "unknown"), responding with WifiStartRequest for port 5000")
                let stationIp = NetworkAddresses.stationIpv4() ?? "0.0.0.0"
                let wppType = (Int(data[2]) << 8) | Int(data[3])
                if wppType == WppMessageType.pingRequest.rawValue {
                    let payload = (data.count > 4) ? data.subdata(in: 4..<data.count) : Data()
                    if let pingResp = try? WppFraming.encodeFrame(payload: payload, type: WppMessageType.pingResponse) {
                        conn.send(content: pingResp, completion: .contentProcessed({ _ in }))
                    }
                } else {
                    let req = WppMessages.startRequest(ip: stationIp, port: 5000)
                    if let framed = try? WppMessages.frame(req, type: WppMessageType.startRequest) {
                        conn.send(content: framed, completion: .contentProcessed({ _ in }))
                    }
                }
            } else {
                print("WirelessHelperServer: Sniffed raw AAP packet (\(data.count) bytes) from \(remoteHost ?? "unknown"). Routing to AAP transport.")
                DispatchQueue.main.async {
                    self.delegate?.wirelessHelperServer(self, didAccept: conn, remoteHost: remoteHost, initialData: data)
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private static func hostString(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else {
            return nil
        }

        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        @unknown default:
            return nil
        }
    }
}
