//
//  ParameterSetTracker.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ParameterSetTracker.kt.
//  Notices when the stream's parameter sets stop being the ones the codec was configured from.
//

import Foundation

public final class ParameterSetTracker {

    public enum Kind: Int, CaseIterable {
        case vps = 0
        case sps = 1
        case pps = 2
    }

    public struct Change: Equatable {
        public let ordinal: Int
        public let kinds: [Kind]

        public init(ordinal: Int, kinds: [Kind]) {
            self.ordinal = ordinal
            self.kinds = kinds
        }
    }

    private var stored: [Data?] = Array(repeating: nil, count: Kind.allCases.count)
    private var pending: Set<Kind> = []
    private var changesReported: Int = 0

    public init() {}

    public func offer(kind: Kind, data: Data, offset: Int, length: Int) -> Bool {
        guard length > 0, offset >= 0, offset + length <= data.count else { return false }
        let sub = data.subdata(in: offset..<(offset + length))
        return offer(kind: kind, data: sub)
    }

    public func offer(kind: Kind, data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let idx = kind.rawValue
        let previous = stored[idx]
        stored[idx] = data

        guard let prev = previous else {
            return false // First arrival is baseline, not change
        }

        if prev == data {
            return false
        }

        pending.insert(kind)
        return true
    }

    public func takeChange() -> Change? {
        guard !pending.isEmpty else { return nil }
        changesReported += 1
        let kinds = Kind.allCases.filter { pending.contains($0) }
        pending.removeAll()
        return Change(ordinal: changesReported, kinds: kinds)
    }

    public func reset() {
        stored = Array(repeating: nil, count: Kind.allCases.count)
        pending.removeAll()
        changesReported = 0
    }
}
