//
//  Discovery.swift
//  HeadunitPad
//
//  Intelligent network discovery for Android Auto Wireless Headunit Server (port 5277).
//  Optimized for phone hotspot scenarios with iOS Local Network permission awakening,
//  Priority 1 immediate gateway probe (<subnet>.1:5277), and fast batched subnet scanning.
//

import Foundation
import Network

public struct DiscoveredDevice: Identifiable, Equatable {
    public let id = UUID()
    public let ip: String
    public let port: UInt16
    public let name: String?

    public var ipAddress: String {
        return ip
    }

    public init(ip: String, port: UInt16, name: String? = nil) {
        self.ip = ip
        self.port = port
        self.name = name
    }

    public init(id: UUID = UUID(), name: String? = nil, ipAddress: String, port: UInt16 = 5277) {
        self.ip = ipAddress
        self.port = port
        self.name = name
    }

    public var displayName: String {
        if let name = name {
            return name
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
    public static let wppPort: UInt16 = 5288
    public static let launcherPort: UInt16 = 5289

    private var targetPorts: [UInt16] = [Discovery.headunitPort]
    private static var permissionTriggerBrowser: NWBrowser?

    public init() {}

    // MARK: - iOS Local Network Permission Trigger

    /// Awakens the iOS 14+ Local Network permission dialog using a Bonjour browser.
    public static func triggerLocalNetworkPermission() {
        guard permissionTriggerBrowser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_aap._tcp", domain: nil)
        let params = NWParameters()
        let browser = NWBrowser(for: descriptor, using: params)
        permissionTriggerBrowser = browser
        browser.stateUpdateHandler = { state in
            print("Discovery: Local network browser state=\(state)")
        }
        browser.start(queue: DispatchQueue.global(qos: .utility))
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            permissionTriggerBrowser?.cancel()
            permissionTriggerBrowser = nil
        }
    }

    // MARK: - Public Scanning API

    public func startScan(
        ports: [UInt16] = [Discovery.headunitPort],
        historicalIps: [String] = []
    ) {
        guard !isScanning else { return }
        targetPorts = ports.contains(Discovery.headunitPort) ? [Discovery.headunitPort] : ports
        isScanning = true
        reportedEndpoints.removeAll()

        browseWorkItem?.cancel()

        // Trigger local network permission awakening
        Discovery.triggerLocalNetworkPermission()

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
        let old = preparedConnections.removeValue(forKey: key)
        probeLock.unlock()
        old?.cancel()
        return nil
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

        // Priority 1: Instant Gateway Probe (<subnet>.1:5277) + Historical IPs
        var prioritySuspects: [String] = []
        let gatewayIp = "\(subnet).1"
        if gatewayIp != myIp {
            prioritySuspects.append(gatewayIp)
        }
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

        print("Discovery: Priority 1 - probing immediate suspects on 5277: \(prioritySuspects)")
        let priorityGroup = DispatchGroup()
        var foundPriority = false

        for suspect in prioritySuspects {
            guard isScanning else { break }
            priorityGroup.enter()
            probePort(ip: suspect, port: Discovery.headunitPort, timeout: 0.5) { [weak self] success, conn in
                defer { priorityGroup.leave() }
                if success {
                    foundPriority = true
                    print("Discovery: Priority suspect \(suspect):\(Discovery.headunitPort) connected!")
                    self?.reportFoundService(ip: suspect, port: Discovery.headunitPort)
                }
            }
        }

        _ = priorityGroup.wait(timeout: .now() + 0.6)

        // If gateway .1 or historical IP connected, finish immediately!
        if foundPriority {
            print("Discovery: Priority suspect responded, completing discovery immediately without scanning subnet.")
            finishScan()
            return
        }

        guard isScanning else {
            finishScan()
            return
        }

        // Priority 2: Deep parallel scan of remainder of /24 subnet (.2 .. .254)
        print("Discovery: Priority 2 - Deep scan of entire subnet \(subnet).2..254 in parallel batches")
        var candidateIps: [String] = []
        for i in 2...254 {
            let ip = "\(subnet).\(i)"
            if ip != myIp && !prioritySuspects.contains(ip) {
                candidateIps.append(ip)
            }
        }

        // Batches of 28 hosts, 400ms timeout per batch
        let batchSize = 28
        let batches = stride(from: 0, to: candidateIps.count, by: batchSize).map {
            Array(candidateIps[$0..<min($0 + batchSize, candidateIps.count)])
        }

        for batch in batches {
            guard isScanning else { break }
            let batchGroup = DispatchGroup()
            var batchFound = false

            for ip in batch {
                guard isScanning else { break }
                batchGroup.enter()
                probePort(ip: ip, port: Discovery.headunitPort, timeout: 0.4) { [weak self] success, conn in
                    defer { batchGroup.leave() }
                    if success {
                        batchFound = true
                        print("Discovery: Host \(ip):\(Discovery.headunitPort) responded in subnet scan")
                        self?.reportFoundService(ip: ip, port: Discovery.headunitPort)
                    }
                }
            }

            _ = batchGroup.wait(timeout: .now() + 0.45)
            if batchFound {
                print("Discovery: Device found in batch, finishing scan")
                break
            }
        }

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

        let device = DiscoveredDevice(ip: ip, port: port, name: nil)
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

    // MARK: - Host Probing via NWConnection

    private func probePort(
        ip: String,
        port: UInt16,
        timeout: TimeInterval,
        completion: @escaping (Bool, NWConnection?) -> Void
    ) {
        guard isScanning else {
            completion(false, nil)
            return
        }

        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            completion(false, nil)
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: portEndpoint)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
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
                completion(false, nil)
            } else {
                lock.unlock()
            }
        }

        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

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
                conn.stateUpdateHandler = nil
                conn.cancel()
                self.removeActiveProbe(probeId)
                completion(true, nil)

            case .failed, .cancelled:
                hasCompleted = true
                lock.unlock()
                timeoutWorkItem.cancel()
                conn.cancel()
                self.removeActiveProbe(probeId)
                completion(false, nil)

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
