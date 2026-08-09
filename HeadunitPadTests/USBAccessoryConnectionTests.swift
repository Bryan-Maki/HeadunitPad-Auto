import XCTest
import Foundation
import USBHostKit

final class USBAccessoryConnectionTests: XCTestCase {
    func testRejectsInvalidEndpointDirections() async {
        let session = RecordingUSBAccessorySession()

        XCTAssertThrowsError(try USBAccessoryConnection(
            session: session,
            interfaceNumber: 0,
            inputEndpoint: 0x01,
            outputEndpoint: 0x81
        )) { error in
            XCTAssertEqual(error as? USBAccessoryConnectionError, .invalidEndpoint)
        }
    }

    func testConnectClaimsInterfaceAndDeliversPartialTimeoutBytes() async throws {
        let payload = Data([0x00, 0x03, 0x01])
        let session = RecordingUSBAccessorySession(readActions: [
            .result(USBAccessoryReadResult(data: payload, recoveredFromTimeout: true)),
        ])
        let connection = try makeConnection(session: session)
        let delegate = USBConnectionDelegateRecorder()
        connection.delegate = delegate
        let connected = expectation(description: "connected")
        let received = expectation(description: "partial timeout bytes delivered")
        let disconnected = expectation(description: "disconnected")
        delegate.onConnect = { connected.fulfill() }
        delegate.onReceive = { data in
            XCTAssertEqual(data, payload)
            received.fulfill()
        }
        delegate.onDisconnect = { error in
            XCTAssertNil(error)
            disconnected.fulfill()
        }

        try await connection.connect()
        await fulfillment(of: [connected, received], timeout: 2)
        connection.disconnect()
        await fulfillment(of: [disconnected], timeout: 2)

        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.claimedInterfaces, [0])
        XCTAssertEqual(snapshot.releasedInterfaces, [0])
        XCTAssertEqual(snapshot.closeCount, 1)
    }

    func testWritesAreSerializedInSubmissionOrder() async throws {
        let session = RecordingUSBAccessorySession(writeDelayNanoseconds: 20_000_000)
        let connection = try makeConnection(session: session)
        try await connection.connect()
        let completions = (0..<3).map { expectation(description: "write \($0)") }
        let payloads = [Data([1]), Data([2]), Data([3])]

        for (index, payload) in payloads.enumerated() {
            connection.send(payload) { error in
                XCTAssertNil(error)
                completions[index].fulfill()
            }
        }

        await fulfillment(of: completions, timeout: 2)
        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.writes, payloads)
        XCTAssertEqual(snapshot.maximumConcurrentWrites, 1)
        connection.disconnect()
    }

    func testDetachStopsReadLoopAndCleansUpOnce() async throws {
        let session = RecordingUSBAccessorySession(readActions: [
            .failure(.disconnected),
        ])
        let connection = try makeConnection(session: session)
        let delegate = USBConnectionDelegateRecorder()
        connection.delegate = delegate
        let disconnected = expectation(description: "detach reported")
        delegate.onDisconnect = { error in
            XCTAssertEqual(error as? USBHostError, .disconnected)
            disconnected.fulfill()
        }

        try await connection.connect()
        await fulfillment(of: [disconnected], timeout: 2)
        connection.disconnect()

        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.releasedInterfaces, [0])
        XCTAssertEqual(snapshot.closeCount, 1)
        XCTAssertFalse(connection.isConnected)
    }

    func testDisconnectCancelsInflightAndQueuedWrites() async throws {
        let session = RecordingUSBAccessorySession(writeDelayNanoseconds: 10_000_000_000)
        let connection = try makeConnection(session: session)
        let delegate = USBConnectionDelegateRecorder()
        connection.delegate = delegate
        let disconnected = expectation(description: "disconnect callback")
        delegate.onDisconnect = { error in
            XCTAssertNil(error)
            disconnected.fulfill()
        }
        try await connection.connect()

        let completions = (0..<2).map { expectation(description: "cancelled write \($0)") }
        connection.send(Data([1])) { error in
            XCTAssertNotNil(error)
            completions[0].fulfill()
        }
        connection.send(Data([2])) { error in
            XCTAssertNotNil(error)
            completions[1].fulfill()
        }
        connection.disconnect()

        await fulfillment(of: completions + [disconnected], timeout: 2)
        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.releasedInterfaces, [0])
        XCTAssertEqual(snapshot.closeCount, 1)
    }

    func testConnectDrainsStaleInputBeforeDeliveringData() async throws {
        let stale = Data([0x0b, 0x0b, 0x17, 0x03])
        let live = Data([0x00, 0x03, 0x01])
        let session = RecordingUSBAccessorySession(readActions: [
            .result(USBAccessoryReadResult(data: stale, recoveredFromTimeout: false)),
            .failure(.timeout),
            .result(USBAccessoryReadResult(data: live, recoveredFromTimeout: false)),
        ])
        let connection = try makeConnection(session: session, staleDrainQuietReads: 1)
        let delegate = USBConnectionDelegateRecorder()
        connection.delegate = delegate
        let received = expectation(description: "only post-drain bytes delivered")
        delegate.onReceive = { data in
            XCTAssertEqual(data, live)
            received.fulfill()
        }

        try await connection.connect()
        await fulfillment(of: [received], timeout: 2)

        XCTAssertEqual(connection.drainedStaleBytes, stale.count)
        XCTAssertFalse(connection.staleDrainRanOutOfBudget)
        connection.disconnect()
    }

    func testConnectKeepsDrainingAcrossGapsInTheStaleStream() async throws {
        let first = Data([0x01, 0x02])
        let second = Data([0x03])
        let session = RecordingUSBAccessorySession(readActions: [
            .result(USBAccessoryReadResult(data: first, recoveredFromTimeout: false)),
            .failure(.timeout),
            .result(USBAccessoryReadResult(data: second, recoveredFromTimeout: false)),
            .failure(.timeout),
            .failure(.timeout),
        ])
        let connection = try makeConnection(session: session, staleDrainQuietReads: 2)

        try await connection.connect()

        // A single quiet read is a gap in the burst, not the end of it.
        XCTAssertEqual(connection.drainedStaleBytes, first.count + second.count)
        XCTAssertFalse(connection.staleDrainRanOutOfBudget)
        connection.disconnect()
    }

    func testConnectStopsDrainingWhenTheBudgetRunsOut() async throws {
        let session = RecordingUSBAccessorySession(
            repeatingRead: USBAccessoryReadResult(data: Data([0x00]), recoveredFromTimeout: false)
        )
        let connection = try makeConnection(
            session: session,
            staleDrainQuietReads: 3,
            staleDrainBudgetMilliseconds: 150
        )

        try await connection.connect()

        XCTAssertTrue(connection.staleDrainRanOutOfBudget)
        XCTAssertGreaterThan(connection.drainedStaleBytes, 0)
        connection.disconnect()
    }

    private func makeConnection(
        session: RecordingUSBAccessorySession,
        staleDrainQuietReads: Int = 0,
        staleDrainBudgetMilliseconds: UInt64 = 6_000
    ) throws -> USBAccessoryConnection {
        try USBAccessoryConnection(
            session: session,
            interfaceNumber: 0,
            inputEndpoint: 0x81,
            outputEndpoint: 0x01,
            staleDrainQuietReads: staleDrainQuietReads,
            staleDrainBudgetMilliseconds: staleDrainBudgetMilliseconds
        )
    }
}

private actor RecordingUSBAccessorySession: USBAccessorySession {
    enum ReadAction: Sendable {
        case result(USBAccessoryReadResult)
        case failure(USBHostError)
    }

    struct Snapshot: Sendable {
        let claimedInterfaces: [UInt8]
        let releasedInterfaces: [UInt8]
        let closeCount: Int
        let writes: [Data]
        let maximumConcurrentWrites: Int
    }

    private var readActions: [ReadAction]
    private let repeatingRead: USBAccessoryReadResult?
    private let writeDelayNanoseconds: UInt64
    private var claimedInterfaces: [UInt8] = []
    private var releasedInterfaces: [UInt8] = []
    private var closeCount = 0
    private var writes: [Data] = []
    private var activeWrites = 0
    private var maximumConcurrentWrites = 0

    init(
        readActions: [ReadAction] = [],
        repeatingRead: USBAccessoryReadResult? = nil,
        writeDelayNanoseconds: UInt64 = 0
    ) {
        self.readActions = readActions
        self.repeatingRead = repeatingRead
        self.writeDelayNanoseconds = writeDelayNanoseconds
    }

    func claimInterface(_ number: UInt8) async throws {
        claimedInterfaces.append(number)
    }

    func releaseInterface(_ number: UInt8) async throws {
        releasedInterfaces.append(number)
    }

    func read(endpoint: UInt8, length: Int, timeoutMilliseconds: UInt32) async throws -> USBAccessoryReadResult {
        if !readActions.isEmpty {
            switch readActions.removeFirst() {
            case .result(let result):
                return result
            case .failure(let error):
                throw error
            }
        }
        if let repeatingRead {
            return repeatingRead
        }
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw USBHostError.cancelled
    }

    func write(endpoint: UInt8, data: Data, timeoutMilliseconds: UInt32) async throws {
        activeWrites += 1
        maximumConcurrentWrites = max(maximumConcurrentWrites, activeWrites)
        defer { activeWrites -= 1 }
        if writeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: writeDelayNanoseconds)
        }
        writes.append(data)
    }

    func close() async {
        closeCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            claimedInterfaces: claimedInterfaces,
            releasedInterfaces: releasedInterfaces,
            closeCount: closeCount,
            writes: writes,
            maximumConcurrentWrites: maximumConcurrentWrites
        )
    }
}

private final class USBConnectionDelegateRecorder: ByteStreamConnectionDelegate {
    var onConnect: (() -> Void)?
    var onReceive: ((Data) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    func byteStreamConnectionDidConnect(_ connection: ByteStreamConnection) {
        onConnect?()
    }

    func byteStreamConnection(_ connection: ByteStreamConnection, didReceive data: Data) {
        onReceive?(data)
    }

    func byteStreamConnection(_ connection: ByteStreamConnection, didDisconnect error: Error?) {
        onDisconnect?(error)
    }
}
