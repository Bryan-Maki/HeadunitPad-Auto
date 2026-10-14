//
//  SameEndpointConnectPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit SameEndpointConnectPolicy.kt
//  Controls endpoint routing and prevents duplicate parallel connections.
//

import Foundation

public enum SameEndpointConnectPolicy {
    public enum Route: Equatable {
        case adoptHeld
        case join
        case dial
    }

    /// True when the requested endpoint matches the one currently in flight.
    public static func joins(inFlight: String?, requested: String?) -> Bool {
        guard let inFlight = inFlight, let requested = requested else { return false }
        return inFlight == requested
    }

    /// A socket discovery holds to the endpoint is adopted, since the server is already bound to it.
    public static func route(held: String?, inFlight: String?, requested: String?) -> Route {
        if joins(inFlight: held, requested: requested) {
            return .adoptHeld
        }
        if joins(inFlight: inFlight, requested: requested) {
            return .join
        }
        return .dial
    }

    /// One canonical spelling per endpoint: no IPv6 scope id, no square brackets.
    public static func endpoint(host: String, port: Int) -> String {
        let cleanHost: String
        if let percentIndex = host.firstIndex(of: "%") {
            cleanHost = String(host[..<percentIndex])
        } else {
            cleanHost = host
        }
        let stripped = cleanHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return "\(stripped):\(port)"
    }
}
