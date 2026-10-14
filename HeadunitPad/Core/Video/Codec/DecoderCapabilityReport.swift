//
//  DecoderCapabilityReport.swift
//  HeadunitPad
//
//  1:1 port and VideoToolbox mapping of open-headunit DecoderCapabilityReport.kt.
//  Inspects whether the hardware/OS claims to support the negotiated codec and resolution.
//

import Foundation
import VideoToolbox
import CoreMedia

public enum DecoderCapabilityReport {

    public struct Capability: Equatable, CustomStringConvertible {
        public let codecType: VideoCodecType
        public let width: Int
        public let height: Int
        public let fps: Int
        public let hardwareAccelerated: Bool
        public let isSupported: Bool

        public var description: String {
            return "codec=\(codecType.rawValue) target=\(width)x\(height)@\(fps) " +
                "hwAccelerated=\(hardwareAccelerated) isSupported=\(isSupported)"
        }
    }

    /// Checks if VideoToolbox supports hardware decoding for the given codec type
    public static func isHardwareDecodeSupported(codec: VideoCodecType) -> Bool {
        switch codec {
        case .h264:
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        case .hevc:
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        }
    }

    /// Evaluates if the current platform can decode the requested stream
    public static func report(for codec: VideoCodecType, width: Int, height: Int, fps: Int) -> Capability {
        let isHw = isHardwareDecodeSupported(codec: codec)

        // iPadOS hardware decoders comfortably support up to 4K 60fps for H.264 and HEVC
        let maxDim = 4096
        let supported = isHw && (width > 0 && width <= maxDim) && (height > 0 && height <= maxDim) && (fps > 0 && fps <= 120)

        return Capability(
            codecType: codec,
            width: width,
            height: height,
            fps: fps,
            hardwareAccelerated: isHw,
            isSupported: supported
        )
    }
}
