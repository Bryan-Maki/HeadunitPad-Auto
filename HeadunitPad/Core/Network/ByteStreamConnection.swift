//
//  ByteStreamConnection.swift
//  HeadunitPad
//

import Foundation

nonisolated protocol ByteStreamConnectionDelegate: AnyObject {
    func byteStreamConnectionDidConnect(_ connection: ByteStreamConnection)
    func byteStreamConnection(_ connection: ByteStreamConnection, didReceive data: Data)
    func byteStreamConnection(_ connection: ByteStreamConnection, didDisconnect error: Error?)
}

nonisolated protocol ByteStreamConnection: AnyObject {
    var delegate: ByteStreamConnectionDelegate? { get set }
    var isConnected: Bool { get }

    func send(_ data: Data, completion: ((Error?) -> Void)?)
    func disconnect()
}

extension ByteStreamConnection {
    func send(_ data: Data) {
        send(data, completion: nil)
    }
}
