import Foundation
import USBHostKit
import XCTest

final class AndroidOpenAccessoryTests: XCTestCase {
    private let identity = AOAIdentity(
        manufacturer: "HeadunitPad",
        model: "iPad Head Unit",
        description: "Wired Android Auto",
        version: "0.3.0",
        uri: "https://github.com/andyching168/headunit-revived",
        serial: "headunit-pad"
    )

    func testAndroidAutoIdentityMatchesHeadUnitProfile() {
        XCTAssertEqual(AOAIdentity.androidAuto, AOAIdentity(
            manufacturer: "Android",
            model: "Android Auto",
            description: "Android Auto",
            version: "2.0.1",
            uri: "https://developer.android.com/auto/index.html",
            serial: "HU-AAAAAA001"
        ))

        XCTAssertEqual(
            AOANegotiationSequence.identityRequests(for: .androidAuto).map(\.buffer),
            [
                "Android",
                "Android Auto",
                "Android Auto",
                "2.0.1",
                "https://developer.android.com/auto/index.html",
                "HU-AAAAAA001",
            ].map { Data($0.utf8) + Data([0]) }
        )
    }

    func testSequenceUsesAOARequestOrderAndFields() {
        let requests = AOANegotiationSequence.requests(for: identity)

        XCTAssertEqual(requests.count, 8)
        XCTAssertEqual(requests.first, AOAControlRequest(
            requestType: 0xC0,
            request: 51,
            value: 0,
            index: 0,
            buffer: Data(count: 2)
        ))

        let stringRequests = Array(requests[1...6])
        XCTAssertEqual(stringRequests.map(\.requestType), Array(repeating: 0x40, count: 6))
        XCTAssertEqual(stringRequests.map(\.request), Array(repeating: 52, count: 6))
        XCTAssertEqual(stringRequests.map(\.value), Array(repeating: 0, count: 6))
        XCTAssertEqual(stringRequests.map(\.index), [0, 1, 2, 3, 4, 5])

        XCTAssertEqual(requests.last, AOAControlRequest(
            requestType: 0x40,
            request: 53,
            value: 0,
            index: 0,
            buffer: Data()
        ))
    }

    func testIdentityPayloadsAreNullTerminatedUTF8() {
        let unicodeIdentity = AOAIdentity(
            manufacturer: "測試廠商",
            model: "Android",
            description: "USB 配件",
            version: "1",
            uri: "https://example.com",
            serial: "序號"
        )
        let expectedStrings = [
            unicodeIdentity.manufacturer,
            unicodeIdentity.model,
            unicodeIdentity.description,
            unicodeIdentity.version,
            unicodeIdentity.uri,
            unicodeIdentity.serial,
        ]

        let requests = AOANegotiationSequence.identityRequests(for: unicodeIdentity)

        for (request, expected) in zip(requests, expectedStrings) {
            XCTAssertEqual(request.buffer, Data(expected.utf8) + Data([0]))
            XCTAssertEqual(request.buffer.last, 0)
        }
    }

    func testProtocolVersionIsParsedAsLittleEndian() throws {
        XCTAssertEqual(
            try AOANegotiationSequence.parseProtocolVersion(from: Data([0x02, 0x01])),
            0x0102
        )
    }

    func testProtocolVersionRequiresExactlyTwoBytes() {
        XCTAssertThrowsError(
            try AOANegotiationSequence.parseProtocolVersion(from: Data([0x02]))
        ) { error in
            XCTAssertEqual(error as? AOAError, .invalidProtocolResponseLength(1))
        }
    }

    func testNegotiatorPerformsCompleteSequence() async throws {
        let transfer = RecordingTransfer(protocolResponse: Data([0x02, 0x00]))
        let negotiator = AOANegotiator(transfer: transfer)

        let version = try await negotiator.negotiate(identity: identity, timeoutMilliseconds: 750)

        XCTAssertEqual(version, 2)
        let calls = await transfer.recordedCalls()
        XCTAssertEqual(calls.map(\.request), [51, 52, 52, 52, 52, 52, 52, 53])
        XCTAssertEqual(calls.map(\.timeoutMilliseconds), Array(repeating: 750, count: 8))
    }

    func testNegotiatorStopsWhenProtocolVersionIsUnsupported() async {
        let transfer = RecordingTransfer(protocolResponse: Data([0x00, 0x00]))
        let negotiator = AOANegotiator(transfer: transfer)

        do {
            _ = try await negotiator.negotiate(identity: identity)
            XCTFail("Expected unsupported protocol error")
        } catch {
            XCTAssertEqual(error as? AOAError, .unsupportedProtocolVersion(0))
        }

        let calls = await transfer.recordedCalls()
        XCTAssertEqual(calls.map(\.request), [51])
    }

    func testNegotiatorTreatsDetachAfterStartAsSuccessfulStart() async throws {
        let transfer = RecordingTransfer(
            protocolResponse: Data([0x02, 0x00]),
            disconnectOnRequest: 53
        )

        let version = try await AOANegotiator(transfer: transfer).negotiate(identity: identity)

        XCTAssertEqual(version, 2)
        let calls = await transfer.recordedCalls()
        XCTAssertEqual(calls.map(\.request), [51, 52, 52, 52, 52, 52, 52, 53])
    }

    func testModeSwitcherNegotiatesAndWaitsForAccessoryReenumeration() async throws {
        let phone = makeDevice(bus: 1, address: 2, vendor: 0x04E8, product: 0x6860)
        let accessory = makeAccessory(bus: 1, address: 3)
        let session = RecordingTransfer(
            protocolResponse: Data([0x02, 0x00]),
            disconnectOnRequest: 53
        )
        let host = RecordingHost(
            probeResults: [[phone], [], [accessory]],
            session: session
        )
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            maximumReenumerationPolls: 3
        )

        let result = try await switcher.switchFirstAvailableDevice()

        XCTAssertEqual(result.sourceDevice, phone)
        XCTAssertEqual(result.protocolVersion, 2)
        XCTAssertEqual(result.accessoryDevice, accessory)
        XCTAssertEqual(result.interfaceNumber, 1)
        XCTAssertEqual(result.bulkInputEndpoint, 0x81)
        XCTAssertEqual(result.bulkOutputEndpoint, 0x02)
        let lifecycle = await host.recordedLifecycle()
        XCTAssertEqual(lifecycle, ["start", "probe", "open:1.2", "probe", "probe", "stop"])
    }

    func testModeSwitcherAdoptsAlreadyEnumeratedAccessoryWhenRestartIsRefused() async throws {
        let accessory = makeAccessory(bus: 2, address: 4)
        let host = RecordingHost(probeResults: [[accessory]], session: nil)
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            accessoryRestartSettleNanoseconds: 0
        )

        let result = try await switcher.switchFirstAvailableDevice()

        XCTAssertNil(result.sourceDevice)
        XCTAssertNil(result.protocolVersion)
        XCTAssertEqual(result.accessoryDevice, accessory)
        // Two opens: the re-enumerate attempt, then the AOA one. Both refused.
        let lifecycle = await host.recordedLifecycle()
        XCTAssertEqual(lifecycle, ["start", "probe", "open:2.4", "open:2.4", "stop"])
    }

    func testModeSwitcherRestartsAnAccessoryLeftOverFromAnEarlierSession() async throws {
        let stale = makeAccessory(bus: 2, address: 4)
        let restarted = makeAccessory(bus: 2, address: 7)
        let session = RecordingTransfer(protocolResponse: Data([0x02, 0x00]))
        // The accessory has to go away and come back for the restart to count.
        let host = RecordingHost(probeResults: [[stale], [], [restarted]], session: session)
        let recorder = StageRecorder()
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            accessoryRestartSettleNanoseconds: 0,
            onStage: { stage in recorder.append(stage) }
        )

        let result = try await switcher.switchFirstAvailableDevice()

        XCTAssertEqual(result.accessoryDevice, restarted)
        XCTAssertEqual(result.protocolVersion, 2)
        // The full sequence: a restarted accessory function loses the identity
        // strings, so Android Auto needs them again before START.
        let calls = await session.recordedCalls()
        XCTAssertEqual(calls.map(\.request), [51, 52, 52, 52, 52, 52, 52, 53])
        let closeCount = await session.recordedCloseCount()
        XCTAssertEqual(closeCount, 2)
        let resetCount = await session.recordedResetCount()
        XCTAssertEqual(resetCount, 1)
        XCTAssertTrue(recorder.values().contains(.restartingExistingAccessory(stale)))

        var diagnostics = AOAProbeDiagnostics()
        for stage in recorder.values() {
            diagnostics.record(stage)
        }
        XCTAssertTrue(diagnostics.didRestartExistingAccessory)
        XCTAssertTrue(diagnostics.didSendStart)
    }

    func testModeSwitcherRenegotiatesFromScratchAfterReEnumeratingTheAccessory() async throws {
        let stale = makeAccessory(bus: 2, address: 4)
        let phone = makeDevice(bus: 2, address: 9, vendor: 0x2717, product: 0xFF08)
        let accessory = makeAccessory(bus: 2, address: 10)
        let session = RecordingTransfer(protocolResponse: Data([0x02, 0x00]), resetError: nil)
        // Gone, back in normal mode, gone again, then finally in accessory mode.
        let host = RecordingHost(
            probeResults: [[stale], [], [phone], [], [accessory]],
            session: session
        )
        let recorder = StageRecorder()
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            accessoryRestartSettleNanoseconds: 0,
            onStage: { stage in recorder.append(stage) }
        )

        let result = try await switcher.switchFirstAvailableDevice()

        // Re-enumeration drops the phone back to normal mode, so the ordinary cold
        // negotiation has to run again rather than adopting the stale accessory.
        XCTAssertEqual(result.sourceDevice, phone)
        XCTAssertEqual(result.accessoryDevice, accessory)
        let resetCount = await session.recordedResetCount()
        XCTAssertEqual(resetCount, 1)

        var diagnostics = AOAProbeDiagnostics()
        for stage in recorder.values() {
            diagnostics.record(stage)
        }
        XCTAssertEqual(diagnostics.deviceResetResult, "Accepted")
        XCTAssertTrue(diagnostics.didObserveAccessoryDetach)
        // The re-enumerate carried it, so the SET_CONFIGURATION fallback is unused.
        XCTAssertNil(diagnostics.softReconfigureResult)
    }

    func testModeSwitcherTreatsDetachDuringAccessoryRestartAsSuccess() async throws {
        let stale = makeAccessory(bus: 2, address: 4)
        let restarted = makeAccessory(bus: 2, address: 7)
        let session = RecordingTransfer(
            protocolResponse: Data([0x02, 0x00]),
            disconnectOnRequest: 53
        )
        let host = RecordingHost(probeResults: [[stale], [], [restarted]], session: session)
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            accessoryRestartSettleNanoseconds: 0
        )

        let result = try await switcher.switchFirstAvailableDevice()

        XCTAssertEqual(result.accessoryDevice, restarted)
    }

    func testModeSwitcherReportsWhenTheAccessoryNeverDetaches() async throws {
        let stale = makeAccessory(bus: 2, address: 4)
        let session = RecordingTransfer(protocolResponse: Data([0x02, 0x00]))
        // Enough probes to cover both the AOA restart wait and the re-configure one.
        let host = RecordingHost(
            probeResults: Array(repeating: [stale], count: 6),
            session: session
        )
        let recorder = StageRecorder()
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            accessoryRestartSettleNanoseconds: 0,
            accessoryRestartReenumerationPolls: 2,
            onStage: { stage in recorder.append(stage) }
        )

        let result = try await switcher.switchFirstAvailableDevice()

        // A phone that never lets go of the device did not restart anything, and
        // the diagnostics must not claim otherwise.
        XCTAssertEqual(result.accessoryDevice, stale)
        XCTAssertFalse(recorder.values().contains(.accessoryDetachObserved))
        var diagnostics = AOAProbeDiagnostics()
        for stage in recorder.values() {
            diagnostics.record(stage)
        }
        XCTAssertTrue(diagnostics.didRestartExistingAccessory)
        XCTAssertFalse(diagnostics.didObserveAccessoryDetach)
        XCTAssertEqual(diagnostics.softReconfigureResult, "Accepted")
    }

    func testPreparedAccessoryKeepsHostAliveUntilOwnershipIsClosed() async throws {
        let accessory = makeAccessory(bus: 2, address: 4)
        let session = RecordingTransfer(protocolResponse: Data([0x02, 0x00]))
        let host = RecordingHost(probeResults: [[accessory]], session: session)
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            accessoryRestartSettleNanoseconds: 0,
            accessoryRestartReenumerationPolls: 1
        )

        let prepared = try await switcher.prepareFirstAvailableAccessory()

        XCTAssertEqual(prepared.result.accessoryDevice, accessory)
        // Ownership, not choreography: the host must outlive the reconnect probing
        // that precedes it and stop only when the caller lets go.
        let activeLifecycle = await host.recordedLifecycle()
        let activeCloseCount = await session.recordedCloseCount()
        XCTAssertFalse(activeLifecycle.contains("stop"))

        await prepared.close()

        let closedLifecycle = await host.recordedLifecycle()
        let closedCount = await session.recordedCloseCount()
        XCTAssertEqual(closedLifecycle.last, "stop")
        XCTAssertEqual(closedCount, activeCloseCount + 1)
    }

    func testModeSwitcherTimesOutWhenAccessoryDoesNotReenumerate() async {
        let phone = makeDevice(bus: 1, address: 2, vendor: 0x04E8, product: 0x6860)
        let session = RecordingTransfer(protocolResponse: Data([0x02, 0x00]))
        let host = RecordingHost(probeResults: [[phone], [], []], session: session)
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            maximumReenumerationPolls: 2
        )

        do {
            _ = try await switcher.switchFirstAvailableDevice()
            XCTFail("Expected re-enumeration timeout")
        } catch {
            XCTAssertEqual(error as? AOAError, .accessoryReenumerationTimedOut)
        }

        let lifecycle = await host.recordedLifecycle()
        XCTAssertEqual(lifecycle.last, "stop")
    }

    func testModeSwitcherReportsPhysicalProbeStages() async throws {
        let phone = makeDevice(bus: 1, address: 2, vendor: 0x04E8, product: 0x6860)
        let accessory = makeAccessory(bus: 1, address: 3)
        let stages = StageRecorder()
        let host = RecordingHost(
            probeResults: [[phone], [accessory]],
            session: RecordingTransfer(
                protocolResponse: Data([0x02, 0x00]),
                disconnectOnRequest: 53
            ),
            registry: "IOUSBHostDevice: Android",
            log: "libusb test log"
        )
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            reenumerationPollNanoseconds: 0,
            onStage: { stage in stages.append(stage) }
        )

        let result = try await switcher.switchFirstAvailableDevice()
        let recorded = stages.values()

        XCTAssertEqual(recorded, [
            .searching,
            .devicesFound([phone]),
            .negotiating(phone),
            .protocolVersion(2),
            .sendingIdentity,
            .startingAccessory,
            .startDetached,
            .waitingForReenumeration,
            .accessoryReady(result),
            .registrySummary("IOUSBHostDevice: Android"),
            .libusbLog("libusb test log"),
        ])
    }

    func testNoDeviceFailureStillReportsRegistryDiagnostics() async {
        let stages = StageRecorder()
        let host = RecordingHost(
            probeResults: [[]],
            session: nil,
            registry: "IOUSBHostDevice: Android"
        )
        let switcher = AOAModeSwitcher(
            host: host,
            identity: identity,
            onStage: { stage in stages.append(stage) }
        )

        do {
            _ = try await switcher.switchFirstAvailableDevice()
            XCTFail("Expected no USB devices error")
        } catch {
            XCTAssertEqual(error as? AOAError, .noUSBDevices)
        }

        XCTAssertEqual(stages.values(), [
            .searching,
            .devicesFound([]),
            .registrySummary("IOUSBHostDevice: Android"),
        ])
        let lifecycle = await host.recordedLifecycle()
        XCTAssertEqual(lifecycle, ["start", "probe", "stop"])
    }

    func testProbeDiagnosticsContainRequiredUSBFields() {
        let phone = makeDevice(bus: 1, address: 2, vendor: 0x04E8, product: 0x6860)
        let accessory = makeAccessory(bus: 1, address: 3)
        let result = AOAModeSwitchResult(
            sourceDevice: phone,
            protocolVersion: 2,
            accessoryDevice: accessory,
            interfaceNumber: 1,
            bulkInputEndpoint: 0x81,
            bulkOutputEndpoint: 0x02
        )
        var diagnostics = AOAProbeDiagnostics()
        diagnostics.record(.negotiating(phone))
        diagnostics.record(.protocolVersion(2))
        diagnostics.record(.startingAccessory)
        diagnostics.record(.startDetached)
        diagnostics.record(.accessoryReady(result))
        diagnostics.record(.devicesFound([phone]))
        diagnostics.record(.registrySummary("IOUSBHostDevice: Android"))
        diagnostics.record(.libusbLog("captured log"))

        let text = diagnostics.lines.joined(separator: "\n")

        XCTAssertTrue(text.contains("Connection kind: USB"))
        XCTAssertTrue(text.contains("Enumerated USB devices: 1"))
        XCTAssertTrue(text.contains("Source VID/PID: 0x04E8:0x6860"))
        XCTAssertTrue(text.contains("Source bus/address: 1/2"))
        XCTAssertTrue(text.contains("AOA protocol version: 2"))
        XCTAssertTrue(text.contains("AOA START sent: Yes"))
        XCTAssertTrue(text.contains("Detach during START response: Yes"))
        XCTAssertTrue(text.contains("Re-enumeration after START: Yes"))
        XCTAssertTrue(text.contains("Accessory VID/PID: 0x18D1:0x2D01"))
        XCTAssertTrue(text.contains("Accessory bus/address: 1/3"))
        XCTAssertTrue(text.contains("Interface: 1"))
        XCTAssertTrue(text.contains("Bulk IN: 0x81"))
        XCTAssertTrue(text.contains("Bulk OUT: 0x02"))
        XCTAssertTrue(text.contains("IORegistry USB devices:\nIOUSBHostDevice: Android"))
        XCTAssertTrue(text.contains("captured log"))
    }

    func testProbeDiagnosticsDistinguishCompletedStartFromReenumeration() {
        let phone = makeDevice(bus: 0, address: 1, vendor: 0x2717, product: 0xFF08)
        let accessory = makeAccessory(bus: 0, address: 1)
        let result = AOAModeSwitchResult(
            sourceDevice: phone,
            protocolVersion: 2,
            accessoryDevice: accessory,
            interfaceNumber: 1,
            bulkInputEndpoint: 0x81,
            bulkOutputEndpoint: 0x02
        )
        var diagnostics = AOAProbeDiagnostics()
        diagnostics.record(.negotiating(phone))
        diagnostics.record(.protocolVersion(2))
        diagnostics.record(.startingAccessory)
        diagnostics.record(.startCompleted)
        diagnostics.record(.waitingForReenumeration)
        diagnostics.record(.accessoryReady(result))

        let text = diagnostics.lines.joined(separator: "\n")

        XCTAssertTrue(text.contains("Detach during START response: No"))
        XCTAssertTrue(text.contains("Re-enumeration after START: Yes"))
    }

    func testProbeDiagnosticsRetainAAPVideoEvidenceAfterDisconnect() {
        var diagnostics = AOAProbeDiagnostics()
        diagnostics.recordAAPVideoDiagnostics([
            "AAP video packets: 3",
            "AAP completed video frames: 1",
            "AAP last completed frame bytes: 4096",
            "AAP video trace: RX flags=0x03 type=0 bytes=4096",
        ])

        let text = diagnostics.lines.joined(separator: "\n")

        XCTAssertTrue(text.contains("AAP video packets: 3"))
        XCTAssertTrue(text.contains("AAP completed video frames: 1"))
        XCTAssertTrue(text.contains("AAP last completed frame bytes: 4096"))
        XCTAssertTrue(text.contains("AAP video trace: RX flags=0x03 type=0 bytes=4096"))
    }

    func testProbeErrorsHaveUserFacingDescriptions() {
        XCTAssertTrue(AOAError.noUSBDevices.localizedDescription.contains("No USB device"))
        XCTAssertTrue(AOAError.noAOACapableDevice.localizedDescription.contains("Android Open Accessory"))
        XCTAssertTrue(AOAError.deviceDetachedDuringNegotiation.localizedDescription.contains("detached"))
        XCTAssertTrue(AOAError.accessoryReenumerationTimedOut.localizedDescription.contains("Timed out"))
        XCTAssertTrue(USBHostError.permission.localizedDescription.contains("entitlement"))
        XCTAssertTrue(USBHostError.timeout.localizedDescription.contains("timed out"))
    }

    private func makeDevice(
        bus: UInt8,
        address: UInt8,
        vendor: UInt16,
        product: UInt16,
        interfaces: [AOAUSBInterface] = []
    ) -> AOAUSBDevice {
        AOAUSBDevice(
            busNumber: bus,
            deviceAddress: address,
            vendorID: vendor,
            productID: product,
            interfaces: interfaces
        )
    }

    private func makeAccessory(bus: UInt8, address: UInt8) -> AOAUSBDevice {
        makeDevice(
            bus: bus,
            address: address,
            vendor: 0x18D1,
            product: 0x2D01,
            interfaces: [
                AOAUSBInterface(number: 0, endpoints: [
                    AOAUSBEndpoint(address: 0x83, attributes: 0x03),
                    AOAUSBEndpoint(address: 0x04, attributes: 0x03),
                ]),
                AOAUSBInterface(number: 1, endpoints: [
                    AOAUSBEndpoint(address: 0x81, attributes: 0x02),
                    AOAUSBEndpoint(address: 0x02, attributes: 0x02),
                ]),
            ]
        )
    }
}

private actor RecordingTransfer: AOAUSBDeviceSession, USBAccessorySession {
    struct Call: Sendable {
        let requestType: UInt8
        let request: UInt8
        let value: UInt16
        let index: UInt16
        let buffer: Data
        let timeoutMilliseconds: UInt32
    }

    private let protocolResponse: Data
    private let disconnectOnRequest: UInt8?
    private let resetError: USBHostError?
    private var calls: [Call] = []
    private var closeCount = 0
    private var resetCount = 0

    init(
        protocolResponse: Data,
        disconnectOnRequest: UInt8? = nil,
        resetError: USBHostError? = .permission
    ) {
        self.protocolResponse = protocolResponse
        self.disconnectOnRequest = disconnectOnRequest
        self.resetError = resetError
    }

    func resetDevice() async throws {
        resetCount += 1
        if let resetError {
            throw resetError
        }
    }

    func recordedResetCount() -> Int {
        resetCount
    }

    func controlTransfer(
        requestType: UInt8,
        request: UInt8,
        value: UInt16,
        index: UInt16,
        buffer: Data,
        timeoutMilliseconds: UInt32
    ) async throws -> Data {
        calls.append(Call(
            requestType: requestType,
            request: request,
            value: value,
            index: index,
            buffer: buffer,
            timeoutMilliseconds: timeoutMilliseconds
        ))
        if request == disconnectOnRequest {
            throw USBHostError.disconnected
        }
        return request == 51 ? protocolResponse : Data()
    }

    func claimInterface(_ number: UInt8) async throws {}

    func releaseInterface(_ number: UInt8) async throws {}

    func read(endpoint: UInt8, length: Int, timeoutMilliseconds: UInt32) async throws -> USBAccessoryReadResult {
        throw USBHostError.timeout
    }

    func write(endpoint: UInt8, data: Data, timeoutMilliseconds: UInt32) async throws {}

    func close() async {
        closeCount += 1
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func recordedCloseCount() -> Int {
        closeCount
    }
}

private actor RecordingHost: AOAUSBHosting {
    private var probeResults: [[AOAUSBDevice]]
    private let session: (any AOAUSBDeviceSession)?
    private let registry: String?
    private let log: String?
    private var lifecycle: [String] = []

    init(
        probeResults: [[AOAUSBDevice]],
        session: (any AOAUSBDeviceSession)?,
        registry: String? = nil,
        log: String? = nil
    ) {
        self.probeResults = probeResults
        self.session = session
        self.registry = registry
        self.log = log
    }

    func start() async throws {
        lifecycle.append("start")
    }

    func stop() async {
        lifecycle.append("stop")
    }

    func probeDevices() async throws -> [AOAUSBDevice] {
        lifecycle.append("probe")
        guard !probeResults.isEmpty else { return [] }
        return probeResults.removeFirst()
    }

    func open(_ device: AOAUSBDevice) async throws -> any AOAUSBDeviceSession {
        lifecycle.append("open:\(device.id)")
        guard let session else { throw USBHostError.disconnected }
        return session
    }

    func libusbLog() async -> String? {
        log
    }

    func registrySummary() async -> String? {
        registry
    }

    func recordedLifecycle() -> [String] {
        lifecycle
    }
}

private final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [AOAModeSwitchStage] = []

    func append(_ stage: AOAModeSwitchStage) {
        lock.lock()
        stages.append(stage)
        lock.unlock()
    }

    func values() -> [AOAModeSwitchStage] {
        lock.lock()
        defer { lock.unlock() }
        return stages
    }
}
