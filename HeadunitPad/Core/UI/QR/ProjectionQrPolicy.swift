//
//  ProjectionQrPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ProjectionQrPolicy.kt
//  Decides whether a setup pairing QR code can be shown, and diagnoses why if not.
//

import Foundation

public struct ProjectionQrSnapshot: Equatable {
    public let ssid: String?
    public let passkey: String?
    public let bssid: String?
    public let ip: String?
    public let listeningPort: Int?
    public let bluetoothMac: String?
    public let bluetoothName: String?

    public init(
        ssid: String?,
        passkey: String?,
        bssid: String?,
        ip: String?,
        listeningPort: Int?,
        bluetoothMac: String?,
        bluetoothName: String?
    ) {
        self.ssid = ssid
        self.passkey = passkey
        self.bssid = bssid
        self.ip = ip
        self.listeningPort = listeningPort
        self.bluetoothMac = bluetoothMac
        self.bluetoothName = bluetoothName
    }
}

public enum ProjectionQrPolicy {
    public enum Refusal: Equatable {
        case notRunning
        case notListening
        case noCredentials
        case noBssid
        case noAddress
        case noBluetoothIdentity
        case dongleIdentity

        public var message: String {
            switch self {
            case .notRunning: return "Wireless projection stack is not running yet."
            case .notListening: return "No WPP TCP server is listening."
            case .noCredentials: return "Wi-Fi network name or passkey is missing."
            case .noBssid: return "Wi-Fi BSSID / MAC address could not be determined."
            case .noAddress: return "iPad IP address is not known yet."
            case .noBluetoothIdentity: return "Bluetooth device MAC address is not available."
            case .dongleIdentity: return "Bluetooth name is recognized as a dongle rather than a head unit."
            }
        }
    }

    public enum Result: Equatable {
        case show(url: String)
        case refuse(refusal: Refusal)
    }

    public static func decide(snapshot: ProjectionQrSnapshot?) -> Result {
        guard let snapshot = snapshot else {
            return .refuse(refusal: .notRunning)
        }
        guard let port = snapshot.listeningPort else {
            return .refuse(refusal: .notListening)
        }
        if ProjectionDeepLink.looksLikeDongle(snapshot.bluetoothName) {
            return .refuse(refusal: .dongleIdentity)
        }
        guard let btMac = snapshot.bluetoothMac, ProjectionDeepLink.isValidBssid(btMac) else {
            return .refuse(refusal: .noBluetoothIdentity)
        }

        let built = ProjectionDeepLink.build(
            ssid: snapshot.ssid ?? "",
            passkey: snapshot.passkey ?? "",
            bssid: snapshot.bssid ?? "",
            wppTcpIp: snapshot.ip ?? "",
            wppTcpPort: port,
            bluetoothMac: btMac
        )

        switch built {
        case .ok(let url):
            return .show(url: url)
        case .failed(let inv):
            switch inv {
            case .noSsid, .noPasskey: return .refuse(refusal: .noCredentials)
            case .noBssid: return .refuse(refusal: .noBssid)
            case .noAddress: return .refuse(refusal: .noAddress)
            case .noBluetoothDevice: return .refuse(refusal: .noBluetoothIdentity)
            }
        }
    }

    public static func isValidPairingUri(_ uri: String) -> Bool {
        return uri.hasPrefix(ProjectionDeepLink.baseUrl) && uri.contains("?data=")
    }
}
