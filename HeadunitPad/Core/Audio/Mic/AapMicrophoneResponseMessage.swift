//
//  AapMicrophoneResponseMessage.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicrophoneResponse.kt
//

import Foundation

public final class AapMicrophoneResponseMessage {
    public static func make(status: Int, sessionId: Int) -> AapMessage {
        var proto = MicrophoneResponse(status: Int32(status), sessionId: UInt32(sessionId))
        var writer = ProtoWriter()
        proto.encode(to: &writer)
        let payload = writer.data

        return AapMessage(
            channel: Channel.ID_MIC,
            flags: 0x01, // First & last unfragmented frame
            type: 0x8006, // MEDIA_MESSAGE_MICROPHONE_RESPONSE
            payload: payload
        )
    }
}
