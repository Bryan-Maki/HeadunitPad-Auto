//
//  AapNavigation.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AapNavigation.kt & AapNavigationHelper.kt
//  Processes turn-by-turn navigation data on channel ID_NAV (8) from Google Maps / Waze.
//

import Foundation

public struct NavSnapshot: Equatable {
    public var status: NavigationClusterStatus.NavigationStatusEnum
    public var road: String
    public var turnSide: NextTurnDetail.Side?
    public var nextTurn: NextTurnDetail.NextEvent?
    public var turnIconData: Data?
    public var distanceMeters: Int32?
    public var timeToTurnSeconds: Int32?

    public init(
        status: NavigationClusterStatus.NavigationStatusEnum = .inactive,
        road: String = "",
        turnSide: NextTurnDetail.Side? = nil,
        nextTurn: NextTurnDetail.NextEvent? = nil,
        turnIconData: Data? = nil,
        distanceMeters: Int32? = nil,
        timeToTurnSeconds: Int32? = nil
    ) {
        self.status = status
        self.road = road
        self.turnSide = turnSide
        self.nextTurn = nextTurn
        self.turnIconData = turnIconData
        self.distanceMeters = distanceMeters
        self.timeToTurnSeconds = timeToTurnSeconds
    }

    public var formattedDistance: String {
        guard let meters = distanceMeters, meters >= 0 else { return "" }
        if meters < 1000 {
            return "\(meters) m"
        } else {
            let km = Double(meters) / 1000.0
            return String(format: "%.1f km", km)
        }
    }

    public var formattedTime: String {
        guard let seconds = timeToTurnSeconds, seconds >= 0 else { return "" }
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            return "\(mins) min"
        }
    }
}

public final class AapNavigation {
    public static let shared = AapNavigation()

    public var onNavigationUpdate: ((NavSnapshot) -> Void)?
    public private(set) var currentSnapshot = NavSnapshot()

    public init() {}

    public func process(message: AapMessage) -> Bool {
        guard message.channelUInt8 == Channel.ID_NAV else { return false }

        switch message.typeUInt16 {
        case UInt16(NavigationMsgType.instrumentClusterStart.rawValue):
            currentSnapshot = NavSnapshot(status: .active)
            onNavigationUpdate?(currentSnapshot)
            return true

        case UInt16(NavigationMsgType.instrumentClusterStop.rawValue):
            currentSnapshot = NavSnapshot(status: .inactive)
            onNavigationUpdate?(currentSnapshot)
            return true

        case UInt16(NavigationMsgType.instrumentClusterNavigationStatus.rawValue):
            do {
                var reader = ProtoReader(data: message.data)
                let statusMsg = try NavigationClusterStatus(from: &reader)
                currentSnapshot.status = statusMsg.status
                onNavigationUpdate?(currentSnapshot)
            } catch {
                print("AapNavigation: failed to parse NavigationClusterStatus: \(error)")
            }
            return true

        case UInt16(NavigationMsgType.nextTurnDetails.rawValue):
            do {
                var reader = ProtoReader(data: message.data)
                let detail = try NextTurnDetail(from: &reader)
                currentSnapshot.road = detail.road
                currentSnapshot.turnSide = detail.side
                currentSnapshot.nextTurn = detail.nextTurn
                currentSnapshot.turnIconData = detail.image
                onNavigationUpdate?(currentSnapshot)
            } catch {
                print("AapNavigation: failed to parse NextTurnDetail: \(error)")
            }
            return true

        case UInt16(NavigationMsgType.nextTurnDistanceAndTime.rawValue):
            do {
                var reader = ProtoReader(data: message.data)
                let dist = try NextTurnDistanceEvent(from: &reader)
                currentSnapshot.distanceMeters = dist.distanceMeters
                currentSnapshot.timeToTurnSeconds = dist.timeToTurnSeconds
                onNavigationUpdate?(currentSnapshot)
            } catch {
                print("AapNavigation: failed to parse NextTurnDistanceEvent: \(error)")
            }
            return true

        default:
            return false
        }
    }

    public func reset() {
        currentSnapshot = NavSnapshot()
        onNavigationUpdate?(currentSnapshot)
    }
}
