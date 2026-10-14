//
//  AapMicrophoneResponseMessage.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicrophoneResponse.kt
//

import Foundation

public final class AapMicrophoneResponseMessage {
    public let status: Int
    public let sessionId: Int

    public init(status: Int = 0, sessionId: Int = 0) {
        self.status = status
        self.sessionId = sessionId
    }

    public func encode() -> Data {
        var data = Data(capacity: 2)
        data.append(UInt8((status >> 8) & 0xFF))
        data.append(UInt8(status & 0xFF))
        return data
    }

    public static func make(status: Int, sessionId: Int = 0) -> AapMessage {
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
