//
//  Phase1ScreenAndFramingTests.swift
//  HeadunitPadTests
//
//  Comprehensive test suite for Phase 1:
//  - Protobuf wire encoder/decoder
//  - AAP framing, multi-packet reassembly & audit
//  - HeadUnitScreenConfig & MarginStrategyPolicy (iPad 4:3 aspect ratio)
//  - TouchCoordinateMapper precision
//  - Typed message serialization (ServiceDiscoveryResponse, UpdateUiConfigRequest, TouchEvent)
//

import XCTest
@testable import HeadunitPad

final class Phase1ScreenAndFramingTests: XCTestCase {

    // MARK: - 1. Protobuf Wire & Encodable Tests

    func testProtoWirePrimitives() throws {
        var writer = ProtoWriter()
        writer.writeVarint(field: 1, value: 42)
        writer.writeZigZag64(field: 2, value: -100)
        writer.writeFixed32(field: 3, value: 0x12345678)
        writer.writeFixed64(field: 4, value: 0x1122334455667788)
        writer.writeString(field: 5, value: "HeadunitPad-Auto")
        writer.writeBytes(field: 6, value: Data([0xDE, 0xAD, 0xBE, 0xEF]))

        let encoded = writer.data
        var reader = ProtoReader(data: encoded)

        var foundVarint: UInt64?
        var foundZigZag: Int64?
        var foundFixed32: UInt32?
        var foundFixed64: UInt64?
        var foundString: String?
        var foundBytes: Data?

        while let tag = try reader.nextTag() {
            switch tag.fieldNumber {
            case 1:
                foundVarint = try reader.readVarint()
            case 2:
                foundZigZag = try reader.readZigZag64()
            case 3:
                foundFixed32 = try reader.readFixed32()
            case 4:
                foundFixed64 = try reader.readFixed64()
            case 5:
                foundString = try reader.readString()
            case 6:
                foundBytes = try reader.readBytes()
            default:
                try reader.skipField(wireType: tag.wireType)
            }
        }

        XCTAssertEqual(foundVarint, 42)
        XCTAssertEqual(foundZigZag, -100)
        XCTAssertEqual(foundFixed32, 0x12345678)
        XCTAssertEqual(foundFixed64, 0x1122334455667788)
        XCTAssertEqual(foundString, "HeadunitPad-Auto")
        XCTAssertEqual(foundBytes, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    // MARK: - 2. AAP Framing, Reassembler & Audit Tests

    func testAapMessageFramingFlags() {
        XCTAssertTrue(AapMessageFraming.isLast(flags: Int(AapFlags.NORMAL_MESSAGE)))
        XCTAssertTrue(AapMessageFraming.carriesMessageType(flags: Int(AapFlags.NORMAL_MESSAGE)))
        XCTAssertFalse(AapMessageFraming.carriesTotalLength(flags: Int(AapFlags.NORMAL_MESSAGE)))

        let firstOnlyFlag: Int = 0x09 // FIRST (0x01) | ENCRYPTED (0x08)
        XCTAssertTrue(AapMessageFraming.carriesMessageType(flags: firstOnlyFlag))
        XCTAssertFalse(AapMessageFraming.isLast(flags: firstOnlyFlag))
        XCTAssertTrue(AapMessageFraming.carriesTotalLength(flags: firstOnlyFlag))

        let middleFlag: Int = 0x08 // ENCRYPTED only
        XCTAssertFalse(AapMessageFraming.carriesMessageType(flags: middleFlag))
        XCTAssertFalse(AapMessageFraming.isLast(flags: middleFlag))
        XCTAssertFalse(AapMessageFraming.carriesTotalLength(flags: middleFlag))

        let lastFlag: Int = 0x0a // LAST (0x02) | ENCRYPTED (0x08)
        XCTAssertFalse(AapMessageFraming.carriesMessageType(flags: lastFlag))
        XCTAssertTrue(AapMessageFraming.isLast(flags: lastFlag))
        XCTAssertFalse(AapMessageFraming.carriesTotalLength(flags: lastFlag))
    }

    func testSingleFragmentReassembly() throws {
        let reassembler = AapMessageReassembler()
        var payload = Data([0x80, 0x01]) // msg type = 0x8001
        payload.append(contentsOf: [1, 2, 3, 4, 5])

        let fragment = AapMessage(
            channel: Int(Channel.ID_CTR),
            flags: 0x0b, // FIRST | LAST | ENCRYPTED
            type: 0x8001,
            dataOffset: 2,
            size: payload.count,
            data: payload
        )

        let result = try reassembler.accept(fragment: fragment, declaredTotal: payload.count)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.channel, Int(Channel.ID_CTR))
        XCTAssertEqual(result?.type, 0x8001)
        XCTAssertEqual(result?.payload, Data([1, 2, 3, 4, 5]))
    }

    func testMultiFragmentReassembly() throws {
        let reassembler = AapMessageReassembler()
        let audit = FragmentedMessageAudit()

        // Say full message is 10 bytes: [type hi, type lo, 8 bytes payload]
        let totalLen = 10
        var frag1Data = Data([0x80, 0x03]) // type = 0x8003
        frag1Data.append(contentsOf: [10, 20, 30]) // 5 bytes in frag1

        let frag2Data = Data([40, 50, 60, 70, 80]) // 5 bytes in frag2

        let frag1 = AapMessage(
            channel: Int(Channel.ID_MPB),
            flags: 0x09, // FIRST | ENCRYPTED
            type: 0x8003,
            dataOffset: 2,
            size: frag1Data.count,
            data: frag1Data
        )

        let frag2 = AapMessage(
            channel: Int(Channel.ID_MPB),
            flags: 0x0a, // LAST | ENCRYPTED
            type: -1,
            dataOffset: 0,
            size: frag2Data.count,
            data: frag2Data
        )

        // Audit frag 1
        let a1 = audit.onMessage(channel: Int(Channel.ID_MPB), flags: 0x09, plaintextLength: 5, declaredTotal: totalLen)
        XCTAssertNil(a1)

        let r1 = try reassembler.accept(fragment: frag1, declaredTotal: totalLen)
        XCTAssertNil(r1, "First fragment should not finish reassembly")

        // Audit frag 2
        let a2 = audit.onMessage(channel: Int(Channel.ID_MPB), flags: 0x0a, plaintextLength: 5, declaredTotal: 0)
        XCTAssertNil(a2, "Normal completion should produce no audit issue")

        let r2 = try reassembler.accept(fragment: frag2, declaredTotal: 0)
        XCTAssertNotNil(r2, "Second fragment should complete assembly")
        XCTAssertEqual(r2?.channel, Int(Channel.ID_MPB))
        XCTAssertEqual(r2?.type, 0x8003)
        XCTAssertEqual(r2?.size, 10)
        XCTAssertEqual(r2?.payload, Data([10, 20, 30, 40, 50, 60, 70, 80]))
    }

    func testStreamingVideoFragmentsYieldedImmediately() throws {
        let reassembler = AapMessageReassembler()

        // Video payload: type=0, size >= 15
        var videoPrefix = Data([0x00, 0x00]) // type 0
        videoPrefix.append(contentsOf: [UInt8](repeating: 0xAA, count: 20))

        let frag1 = AapMessage(
            channel: Int(Channel.ID_VID),
            flags: 0x09, // FIRST
            type: 0,
            dataOffset: 2,
            size: videoPrefix.count,
            data: videoPrefix
        )

        let r1 = try reassembler.accept(fragment: frag1, declaredTotal: 50)
        XCTAssertNotNil(r1, "Video fragment 1 should be yielded immediately for streaming low-latency decoding")
        XCTAssertEqual(r1?.flags, 0x09)
        XCTAssertEqual(r1?.type, 0)

        let frag2Data = Data([UInt8](repeating: 0xBB, count: 28))
        let frag2 = AapMessage(
            channel: Int(Channel.ID_VID),
            flags: 0x0a, // LAST
            type: -1,
            dataOffset: 0,
            size: frag2Data.count,
            data: frag2Data
        )

        let r2 = try reassembler.accept(fragment: frag2, declaredTotal: 0)
        XCTAssertNotNil(r2, "Video fragment 2 (last) should be yielded immediately")
        XCTAssertEqual(r2?.flags, 0x0a)
    }

    func testFragmentAuditDiscrepancyDetection() {
        let audit = FragmentedMessageAudit()

        // Start run declaring 10 bytes
        _ = audit.onMessage(channel: 1, flags: 0x09, plaintextLength: 4, declaredTotal: 10)

        // Finish run with only 3 bytes (total observed = 7 != 10)
        let issue = audit.onMessage(channel: 1, flags: 0x0a, plaintextLength: 3, declaredTotal: 0)
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue?.outcome, .deltaChanged)
        XCTAssertEqual(issue?.delta, 3)

        // Orphan fragment without FIRST
        let orphan = audit.onMessage(channel: 1, flags: 0x08, plaintextLength: 5, declaredTotal: 0)
        XCTAssertNotNil(orphan)
        XCTAssertEqual(orphan?.outcome, .orphanedFragment)
    }

    // MARK: - 3. iPad 4:3 Aspect Ratio Screen Config & Margins

    func testIpadScreenConfigFillMarginMode() {
        let config = HeadUnitScreenConfig.shared
        // Simulate iPad Pro 11" / 12.9" 4:3 panel resolution: 2048 x 1536
        _ = config.updateDimensions(width: 2048, height: 1536)
        config.videoFitMode = .fillMargin
        config.negotiatedResolutionType = ._1920x1080
        config.recalculate()

        // In FillMargin mode on 4:3 display:
        // negotiated video is 1920 x 1080 (16:9).
        // To fill full screen 4:3 without vertical distortion:
        // targetVideoWidthFor4to3 = (1080 * 2048) / 1536 = 1440.
        // widthMargin = 1920 - 1440 = 480.
        // leftMargin = 240, rightMargin = 240.
        // heightMargin = 0.
        let widthMargin = config.getWidthMargin()
        let heightMargin = config.getHeightMargin()

        XCTAssertEqual(widthMargin, 480)
        XCTAssertEqual(heightMargin, 0)
        XCTAssertEqual(config.getLeftMargin(), 240)
        XCTAssertEqual(config.getRightMargin(), 240)
        XCTAssertEqual(config.getTopMargin(), 0)
        XCTAssertEqual(config.getBottomMargin(), 0)

        // Verify active visible dimensions
        let visibleW = config.getNegotiatedWidth() - widthMargin
        let visibleH = config.getNegotiatedHeight() - heightMargin
        XCTAssertEqual(visibleW, 1440)
        XCTAssertEqual(visibleH, 1080)
        XCTAssertEqual(Double(visibleW) / Double(visibleH), 4.0 / 3.0, accuracy: 0.001)
    }

    func testMarginStrategyPolicySelection() {
        // Under fillMargin mode, strategy is always .margin
        let strategyFill = MarginStrategyPolicy.select(
            mode: .fillMargin,
            panelW: 2048,
            panelH: 1536,
            videoW: 1920,
            videoH: 1080
        )
        XCTAssertEqual(strategyFill, .margin)

        // Under fit mode, strategy is .par
        let strategyFit = MarginStrategyPolicy.select(
            mode: .fit,
            panelW: 2048,
            panelH: 1536,
            videoW: 1920,
            videoH: 1080
        )
        XCTAssertEqual(strategyFit, .par)
    }

    // MARK: - 4. Touch Coordinate Inverse Mapping Precision

    func testTouchCoordinateMapperFillMargin() {
        let mapper = TouchCoordinateMapper()
        let container = CGSize(width: 1024, height: 768) // iPad points
        let videoSize = CGSize(width: 1920, height: 1080)

        // In fillMargin: widthMargin = 480, heightMargin = 0
        // Effective video UI active width is 1440
        // left offset is margin/2 = 240

        // 1. Touch at left edge (0, 384)
        let leftTouch = CGPoint(x: 0, y: 384)
        let pLeft = mapper.map(
            point: leftTouch,
            containerSize: container,
            videoSize: videoSize,
            mode: .fillMargin,
            marginW: 480,
            marginH: 0
        )
        XCTAssertEqual(pLeft.x, 240)
        XCTAssertEqual(pLeft.y, 540)

        // 2. Touch at center (512, 384)
        let centerTouch = CGPoint(x: 512, y: 384)
        let pCenter = mapper.map(
            point: centerTouch,
            containerSize: container,
            videoSize: videoSize,
            mode: .fillMargin,
            marginW: 480,
            marginH: 0
        )
        XCTAssertEqual(pCenter.x, 960)
        XCTAssertEqual(pCenter.y, 540)

        // 3. Touch at right edge (1024, 384)
        let rightTouch = CGPoint(x: 1024, y: 384)
        let pRight = mapper.map(
            point: rightTouch,
            containerSize: container,
            videoSize: videoSize,
            mode: .fillMargin,
            marginW: 480,
            marginH: 0
        )
        XCTAssertEqual(pRight.x, 1680)
        XCTAssertEqual(pRight.y, 540)
    }

    func testTouchCoordinateMapperStretch() {
        let mapper = TouchCoordinateMapper()
        let container = CGSize(width: 1000, height: 500)
        let videoSize = CGSize(width: 1920, height: 1080)

        let point = CGPoint(x: 500, y: 250) // center
        let mapped = mapper.map(
            point: point,
            containerSize: container,
            videoSize: videoSize,
            mode: .stretch,
            marginW: 0,
            marginH: 0
        )

        XCTAssertEqual(mapped.x, 960)
        XCTAssertEqual(mapped.y, 540)
    }

    // MARK: - 5. Typed Protocol Message Serializations

    func testUpdateUiConfigRequestSerialization() throws {
        let msg = UpdateUiConfigRequest.make(left: 240, top: 0, right: 240, bottom: 0)

        XCTAssertEqual(msg.channel, Int(Channel.ID_VID))
        XCTAssertEqual(msg.type, Int(MediaMsgType.mediaMessageUpdateUiConfigRequest.rawValue))

        let payload = msg.payload
        var reader = ProtoReader(data: payload)
        let decoded = try UpdateUiConfigRequestProto(from: &reader)

        XCTAssertEqual(decoded.uiConfig.margins?.left, 240)
        XCTAssertEqual(decoded.uiConfig.margins?.top, 0)
        XCTAssertEqual(decoded.uiConfig.margins?.right, 240)
        XCTAssertEqual(decoded.uiConfig.margins?.bottom, 0)
    }

    func testAapTouchEventMessageSerialization() throws {
        let pointers = [(id: 0, x: 960, y: 540)]
        let msg = AapTouchEventMessage.make(
            timestampNs: 123456789,
            action: .press,
            actionIndex: 0,
            pointers: pointers
        )

        XCTAssertEqual(msg.channel, Int(Channel.ID_INP))
        XCTAssertEqual(msg.type, Int(InputMsgType.event.rawValue))

        var reader = ProtoReader(data: msg.payload)
        let report = try InputReport(from: &reader)

        XCTAssertEqual(report.timestamp, 123456789)
        XCTAssertEqual(report.touchEvent?.action, .press)
        XCTAssertEqual(report.touchEvent?.pointerData.count, 1)
        XCTAssertEqual(report.touchEvent?.pointerData.first?.x, 960)
        XCTAssertEqual(report.touchEvent?.pointerData.first?.y, 540)
    }

    func testServiceDiscoveryResponseSerialization() throws {
        let screenConfig = HeadUnitScreenConfig.shared
        _ = screenConfig.updateDimensions(width: 2048, height: 1536)
        screenConfig.videoFitMode = .fillMargin

        let msg = AapServiceDiscoveryResponseMessage.make(
            screenConfig: screenConfig,
            fpsLimit: 60,
            rightHandDrive: false,
            useGps: true,
            useMic: true,
            requestedDpi: 160
        )

        XCTAssertEqual(msg.channel, Int(Channel.ID_CTR))
        XCTAssertEqual(msg.type, Int(ControlMsgType.serviceDiscoveryResponse.rawValue))

        var reader = ProtoReader(data: msg.payload)
        let response = try ServiceDiscoveryResponseProto(from: &reader)

        XCTAssertFalse(response.services.isEmpty)

        // Check Video service
        let videoService = response.services.first(where: { $0.id == UInt32(Channel.ID_VID) })
        XCTAssertNotNil(videoService)
        let videoConfig = videoService?.mediaSinkService?.videoConfigs.first
        XCTAssertNotNil(videoConfig)
        XCTAssertEqual(videoConfig?.marginWidth, 480)
        XCTAssertEqual(videoConfig?.marginHeight, 0)

        // Check Input service
        let inputService = response.services.first(where: { $0.id == UInt32(Channel.ID_INP) })
        XCTAssertNotNil(inputService)
        XCTAssertEqual(inputService?.inputSourceService?.touchscreen?.width, 1920)
        XCTAssertEqual(inputService?.inputSourceService?.touchscreen?.height, 1080)
    }
}
