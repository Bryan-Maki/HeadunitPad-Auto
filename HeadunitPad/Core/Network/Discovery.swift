//
//  Discovery.swift
//  HeadunitPad
//
//  Intelligent network discovery for Android Auto Wireless Headunit Server (port 5277)
//  and Wireless Helper (port 5289), incorporating DiscoverySubnetPolicy,
//  DhcpGatewayFormat, NetworkAddresses, and SameEndpointConnectPolicy.
//

import Foundation
import Network

public struct DiscoveredDevice: Identifiable, Equatable {
    public let id = UUID()
    public let ip: String
    public let port: UInt16
    public let name: String?

    public init(ip: String, port: UInt16, name: String? = nil) {
        self.ip = ip
        self.port = port
        self.name = name
    }

    public var displayName: String {
        if let name = name {
            return name
        }
        if port == Discovery.launcherPort {
            return "Wireless Helper at \(ip)"
        }
        return "\(ip):\(port)"
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.ip == rhs.ip && lhs.port == rhs.port
    }
}

public protocol DiscoveryDelegate: AnyObject {
    func discoveryDidFindDevice(_ device: DiscoveredDevice)
    func discoveryDidFinish()
    func discoveryDidFail(_ error: Error)
}

public final class Discovery {
    public weak var delegate: DiscoveryDelegate?

    private let queue = DispatchQueue(label: "com.headunitpad.discovery", qos: .userInitiated)
    private var browseWorkItem: DispatchWorkItem?
    private(set) public var isScanning = false
    private var activeProbeConnections: [UUID: NWConnection] = [:]
    private var preparedConnections: [String: NWConnection] = [:]
    private var reportedEndpoints = Set<String>()
    private let probeLock = NSLock()

    public static let headunitPort: UInt16 = 5277
    public static let launcherPort: UInt16 = 5289

    private var targetPorts: [UInt16] = [Discovery.launcherPort, Discovery.headunitPort]
    private let connectionTimeout: TimeInterval = 1.5

    public init() {}

    public func startScan(
        ports: [UInt16] = [Discovery.launcherPort, Discovery.headunitPort],
        historicalIps: [String] = []
    ) {
        guard !isScanning else { return }
        targetPorts = ports
        isScanning = true
        reportedEndpoints.removeAll()

        browseWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performDiscoverySequence(historicalIps: historicalIps)
        }

        browseWorkItem = workItem
        queue.async(execute: workItem)
    }

    public func stopScan() {
        browseWorkItem?.cancel()
        browseWorkItem = nil
        isScanning = false

        probeLock.lock()
        let connections = Array(activeProbeConnections.values)
        activeProbeConnections.removeAll()
        let prepared = Array(preparedConnections.values)
        preparedConnections.removeAll()
        reportedEndpoints.removeAll()
        probeLock.unlock()

        for connection in connections {
            connection.cancel()
        }

        for connection in prepared {
            connection.cancel()
        }
    }

    public func takePreparedConnection(ip: String, port: UInt16) -> NWConnection? {
        let key = SameEndpointConnectPolicy.endpoint(host: ip, port: Int(port))
        probeLock.lock()
        defer { probeLock.unlock() }
        return preparedConnections.removeValue(forKey: key)
    }

    // MARK: - Scan Sequence

    private func performDiscoverySequence(historicalIps: [String]) {
        let stationIp = NetworkAddresses.stationIpv4()
        let firstIp = NetworkAddresses.allInterfaces().first?.ip
        guard let myIp = DiscoverySubnetPolicy.address(stationIpv4: stationIp, firstInterfaceIpv4: firstIp),
              let subnet = DiscoverySubnetPolicy.subnetOf(ipv4: myIp) else {
            print("Discovery: Could not determine valid local subnet (source: \(DiscoverySubnetPolicy.source(stationIpv4: stationIp)))")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
                self?.delegate?.discoveryDidFail(DiscoveryError.noNetworkInterface)
            }
            return
        }

        print("Discovery: Starting discovery on \(myIp) (/24: \(subnet).*)")

        // Step 1: Quick Scan (Gateways, Heuristics, Historical IPs)
        var prioritySuspects: [String] = []
        for hist in historicalIps {
            if hist != myIp && !prioritySuspects.contains(hist) {
                prioritySuspects.append(hist)
            }
        }
        for suspect in NetworkAddresses.defaultGatewaySuspects() {
            if suspect != myIp && !prioritySuspects.contains(suspect) {
                prioritySuspects.append(suspect)
            }
        }

        if !prioritySuspects.isEmpty {
            print("Discovery: Step 1 - Quick scan of \(prioritySuspects.count) suspects: \(prioritySuspects)")
            let gatewayGroup = DispatchGroup()
            var foundAny = false

            for suspect in prioritySuspects {
                guard isScanning else { break }
                gatewayGroup.enter()
                checkHost(ip: suspect) { [weak self] success, foundIP, foundPort in
                    if success, let fIP = foundIP, let fPort = foundPort {
                        foundAny = true
                        self?.reportFoundService(ip: fIP, port: fPort)
                    }
                    gatewayGroup.leave()
                }
            }

            gatewayGroup.wait()

            if foundAny {
                print("Discovery: Suspect responded, completing quick scan")
                finishScan()
                return
            }
        }

        // Step 2: Full /24 Subnet Deep Scan
        guard isScanning else {
            finishScan()
            return
        }

        print("Discovery: Step 2 - Deep scan of entire subnet \(subnet).1..254")
        let subnetGroup = DispatchGroup()

        for i in 1...254 {
            guard isScanning else { break }
            let ip = "\(subnet).\(i)"
            if ip == myIp || prioritySuspects.contains(ip) {
                continue
            }

            subnetGroup.enter()
            checkHost(ip: ip) { [weak self] success, foundIP, foundPort in
                if success, let fIP = foundIP, let fPort = foundPort {
                    self?.reportFoundService(ip: fIP, port: fPort)
                }
                subnetGroup.leave()
            }
        }

        subnetGroup.wait()
        finishScan()
    }

    private func reportFoundService(ip: String, port: UInt16) {
        let ep = SameEndpointConnectPolicy.endpoint(host: ip, port: Int(port))
        probeLock.lock()
        if reportedEndpoints.contains(ep) {
            probeLock.unlock()
            return
        }
        reportedEndpoints.insert(ep)
        probeLock.unlock()

        let name = (port == Discovery.launcherPort) ? "Wireless Helper at \(ip)" : nil
        let device = DiscoveredDevice(ip: ip, port: port, name: name)
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.discoveryDidFindDevice(device)
        }
    }

    private func finishScan() {
        isScanning = false
        print("Discovery: Scan finished")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.discoveryDidFinish()
        }
    }

    // MARK: - Host Probing

    private func checkHost(ip: String, completion: @escaping (Bool, String?, UInt16?) -> Void) {
        guard isScanning else {
            completion(false, nil, nil)
            return
        }
        checkPorts(ip: ip, ports: targetPorts, completion: completion)
    }

    private func checkPorts(ip: String, ports: [UInt16], completion: @escaping (Bool, String?, UInt16?) -> Void) {
        guard isScanning, let port = ports.first else {
            completion(false, nil, nil)
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!)
        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false

        let connection = NWConnection(to: endpoint, using: parameters)
        let probeId = UUID()

        probeLock.lock()
        activeProbeConnections[probeId] = connection
        probeLock.unlock()

        let lock = NSLock()
        var hasCompleted = false

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
            lock.lock()
            if !hasCompleted {
                hasCompleted = true
                lock.unlock()
                connection?.cancel()
                self?.removeActiveProbe(probeId)
                self?.checkPorts(ip: ip, ports: Array(ports.dropFirst()), completion: completion)
            } else {
                lock.unlock()
            }
        }

        queue.asyncAfter(deadline: .now() + connectionTimeout, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            lock.lock()
            guard !hasCompleted else {
                lock.unlock()
                return
            }

            switch state {
            case .ready:
                hasCompleted = true
                lock.unlock()
                timeoutWorkItem.cancel()
                self.removeActiveProbe(probeId)

                if port == Discovery.headunitPort {
                    self.storePreparedConnection(conn, ip: ip, port: port)
                } else {
                    conn.cancel()
                }
                completion(true, ip, port)

            case .failed, .cancelled:
                hasCompleted = true
                lock.unlock()
                timeoutWorkItem.cancel()
                conn.cancel()
                self.removeActiveProbe(probeId)
                self.checkPorts(ip: ip, ports: Array(ports.dropFirst()), completion: completion)

            default:
                lock.unlock()
            }
        }

        connection.start(queue: queue)
    }

    private func removeActiveProbe(_ id: UUID) {
        probeLock.lock()
        activeProbeConnections.removeValue(forKey: id)
        probeLock.unlock()
    }

    private func storePreparedConnection(_ connection: NWConnection, ip: String, port: UInt16) {
        let key = SameEndpointConnectPolicy.endpoint(host: ip, port: Int(port))
        probeLock.lock()
        if let old = preparedConnections[key] {
            old.cancel()
        }
        preparedConnections[key] = connection
        probeLock.unlock()
    }
}

public enum DiscoveryError: Error, LocalizedError {
    case noNetworkInterface
    case scanFailed

    public var errorDescription: String? {
        switch self {
        case .noNetworkInterface:
            return "No valid Wi-Fi network interface found"
        case .scanFailed:
            return "Network discovery scan failed"
        }
    }
}
