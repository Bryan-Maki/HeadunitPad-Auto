//
//  PendingPcm.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PendingPcm.kt
//

import Foundation

/// Cold recovery storage. A replacement receives this prefix before unwritten tail.
public final class PendingPcm {
    private var data: [Int16] = []
    private var offset = 0

    public var isEmpty: Bool {
        return offset >= data.count
    }

    public init() {}

    public func prepend(prefix: [Int16]) {
        guard !prefix.isEmpty else { return }
        data = prefix + Array(data[offset..<data.count])
        offset = 0
    }

    public func take() -> [Int16] {
        let result = Array(data[offset..<data.count])
        data.removeAll()
        offset = 0
        return result
    }
}
