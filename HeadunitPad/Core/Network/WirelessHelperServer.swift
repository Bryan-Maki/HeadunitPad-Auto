//
//  WirelessHelperServer.swift
//  HeadunitPad
//
//  TCP listener for Headunit Revived Wireless Helper mode.
//

import Foundation
import Network

protocol WirelessHelperServerDelegate: AnyObject {
    func wirelessHelperServer(_ server: WirelessHelperServer, didAccept connection: NWConnection, remoteHost: String?)
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
                DispatchQueue.main.async {
                    self.delegate?.wirelessHelperServer(self, didAccept: connection, remoteHost: remoteHost)
                }
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
