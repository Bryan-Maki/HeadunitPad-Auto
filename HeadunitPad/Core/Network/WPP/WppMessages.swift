//
//  WppMessages.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppMessages.kt
//  Builds and parses WPP (WiFi Projection Protocol) messages and wire frames.
//

import Foundation

public enum WppMessageType {
    /// Head unit -> phone: where to open the projection session.
    public static let startRequest = 1
    /// Phone -> head unit: asking for the network credentials.
    public static let infoRequest = 2
    /// Head unit -> phone: the credentials.
    public static let infoResponse = 3
    /// Head unit -> phone: our protocol version, opening the modern handshake.
    public static let versionRequest = 4
    /// Phone -> head unit: its protocol version.
    public static let versionResponse = 5
    /// Phone -> head unit: whether it managed to join our network.
    public static let connectStatus = 6
    /// Phone -> head unit: acknowledges START_REQUEST.
    public static let startResponse = 7
    /// Keepalive, either direction. Echo payload back as PING_RESPONSE.
    public static let pingRequest = 8
    public static let pingResponse = 9
    /// Head unit -> phone, TCP only: withdraws the endpoint the phone dialled.
    public static let connectionRejection = 10
    /// Type 11: setup info.
    public static let setupInfo = 11
}

public struct WppEndpoint: Equatable {
    public let ip: String
    public let port: Int

    public init(ip: String, port: Int) {
        self.ip = ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WppMessages.gatewayAddress : ip
        self.port = port
    }
}

public enum WppMessages {
    public static let softwareBuild = "1"
    public static let softwareVersion = "0.1.0"
    public static let gatewayAddress = "0.0.0.0"

    public static func endpoint(ip: String, port: Int) -> WppEndpoint {
        return WppEndpoint(ip: ip, port: port)
    }

    /// Type 4: Version Request
    public static func versionRequest(
        carInfo: WppCarInfo,
        endpoint: WppEndpoint?,
        channelType: WifiChannelType? = nil,
        channels: [Int32] = []
    ) -> WifiVersionRequest {
        var wppInfo: WifiProjectionProtocolInfo? = nil
        if let ep = endpoint {
            wppInfo = WifiProjectionProtocolInfo(ipAddress: ep.ip, port: Int32(ep.port))
        }
        return WifiVersionRequest(
            major: 4,
            minor: 2,
            supportedWifiChannelType: channelType,
            supportedWifiChannels: channels,
            carInfo: carInfo,
            wppInfo: wppInfo
        )
    }

    /// Car Info
    public static func carInfo(
        vehicleMake: String = "Apple",
        vehicleModel: String = "iPad",
        vehicleYear: String = "2026",
        vehicleId: String = "HeadunitPad-001",
        headUnitMake: String = "HeadunitPad",
        headUnitModel: String = "Auto"
    ) -> WppCarInfo {
        return WppCarInfo(
            make: vehicleMake,
            model: vehicleModel,
            modelYear: vehicleYear,
            vehicleId: vehicleId,
            headUnitMake: headUnitMake,
            headUnitModel: headUnitModel,
            headUnitSoftwareBuild: softwareBuild,
            headUnitSoftwareVersion: softwareVersion,
            bodyType: 1
        )
    }

    /// Type 10: Connection Rejection
    public static func connectionRejection() -> WifiConnectionRejection {
        return WifiConnectionRejection(reason: .invalidSetupToken)
    }

    /// Type 1: Start Request
    public static func startRequest(ip: String, port: Int) -> WifiStartRequest {
        return WifiStartRequest(
            ipAddress: ip,
            port: Int32(port),
            startRequestReason: .userRequest
        )
    }

    /// Type 3: Info Response (Credentials)
    public static func infoResponse(
        ssid: String,
        key: String,
        bssid: String? = nil,
        identity: GroupIdentityStability
    ) -> WifiInfoResponse {
        let apType: AccessPointType = WppEndpointPolicy.keepsNetwork(identity: identity) ? .static : .dynamic
        return WifiInfoResponse(
            ssid: ssid,
            key: key,
            bssid: bssid ?? "",
            securityMode: .wpa2Personal,
            accessPointType: apType
        )
    }

    // MARK: - Framing Helpers

    public static func frame<T: ProtoCodable>(_ message: T, type: Int) throws -> Data {
        var writer = ProtoWriter()
        message.encode(to: &writer)
        return try WppFraming.encodeFrame(payload: writer.data, type: type)
    }
}
