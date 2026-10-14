//
//  ProjectionDeepLink.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ProjectionDeepLink.kt
//  Builds Android Auto's standard wireless setup deep-link URL (https://androidauto.com/projection/setup?data=...).
//

import Foundation

public enum ProjectionDeepLink {
    public static let baseUrl = "https://androidauto.com/projection/setup"

    private static let bssidRegex = try? NSRegularExpression(pattern: "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
    private static let dongleMarkers = ["Intercooler", "AndroidAuto-", "AAWireless-"]

    public enum Invalid: Error, Equatable {
        case noSsid
        case noPasskey
        case noBssid
        case noAddress
        case noBluetoothDevice

        public var reason: String {
            switch self {
            case .noSsid: return "This head unit's network name is not known yet."
            case .noPasskey: return "This head unit's network password is not known yet."
            case .noBssid: return "This head unit's WiFi MAC address could not be read."
            case .noAddress: return "This head unit's own IP address on that network is not known yet."
            case .noBluetoothDevice: return "No Bluetooth device address available to identify this head unit by."
            }
        }
    }

    public enum Result: Equatable {
        case ok(url: String)
        case failed(invalid: Invalid)
    }

    public static func looksLikeDongle(_ name: String?) -> Bool {
        guard let name = name else { return false }
        for marker in dongleMarkers {
            if name.contains(marker) { return true }
        }
        return false
    }

    public static func isValidBssid(_ bssid: String) -> Bool {
        let range = NSRange(location: 0, length: bssid.utf16.count)
        return bssidRegex?.firstMatch(in: bssid, options: [], range: range) != nil
    }

    public static func build(
        ssid: String,
        passkey: String,
        bssid: String,
        wppTcpIp: String,
        wppTcpPort: Int,
        bluetoothMac: String
    ) -> Result {
        if ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed(invalid: .noSsid)
        }
        if passkey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed(invalid: .noPasskey)
        }
        if !isValidBssid(bssid) {
            return .failed(invalid: .noBssid)
        }
        if wppTcpIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wppTcpIp == WppMessages.gatewayAddress {
            return .failed(invalid: .noAddress)
        }
        if !isValidBssid(bluetoothMac) {
            return .failed(invalid: .noBluetoothDevice)
        }

        let linkData = ProjectionDeepLinkData(
            ssid: ssid,
            bssid: bssid.lowercased(),
            passkey: passkey,
            wppTcpIp: wppTcpIp,
            wppTcpPort: Int32(wppTcpPort),
            bluetoothMac: bluetoothMac.uppercased(),
            securityMode: .wpa2Personal
        )

        var writer = ProtoWriter()
        linkData.encode(to: &writer)
        let base64 = base64Url(writer.data)
        return .ok(url: "\(baseUrl)?data=\(base64)")
    }

    /// RFC 4648 Section 5 URL-safe unpadded Base64
    public static func base64Url(_ data: Data) -> String {
        var base64 = data.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
        base64 = base64.replacingOccurrences(of: "/", with: "_")
        base64 = base64.replacingOccurrences(of: "=", with: "")
        return base64
    }

    public static func generateUri(
        ssid: String,
        passphrase: String,
        ipAddress: String,
        port: Int,
        bssid: String = "00:11:22:33:44:55",
        bluetoothMac: String = "AA:BB:CC:DD:EE:FF"
    ) -> String {
        let linkData = ProjectionDeepLinkData(
            ssid: ssid,
            bssid: bssid.lowercased(),
            passkey: passphrase,
            wppTcpIp: ipAddress,
            wppTcpPort: Int32(port),
            bluetoothMac: bluetoothMac.uppercased(),
            securityMode: .wpa2Personal
        )

        var writer = ProtoWriter()
        linkData.encode(to: &writer)
        let base64 = base64Url(writer.data)
        return "\(baseUrl)?data=\(base64)"
    }
}
