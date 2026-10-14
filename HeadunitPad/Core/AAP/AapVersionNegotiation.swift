//
//  AapVersionNegotiation.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AapVersionNegotiation.kt
//

import Foundation

public enum AapVersionNegotiation {
    public static let announcedMajor = 1
    public static let announcedMinor = 2
    public static let featureMinor16 = 6

    public struct NegotiationResult: Equatable {
        public let major: Int
        public let minor: Int
        public let status: Int
        public let requestedConfig: ConnectionConfiguration?

        public var supports16: Bool {
            return major > 1 || (major == 1 && minor >= featureMinor16)
        }

        public var statusName: String {
            if let st = MessageStatus(rawValue: Int32(status)) {
                return "\(st)"
            }
            return "UNKNOWN(\(status))"
        }

        public init(major: Int, minor: Int, status: Int, requestedConfig: ConnectionConfiguration? = nil) {
            self.major = major
            self.minor = minor
            self.status = status
            self.requestedConfig = requestedConfig
        }
    }

    public static func parse(frame: Data, length: Int) -> NegotiationResult? {
        guard length >= 12, frame.count >= length else { return nil }

        func u16(_ index: Int) -> Int {
            return (Int(frame[index]) << 8) | Int(frame[index + 1])
        }

        let major = u16(6)
        let minor = u16(8)
        let rawStatus = u16(10)
        let signedStatus = (rawStatus >= 0x8000) ? (rawStatus - 0x10000) : rawStatus

        var config: ConnectionConfiguration? = nil
        if length > 12 {
            let trailing = frame.subdata(in: 12..<length)
            var reader = ProtoReader(data: trailing)
            if let options = try? VersionResponseOptions(from: &reader) {
                config = options.connectionConfiguration
            }
        }

        return NegotiationResult(major: major, minor: minor, status: signedStatus, requestedConfig: config)
    }
}
