//
//  KeyCodeEvent.swift
//  HeadunitPad
//
//  1:1 port of open-headunit KeyCodeEvent.kt
//  Sends hardware key press/release input reports on channel ID_INP (1).
//

import Foundation

public final class KeyCodeEventMessage {
    public static func make(timestampNs: UInt64, keycode: Int, isPress: Bool) -> AapMessage {
        let key = ProtoKey(
            keycode: UInt32(keycode),
            down: isPress,
            metastate: 0,
            longpress: false
        )
        let keyEvent = ProtoKeyEvent(keys: [key])
        let inputReport = InputReport(
            timestamp: timestampNs,
            keyEvent: keyEvent
        )
        return AapMessage(
            channel: Int(Channel.ID_INP),
            type: Int(InputMsgType.event.rawValue),
            proto: inputReport
        )
    }
}
