//
//  WppEndpointPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppEndpointPolicy.kt
//  Decides whether to advertise the WPP-over-TCP endpoint to the phone.
//

import Foundation

public enum GroupIdentityStability: Equatable {
    case stable
    case changed
    case renamed
    case unverified
}

public enum WppEndpointDecision: Equatable {
    case advertise(port: Int)
    case withhold(reason: String, ourOwnState: Bool = false)
}

public enum WppEndpointPolicy {
    public static func keepsNetwork(identity: GroupIdentityStability) -> Bool {
        return identity == .stable
    }

    private static let howToClear =
        "Withholding one does not clear one the phone already has: Android Auto keeps an endpoint " +
        "it was given for as long as it is running, and dials it in preference to Bluetooth, " +
        "so if a connection will not start, forget this head unit on the phone"

    public static func decide(
        listeningPort: Int?,
        identity: GroupIdentityStability
    ) -> WppEndpointDecision {
        switch identity {
        case .changed:
            return .withhold(reason: "this unit gives its network a new address every time it comes up. \(howToClear)")
        case .renamed:
            return .withhold(reason: "this unit's network has picked a new name every create. \(howToClear)")
        case .unverified:
            return .withhold(reason: "the network's name and address have not yet been seen to repeat on this unit. \(howToClear)")
        case .stable:
            if let port = listeningPort {
                return .advertise(port: port)
            } else {
                return .withhold(reason: "the WPP TCP server is not listening", ourOwnState: true)
            }
        }
    }
}
