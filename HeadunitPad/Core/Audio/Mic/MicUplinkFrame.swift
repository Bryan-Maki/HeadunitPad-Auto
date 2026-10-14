//
//  MicUplinkFrame.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicUplinkFrame.kt
//

import Foundation

/// The bytes of one microphone message obeying AapMessageFraming.
/// Channel, flags (0x0b), 2-byte type (0), 8-byte timestampUs (big-endian), and PCM payload.
public enum MicUplinkFrame {
    public static let headerSize = 4
    public static let typeOffset = headerSize
    public static let typeSize = 2
    public static let timestampOffset = typeOffset + typeSize
    public static let timestampSize = 8
    public static let pcmOffset = timestampOffset + timestampSize
    public static let flags: UInt8 = 0x0b

    public static func size(pcmLength: Int) -> Int {
        return pcmOffset + pcmLength
    }

    public static func build(timestampUs: Int64, pcm: Data, pcmOffset: Int, pcmLength: Int) -> Data {
        let totalSize = size(pcmLength: pcmLength)
        var into = Data(count: totalSize)

        into.withUnsafeMutableBytes { raw in
            let ptr = raw.baseAddress!
            ptr.advanced(by: 0).assumingMemoryBound(to: UInt8.self).pointee = Channel.ID_MIC
            ptr.advanced(by: 1).assumingMemoryBound(to: UInt8.self).pointee = flags
            ptr.advanced(by: 2).assumingMemoryBound(to: UInt8.self).pointee = 0
            ptr.advanced(by: 3).assumingMemoryBound(to: UInt8.self).pointee = 0

            // Type = 0 (MEDIA_MESSAGE_DATA)
            ptr.advanced(by: typeOffset).assumingMemoryBound(to: UInt8.self).pointee = 0
            ptr.advanced(by: typeOffset + 1).assumingMemoryBound(to: UInt8.self).pointee = 0

            var remaining = timestampUs
            for i in stride(from: timestampSize - 1, through: 0, by: -1) {
                ptr.advanced(by: timestampOffset + i).assumingMemoryBound(to: UInt8.self).pointee = UInt8(remaining & 0xFF)
                remaining = remaining >> 8
            }

            pcm.withUnsafeBytes { pcmRaw in
                memcpy(ptr.advanced(by: pcmOffset), pcmRaw.baseAddress!.advanced(by: pcmOffset), pcmLength)
            }
        }

        return into
    }

    public static func frame(timestampUs: UInt64, pcmData: Data) -> Data {
        var data = Data(count: 2 + 8 + pcmData.count)
        data[0] = 0x00
        data[1] = 0x00
        var ts = timestampUs.bigEndian
        withUnsafeBytes(of: &ts) { raw in
            data.replaceSubrange(2..<10, with: raw)
        }
        data.replaceSubrange(10..<(10 + pcmData.count), with: pcmData)
        return data
    }
}
