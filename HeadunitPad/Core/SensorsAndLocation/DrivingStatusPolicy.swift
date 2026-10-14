//
//  DrivingStatusPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DrivingStatusEvent.kt and driving restriction policies.
//  Emits unrestricted driving status so Android Auto phone permits keyboard and touch interaction.
//

import Foundation

public enum DrivingStatusPolicy {
    /// In Android Auto sensors.proto, Status.UNRESTRICTED = 0.
    public static let unrestricted: Int32 = 0
    public static let noVideo: Int32 = 1
    public static let noKeyboardInput: Int32 = 2
    public static let noVoiceInput: Int32 = 4
    public static let fullyRestricted: Int32 = 31

    /// Constructs the SensorBatch payload representing the chosen driving status.
    public static func makeSensorBatch(status: Int32 = DrivingStatusPolicy.unrestricted) -> SensorBatch {
        return SensorBatch(
            drivingStatus: [
                SensorBatch.DrivingStatusData(status: status)
            ]
        )
    }

    /// Helper to check if unrestricted input is allowed.
    public static func allowsKeyboardInput(status: Int32) -> Bool {
        return (status & noKeyboardInput) == 0
    }
}
