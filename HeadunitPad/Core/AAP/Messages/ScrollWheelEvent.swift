//
//  ScrollWheelEvent.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ScrollWheelEvent.kt
//  Sends rotary controller / scroll wheel relative events on channel ID_INP (1).
//

import Foundation

public final class ScrollWheelEventMessage {
    public static let keycodeScrollWheel: UInt32 = 65536

    public static func make(timestampNs: UInt64, delta: Int) -> AapMessage {
        let rel = RelativeEventRel(
            keycode: ScrollWheelEventMessage.keycodeScrollWheel,
            delta: Int32(delta)
        )
        let relativeEvent = ProtoRelativeEvent(data: [rel])
        let inputReport = InputReport(
            timestamp: timestampNs,
            relativeEvent: relativeEvent
        )
        return AapMessage(
            channel: Int(Channel.ID_INP),
            type: Int(InputMsgType.event.rawValue),
            proto: inputReport
        )
    }
}
