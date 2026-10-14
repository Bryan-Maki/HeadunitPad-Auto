//
//  VehicleTypePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VehicleTypePolicy.kt
//  Controls announced vehicle type (Car, Truck, Motorcycle) and microphone fallback.
//

import Foundation

public enum VehicleTypePolicy {
    public static let car: Int = 1
    public static let truck: Int = 2
    public static let motorcycle: Int = 3

    public static let selectable: [Int] = [car, truck, motorcycle]

    public static func sanitised(_ vehicleType: Int) -> Int {
        return selectable.contains(vehicleType) ? vehicleType : car
    }

    /// When head unit mic is disabled, we must announce Motorcycle so phone uses its own microphone.
    public static func vehicleType(selected: Int, headUnitMicEnabled: Bool) -> Int {
        if headUnitMicEnabled {
            return sanitised(selected)
        } else {
            return motorcycle
        }
    }

    public static func isOverriddenByMicrophone(selected: Int, headUnitMicEnabled: Bool) -> Bool {
        return vehicleType(selected: selected, headUnitMicEnabled: headUnitMicEnabled) != sanitised(selected)
    }

    public static func title(for vehicleType: Int) -> String {
        switch sanitised(vehicleType) {
        case car: return "Car (Passenger Vehicle)"
        case truck: return "Truck (Commercial Vehicle)"
        case motorcycle: return "Motorcycle (Phone Mic)"
        default: return "Car"
        }
    }
}
