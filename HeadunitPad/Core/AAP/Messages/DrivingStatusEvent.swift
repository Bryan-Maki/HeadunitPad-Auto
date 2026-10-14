//
//  DrivingStatusEvent.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DrivingStatusEvent.kt
//  Sends driving status event on channel ID_SEN (7).
//

import Foundation

public final class DrivingStatusEventMessage {
    public static func make(status: Int32 = DrivingStatusPolicy.unrestricted) -> AapMessage {
        let sensorBatch = DrivingStatusPolicy.makeSensorBatch(status: status)
        return AapMessage(
            channel: Int(Channel.ID_SEN),
            type: Int(SensorsMsgType.sensorEvent.rawValue),
            proto: sensorBatch
        )
    }
}
