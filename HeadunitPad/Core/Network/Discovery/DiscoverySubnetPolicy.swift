//
//  DiscoverySubnetPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DiscoverySubnetPolicy.kt
//  Determines which IPv4 address and /24 subnet a discovery sweep walks.
//

import Foundation

public enum DiscoverySubnetPolicy {
    /// The network carrying traffic wins; fallback to the first up interface.
    public static func address(stationIpv4: String?, firstInterfaceIpv4: String?) -> String? {
        if let station = stationIpv4, !station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return station
        }
        if let first = firstInterfaceIpv4, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return first
        }
        return nil
    }

    /// Names the address source for logging.
    public static func source(stationIpv4: String?) -> String {
        if let station = stationIpv4, !station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "the joined WiFi network"
        } else {
            return "the first interface that is up"
        }
    }

    /// The first three octets of an IPv4 address, or nil when not a dotted quad.
    public static func subnetOf(ipv4: String?) -> String? {
        guard let host = ipv4?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return nil
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        for part in parts {
            guard let val = Int(part), val >= 0, val <= 255 else {
                return nil
            }
        }
        return parts.prefix(3).joined(separator: ".")
    }

    /// Generates candidate IPv4 host addresses in the /24 subnet for discovery sweeps.
    public static func generateSubnetCandidates(baseIp: String, maxHosts: Int = 254) -> [String] {
        guard let subnet = subnetOf(ipv4: baseIp) else { return [] }
        var list: [String] = []
        let count = min(max(1, maxHosts), 254)
        for i in 1...count {
            list.append("\(subnet).\(i)")
        }
        return list
    }
}
