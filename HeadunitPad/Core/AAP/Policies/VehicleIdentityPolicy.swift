//
//  VehicleIdentityPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VehicleIdentityPolicy.kt
//  Differentiates announced vehicle ID per vehicle type to preserve per-type settings on the phone.
//

import Foundation

public enum VehicleIdentityPolicy {
    /// Produces the announced vehicle ID derived from the base vehicle ID and announced vehicle type.
    public static func vehicleId(base: String, vehicleType: Int) -> String {
        switch vehicleType {
        case VehicleTypePolicy.truck:
            return "\(base)-truck"
        case VehicleTypePolicy.motorcycle:
            return "\(base)-moto"
        default:
            return base
        }
    }
}
