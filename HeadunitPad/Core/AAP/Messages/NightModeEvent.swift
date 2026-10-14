//
//  NightModeEvent.swift
//  HeadunitPad
//
//  1:1 port of open-headunit NightModeEvent.kt
//  Sends day/night sensor event on channel ID_SEN (7).
//

import Foundation

public final class NightModeEventMessage {
    public static func make(isNight: Bool) -> AapMessage {
        let sensorBatch = SensorBatch(
            nightMode: [
                SensorBatch.NightData(isNightMode: isNight)
            ]
        )
        return AapMessage(
            channel: Int(Channel.ID_SEN),
            type: Int(SensorsMsgType.sensorEvent.rawValue),
            proto: sensorBatch
        )
    }
}
