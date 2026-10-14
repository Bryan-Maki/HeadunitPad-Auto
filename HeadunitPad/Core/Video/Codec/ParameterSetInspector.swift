//
//  ParameterSetInspector.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ParameterSetInspector.kt.
//  Reads the fields of an H.264 or H.265 parameter set that decide how a decoder buffers frames.
//

import Foundation

public enum ParameterSetInspector {

    public struct H264Sps: Equatable, CustomStringConvertible {
        public let profileIdc: Int
        public let levelIdc: Int
        public let picOrderCntType: Int
        public let maxNumRefFrames: Int
        public let width: Int
        public let height: Int
        public let vuiPresent: Bool
        public let bitstreamRestrictionPresent: Bool
        public let maxNumReorderFrames: Int?
        public let maxDecFrameBuffering: Int?

        public var description: String {
            let reorderStr = maxNumReorderFrames.map(String.init) ?? "absent"
            let bufferingStr = maxDecFrameBuffering.map(String.init) ?? "absent"
            return "profile=\(profileIdc) level=\(levelIdc) poc_type=\(picOrderCntType) " +
                "num_ref_frames=\(maxNumRefFrames) size=\(width)x\(height) vui=\(vuiPresent) " +
                "bitstream_restriction=\(bitstreamRestrictionPresent) " +
                "num_reorder_frames=\(reorderStr) " +
                "max_dec_frame_buffering=\(bufferingStr)"
        }
    }

    public struct HevcSps: Equatable, CustomStringConvertible {
        public let generalProfileIdc: Int
        public let generalLevelIdc: Int
        public let chromaFormatIdc: Int
        public let bitDepthLuma: Int
        public let width: Int
        public let height: Int
        public let maxDecPicBuffering: Int
        public let maxNumReorderPics: Int

        public var description: String {
            return "profile=\(generalProfileIdc) level=\(generalLevelIdc) chroma_format=\(chromaFormatIdc) " +
                "bit_depth=\(bitDepthLuma) size=\(width)x\(height) " +
                "max_dec_pic_buffering=\(maxDecPicBuffering) max_num_reorder_pics=\(maxNumReorderPics)"
        }
    }

    public static func parseH264Sps(data: Data, nalHeaderOffset: Int, length: Int) -> H264Sps? {
        let bytes = [UInt8](data)
        return parseH264Sps(bytes: bytes, nalHeaderOffset: nalHeaderOffset, length: length)
    }

    public static func parseH264Sps(bytes: [UInt8], nalHeaderOffset: Int, length: Int) -> H264Sps? {
        guard nalHeaderOffset + length <= bytes.count, length > 1 else { return nil }

        let r = RbspReader(buf: bytes, offset: nalHeaderOffset + 1, length: length - 1)

        let profileIdc = r.u(8)
        r.skip(8) // constraint_set0..5 (6) + reserved_zero_2bits (2)
        let levelIdc = r.u(8)
        _ = r.ue() // seq_parameter_set_id

        var chromaFormatIdc = 1
        if HIGH_PROFILES.contains(profileIdc) {
            chromaFormatIdc = r.ue()
            if chromaFormatIdc == 3 {
                r.skip(1) // separate_colour_plane_flag
            }
            _ = r.ue() // bit_depth_luma_minus8
            _ = r.ue() // bit_depth_chroma_minus8
            r.skip(1)  // qpprime_y_zero_transform_bypass_flag
            if r.u(1) == 1 { // seq_scaling_matrix_present_flag
                let lists = (chromaFormatIdc != 3) ? 8 : 12
                for i in 0..<lists {
                    if r.u(1) == 1 {
                        skipScalingList(r: r, sizeOfList: (i < 6) ? 16 : 64)
                    }
                }
            }
        }

        _ = r.ue() // log2_max_frame_num_minus4
        let picOrderCntType = r.ue()
        switch picOrderCntType {
        case 0:
            _ = r.ue() // log2_max_pic_order_cnt_lsb_minus4
        case 1:
            r.skip(1)  // delta_pic_order_always_zero_flag
            _ = r.se() // offset_for_non_ref_pic
            _ = r.se() // offset_for_top_to_bottom_field
            let cycle = r.ue()
            if cycle > MAX_POC_CYCLE { return nil }
            for _ in 0..<cycle {
                _ = r.se()
            }
        default:
            break
        }

        let maxNumRefFrames = r.ue()
        r.skip(1) // gaps_in_frame_num_value_allowed_flag
        let widthInMbsMinus1 = r.ue()
        let heightInMapUnitsMinus1 = r.ue()
        let frameMbsOnly = r.u(1)
        if frameMbsOnly == 0 {
            r.skip(1) // mb_adaptive_frame_field_flag
        }
        r.skip(1) // direct_8x8_inference_flag

        var width = (widthInMbsMinus1 + 1) * 16
        var height = (2 - frameMbsOnly) * (heightInMapUnitsMinus1 + 1) * 16

        if r.u(1) == 1 { // frame_cropping_flag
            let left = r.ue()
            let right = r.ue()
            let top = r.ue()
            let bottom = r.ue()
            let subWidth = (chromaFormatIdc == 3) ? 1 : 2
            let subHeight = (chromaFormatIdc == 1) ? 2 : 1
            width -= (left + right) * subWidth
            height -= (top + bottom) * subHeight * (2 - frameMbsOnly)
        }

        let vuiPresent = (r.u(1) == 1)
        var bitstreamRestrictionPresent = false
        var maxNumReorderFrames: Int? = nil
        var maxDecFrameBuffering: Int? = nil

        if vuiPresent {
            if r.u(1) == 1 { // aspect_ratio_info_present_flag
                if r.u(8) == 255 {
                    r.skip(32) // Extended_SAR
                }
            }
            if r.u(1) == 1 { r.skip(1) } // overscan_info_present
            if r.u(1) == 1 { // video_signal_type_present_flag
                r.skip(4) // video_format (3) + video_full_range_flag (1)
                if r.u(1) == 1 { r.skip(24) } // colour_description
            }
            if r.u(1) == 1 { _ = r.ue(); _ = r.ue() } // chroma_loc_info_present_flag
            if r.u(1) == 1 { // timing_info_present_flag
                r.skip(32) // num_units_in_tick
                r.skip(32) // time_scale
                r.skip(1)  // fixed_frame_rate_flag
            }
            let nalHrd = (r.u(1) == 1)
            if nalHrd && !skipHrdParameters(r: r) { return nil }
            let vclHrd = (r.u(1) == 1)
            if vclHrd && !skipHrdParameters(r: r) { return nil }
            if nalHrd || vclHrd { r.skip(1) } // low_delay_hrd_flag
            r.skip(1) // pic_struct_present_flag
            bitstreamRestrictionPresent = (r.u(1) == 1)
            if bitstreamRestrictionPresent {
                r.skip(1) // motion_vectors_over_pic_boundaries_flag
                _ = r.ue() // max_bytes_per_pic_denom
                _ = r.ue() // max_bits_per_mb_denom
                _ = r.ue() // log2_max_mv_length_horizontal
                _ = r.ue() // log2_max_mv_length_vertical
                maxNumReorderFrames = r.ue()
                maxDecFrameBuffering = r.ue()
            }
        }

        if r.overran { return nil }

        return H264Sps(
            profileIdc: profileIdc,
            levelIdc: levelIdc,
            picOrderCntType: picOrderCntType,
            maxNumRefFrames: maxNumRefFrames,
            width: width,
            height: height,
            vuiPresent: vuiPresent,
            bitstreamRestrictionPresent: bitstreamRestrictionPresent,
            maxNumReorderFrames: maxNumReorderFrames,
            maxDecFrameBuffering: maxDecFrameBuffering
        )
    }

    public static func parseHevcSps(data: Data, nalHeaderOffset: Int, length: Int) -> HevcSps? {
        let bytes = [UInt8](data)
        return parseHevcSps(bytes: bytes, nalHeaderOffset: nalHeaderOffset, length: length)
    }

    public static func parseHevcSps(bytes: [UInt8], nalHeaderOffset: Int, length: Int) -> HevcSps? {
        guard nalHeaderOffset + length <= bytes.count, length > 2 else { return nil }

        // Skip nal_unit_header: 2 bytes for HEVC
        let r = RbspReader(buf: bytes, offset: nalHeaderOffset + 2, length: length - 2)

        r.skip(4) // sps_video_parameter_set_id
        let maxSubLayersMinus1 = r.u(3)
        r.skip(1) // sps_temporal_id_nesting_flag

        // profile_tier_level
        r.skip(2) // general_profile_space
        r.skip(1) // general_tier_flag
        let generalProfileIdc = r.u(5)
        r.skip(32) // general_profile_compatibility_flag[32]
        r.skip(4)  // progressive/interlaced/non_packed/frame_only
        r.skip(43) // general_reserved_zero_43bits
        r.skip(1)  // general_inbld_flag / reserved_zero_bit
        let generalLevelIdc = r.u(8)

        var subLayerProfilePresent = [Bool](repeating: false, count: maxSubLayersMinus1)
        var subLayerLevelPresent = [Bool](repeating: false, count: maxSubLayersMinus1)
        for i in 0..<maxSubLayersMinus1 {
            subLayerProfilePresent[i] = (r.u(1) == 1)
            subLayerLevelPresent[i] = (r.u(1) == 1)
        }
        if maxSubLayersMinus1 > 0 {
            r.skip(2 * (8 - maxSubLayersMinus1))
        }
        for i in 0..<maxSubLayersMinus1 {
            if subLayerProfilePresent[i] { r.skip(88) }
            if subLayerLevelPresent[i] { r.skip(8) }
        }

        _ = r.ue() // sps_seq_parameter_set_id
        let chromaFormatIdc = r.ue()
        if chromaFormatIdc == 3 {
            r.skip(1) // separate_colour_plane_flag
        }
        var width = r.ue()
        var height = r.ue()

        if r.u(1) == 1 { // conformance_window_flag
            let left = r.ue()
            let right = r.ue()
            let top = r.ue()
            let bottom = r.ue()
            let subWidth = (chromaFormatIdc == 1 || chromaFormatIdc == 2) ? 2 : 1
            let subHeight = (chromaFormatIdc == 1) ? 2 : 1
            width -= (left + right) * subWidth
            height -= (top + bottom) * subHeight
        }

        let bitDepthLuma = r.ue() + 8
        _ = r.ue() // bit_depth_chroma_minus8
        _ = r.ue() // log2_max_pic_order_cnt_lsb_minus4

        let subLayerOrderingInfoPresent = (r.u(1) == 1)
        var maxDecPicBuffering = 0
        var maxNumReorderPics = 0
        let firstLayer = subLayerOrderingInfoPresent ? 0 : maxSubLayersMinus1
        if firstLayer <= maxSubLayersMinus1 {
            for _ in firstLayer...maxSubLayersMinus1 {
                maxDecPicBuffering = r.ue() + 1
                maxNumReorderPics = r.ue()
                _ = r.ue() // sps_max_latency_increase_plus1
            }
        }

        if r.overran { return nil }

        return HevcSps(
            generalProfileIdc: generalProfileIdc,
            generalLevelIdc: generalLevelIdc,
            chromaFormatIdc: chromaFormatIdc,
            bitDepthLuma: bitDepthLuma,
            width: width,
            height: height,
            maxDecPicBuffering: maxDecPicBuffering,
            maxNumReorderPics: maxNumReorderPics
        )
    }

    private static func skipScalingList(r: RbspReader, sizeOfList: Int) {
        var lastScale = 8
        var nextScale = 8
        for _ in 0..<sizeOfList {
            if nextScale != 0 {
                let delta = r.se()
                nextScale = (lastScale + delta + 256) % 256
            }
            if nextScale != 0 { lastScale = nextScale }
        }
    }

    private static func skipHrdParameters(r: RbspReader) -> Bool {
        let cpbCntMinus1 = r.ue()
        if cpbCntMinus1 > MAX_CPB_CNT_MINUS1 { return false }
        r.skip(4) // bit_rate_scale
        r.skip(4) // cpb_size_scale
        for _ in 0...cpbCntMinus1 {
            _ = r.ue() // bit_rate_value_minus1
            _ = r.ue() // cpb_size_value_minus1
            r.skip(1)  // cbr_flag
        }
        r.skip(20) // the four *_length_minus1 / time_offset_length
        return !r.overran
    }

    private static let HIGH_PROFILES: Set<Int> = [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135]
    private static let MAX_CPB_CNT_MINUS1 = 31
    private static let MAX_POC_CYCLE = 255

    public final class RbspReader {
        private let buf: [UInt8]
        private let end: Int
        private var bytePos: Int
        private var bitInByte: Int = 0
        private var zeroRun: Int = 0

        public private(set) var overran: Bool = false

        public init(buf: [UInt8], offset: Int, length: Int) {
            self.buf = buf
            self.bytePos = offset
            self.end = offset + length
        }

        private func currentByte() -> Int {
            if bytePos >= end || bytePos >= buf.count {
                overran = true
                return 0
            }
            return Int(buf[bytePos]) & 0xFF
        }

        private func advanceByte() {
            let consumed = currentByte()
            bytePos += 1
            zeroRun = (consumed == 0) ? zeroRun + 1 : 0
            if zeroRun >= 2 && bytePos < end && bytePos < buf.count && (Int(buf[bytePos]) & 0xFF) == 0x03 {
                bytePos += 1
                zeroRun = 0
            }
        }

        public func u(_ count: Int) -> Int {
            var result = 0
            for _ in 0..<count {
                result = (result << 1) | bit()
            }
            return result
        }

        public func skip(_ count: Int) {
            for _ in 0..<count {
                _ = bit()
            }
        }

        public func ue() -> Int {
            var leadingZeros = 0
            while bit() == 0 {
                leadingZeros += 1
                if overran || leadingZeros > 32 {
                    overran = true
                    return 0
                }
            }
            if leadingZeros == 0 { return 0 }
            return (1 << leadingZeros) - 1 + u(leadingZeros)
        }

        public func se() -> Int {
            let k = ue()
            return (k % 2 == 0) ? -(k / 2) : (k + 1) / 2
        }

        private func bit() -> Int {
            let b = currentByte()
            let value = (b >> (7 - bitInByte)) & 1
            bitInByte += 1
            if bitInByte == 8 {
                bitInByte = 0
                advanceByte()
            }
            return value
        }
    }
}
