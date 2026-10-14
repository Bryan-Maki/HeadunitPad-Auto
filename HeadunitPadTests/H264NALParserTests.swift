import XCTest
import Foundation
@testable import HeadunitPad

final class H264NALParserTests: XCTestCase {
    private let sps = Data([0x67, 0x42, 0x00, 0x1F])
    private let pps = Data([0x68, 0xCE, 0x06, 0xE2])

    func testParsesAnnexBParameterSets() {
        let data = Data([0, 0, 0, 1]) + sps + Data([0, 0, 1]) + pps

        XCTAssertEqual(H264NALParser.nalUnits(from: data), [sps, pps])
    }

    func testParsesAVCDecoderConfigurationRecordAfterAAPTypePrefix() {
        var avcC = Data([0x00, 0x01, 0x01, 0x42, 0x00, 0x1F, 0xFF, 0xE1])
        avcC.append(contentsOf: [0x00, UInt8(sps.count)])
        avcC.append(sps)
        avcC.append(0x01)
        avcC.append(contentsOf: [0x00, UInt8(pps.count)])
        avcC.append(pps)

        XCTAssertEqual(H264NALParser.nalUnits(from: avcC), [sps, pps])
        XCTAssertNotNil(H264NALParser.annexBParameterSets(from: avcC))
    }

    func testParsesAVCDecoderConfigurationRecordAfterAAPTypeAndTimestamp() {
        var data = Data([0x00, 0x01])
        data.append(Data(repeating: 0, count: 8))
        data.append(contentsOf: [0x01, 0x42, 0x00, 0x1F, 0xFF, 0xE1])
        data.append(contentsOf: [0x00, UInt8(sps.count)])
        data.append(sps)
        data.append(0x01)
        data.append(contentsOf: [0x00, UInt8(pps.count)])
        data.append(pps)

        XCTAssertEqual(H264NALParser.nalUnits(from: data), [sps, pps])
        XCTAssertNotNil(H264NALParser.annexBParameterSets(from: data))
    }

    func testParsesLengthPrefixedParameterSetsAfterTimestamp() {
        var data = Data(repeating: 0, count: 8)
        for nal in [sps, pps] {
            let length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: length) { data.append(contentsOf: $0) }
            data.append(nal)
        }

        XCTAssertEqual(H264NALParser.nalUnits(from: data), [sps, pps])
    }
}
