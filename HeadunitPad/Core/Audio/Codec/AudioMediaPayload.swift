//
//  AudioMediaPayload.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioMediaPayload.kt
//

import Foundation

/// Audio service payload after AAP/TLS reassembly:
/// - DATA, type 0: [2-byte type][8-byte big-endian timestamp in microseconds][PCM or AAC bytes].
/// - CODEC_CONFIG, type 1: [2-byte type][codec-specific configuration bytes], with no timestamp.
public enum AudioMediaPayload {
    public static func isMedia(type: Int) -> Bool {
        return type == 0 || type == 1
    }

    public static func requiresAck(type: Int) -> Bool {
        return type == 0
    }

    /// Resolves payload offset into the message payload:
    /// For type 0 (DATA): skips 8-byte timestamp, or 10 bytes if outer type prefix is present.
    public static func resolveAudioPayloadOffset(_ payload: Data) -> Int {
        if payload.count >= 10 {
            let typeCandidate = UInt16(payload[0]) << 8 | UInt16(payload[1])
            if typeCandidate == 0 || typeCandidate == 1 {
                return 10
            }
        }
        return 8
    }

    public static func timestampUs(from payload: Data) -> Int64? {
        guard payload.count >= 8 else { return nil }
        var offset = 0
        if payload.count >= 10 {
            let typeCandidate = UInt16(payload[0]) << 8 | UInt16(payload[1])
            if typeCandidate == 0 || typeCandidate == 1 {
                offset = 2
            }
        }
        guard payload.count >= offset + 8 else { return nil }
        var value: Int64 = 0
        for i in 0..<8 {
            value = (value << 8) | Int64(payload[offset + i])
        }
        return value
    }
}
