import XCTest
import Foundation
import Network

final class ByteStreamConnectionTests: XCTestCase {
    func testUserSelectionByebyeRequestUsesAAPControlEncoding() {
        let request = AapMessage.userSelectionByebyeRequest

        XCTAssertEqual(request.channel, Channel.ID_CTR)
        XCTAssertEqual(request.flags, AapFlags.CONTROL_MESSAGE)
        XCTAssertEqual(request.type, AapMessageType.BYEBYE_REQUEST.rawValue)
        XCTAssertEqual(request.payload, Data([0x08, 0x01]))
        XCTAssertEqual(request.toData(), Data([0x00, 0x03, 0x00, 0x04, 0x00, 0x0F, 0x08, 0x01]))
    }

    func testProtocolForwardsSendAndLifecycleCallbacks() {
        let connection = RecordingByteStreamConnection()
        let delegate = RecordingByteStreamDelegate()
        connection.delegate = delegate

        let payload = Data([0x01, 0x02, 0x03])
        connection.connectForTest()
        connection.send(payload)
        connection.receiveForTest(payload)
        connection.disconnect()

        XCTAssertEqual(delegate.events, [.connected, .received(payload), .disconnected])
        XCTAssertEqual(connection.sentData, [payload])
        XCTAssertFalse(connection.isConnected)
    }

    func testTcpHandlerTransfersBytesOverLoopback() throws {
        let queue = DispatchQueue(label: "com.headunitpad.tests.tcp-loopback")
        let listener = try NWListener(using: .tcp, on: .any)
        let handler = TcpHandler()
        let delegate = RecordingByteStreamDelegate()
        handler.delegate = delegate

        let connected = expectation(description: "TcpHandler connected")
        let serverReceived = expectation(description: "Server received client bytes")
        let clientReceived = expectation(description: "TcpHandler received server bytes")
        let sendCompleted = expectation(description: "TcpHandler send completed")
        let clientPayload = Data("client-payload".utf8)
        let serverPayload = Data("server-payload".utf8)
        var acceptedConnection: NWConnection?

        delegate.onConnect = {
            connected.fulfill()
            handler.send(clientPayload) { error in
                XCTAssertNil(error)
                sendCompleted.fulfill()
            }
        }
        delegate.onReceive = { data in
            XCTAssertEqual(data, serverPayload)
            clientReceived.fulfill()
        }
        delegate.onDisconnect = { error in
            if let error {
                XCTFail("Unexpected TCP disconnect error: \(error)")
            }
        }

        listener.newConnectionHandler = { connection in
            acceptedConnection = connection
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(data, clientPayload)
                    serverReceived.fulfill()
                }
                connection.send(content: serverPayload, completion: .contentProcessed { error in
                    XCTAssertNil(error)
                })
            }
            connection.start(queue: queue)
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            handler.connect(host: "127.0.0.1", port: port.rawValue)
        }
        listener.start(queue: queue)

        wait(for: [connected, serverReceived, clientReceived, sendCompleted], timeout: 5)

        delegate.onDisconnect = nil
        handler.disconnect()
        acceptedConnection?.cancel()
        listener.cancel()
    }
}

private final class RecordingByteStreamConnection: ByteStreamConnection {
    weak var delegate: ByteStreamConnectionDelegate?
    private(set) var isConnected = false
    private(set) var sentData: [Data] = []

    func connectForTest() {
        isConnected = true
        delegate?.byteStreamConnectionDidConnect(self)
    }

    func send(_ data: Data, completion: ((Error?) -> Void)?) {
        sentData.append(data)
        completion?(nil)
    }

    func receiveForTest(_ data: Data) {
        delegate?.byteStreamConnection(self, didReceive: data)
    }

    func disconnect() {
        isConnected = false
        delegate?.byteStreamConnection(self, didDisconnect: nil)
    }
}

private final class RecordingByteStreamDelegate: ByteStreamConnectionDelegate {
    enum Event: Equatable {
        case connected
        case received(Data)
        case disconnected
    }

    private(set) var events: [Event] = []
    var onConnect: (() -> Void)?
    var onReceive: ((Data) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    func byteStreamConnectionDidConnect(_ connection: ByteStreamConnection) {
        events.append(.connected)
        onConnect?()
    }

    func byteStreamConnection(_ connection: ByteStreamConnection, didReceive data: Data) {
        events.append(.received(data))
        onReceive?(data)
    }

    func byteStreamConnection(_ connection: ByteStreamConnection, didDisconnect error: Error?) {
        events.append(.disconnected)
        onDisconnect?(error)
    }
}
