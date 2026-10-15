//
//  WppHandshakeSession.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppHandshakeSession.kt
//  Pure state machine driving the Android Auto WiFi Projection Protocol (WPP) handshake.
//

import Foundation

public enum WppStage: Equatable {
    /// Nothing sent yet.
    case new
    /// VERSION_REQUEST is out; waiting for phone's version.
    case awaitVersion
    /// Waiting for head unit's own WiFi credentials to become available.
    case awaitCredentials
    /// START_REQUEST is out; waiting for phone to ask for credentials (INFO_REQUEST).
    case awaitInfoRequest
    /// Credentials delivered; phone is associating, WPS and DHCP.
    case settling
    /// Projection session landed; holding channel open, answering pings.
    case holding
    /// Handshake completed successfully.
    case done
    /// Exchange ended without a successful session.
    case failed
}

public enum WppEvent: Equatable {
    case socketReady
    case credentialsReady
    case credentialsUnavailable
    case messageReceived(type: Int, status: Int?, rawPayload: Data)
    case stageTimeout
    case tcpSessionUp
    case settleTimeout
    case networkWithdrawn
    case peerClosed
    case sessionEnded
}

public enum WppAction: Equatable {
    case sendVersionRequest
    case sendStartRequest
    case sendInfoResponse
    case sendPingResponse(Data)
    case extendSettle
    case completeSuccess
    case fail(reason: String, phoneWasSilent: Bool, joinRefused: Bool)
}

public final class WppHandshakeSession {
    public static let wppVersionMajor: Int32 = 4
    public static let wppVersionMinor: Int32 = 2

    public private(set) var stage: WppStage = .new
    public private(set) var phoneWasSilent: Bool = true
    public private(set) var credentialsKnown: Bool = false

    public static let versionTimeoutMs: Int64 = 5_000
    public static let infoRequestTimeoutMs: Int64 = 8_000
    public static let settleWindowMs: Int64 = 30_000

    public init(credentialsKnown: Bool = true) {
        self.credentialsKnown = credentialsKnown
    }

    public func start(localIp: String? = nil, aapPort: Int = 5000) -> [Data] {
        let ip = localIp ?? NetworkAddresses.stationIpv4() ?? NetworkAddresses.currentHotspotGatewayIpv4() ?? "0.0.0.0"
        let req = WppMessages.startRequest(ip: ip, port: aapPort)
        if let framed = try? WppMessages.frame(req, type: .startRequest) {
            stage = .awaitInfoRequest
            return [framed]
        }
        return []
    }

    public enum State: Equatable {
        case waitingForVersionRequest
        case waitingForSecurityOrStart
        case completed
        case failed
    }

    public typealias SendCallback = (WppMessageType, Data) -> Void
    private var sendCallback: SendCallback?
    public var currentState: State = .waitingForVersionRequest

    public convenience init(sendCallback: @escaping SendCallback) {
        self.init(credentialsKnown: true)
        self.sendCallback = sendCallback
    }

    public func onMessageReceived(type: WppMessageType, payload: Data) throws {
        switch type {
        case .versionRequest, .wifiVersionRequest:
            currentState = .waitingForSecurityOrStart
            sendCallback?(.wifiVersionResponse, Data())
        case .startRequest, .wifiStartRequest:
            currentState = .completed
            sendCallback?(.wifiStartResponse, Data())
        default:
            break
        }
    }

    public var currentStageTimeoutMs: Int64? {
        switch stage {
        case .awaitVersion:
            return Self.versionTimeoutMs
        case .awaitInfoRequest:
            return Self.infoRequestTimeoutMs
        case .settling:
            return Self.settleWindowMs
        default:
            return nil
        }
    }

    public func on(event: WppEvent) -> [WppAction] {
        var actions: [WppAction] = []

        switch event {
        case .socketReady:
            if stage == .new {
                stage = .awaitVersion
                actions.append(.sendVersionRequest)
            }

        case .credentialsReady:
            credentialsKnown = true
            if stage == .awaitCredentials {
                stage = .awaitInfoRequest
                actions.append(.sendStartRequest)
            }

        case .credentialsUnavailable:
            stage = .failed
            actions.append(.fail(reason: "Credentials unavailable", phoneWasSilent: phoneWasSilent, joinRefused: false))

        case .messageReceived(let type, let status, let payload):
            phoneWasSilent = false

            // Keepalive handling across all stages
            if type == WppMessageType.pingRequest {
                actions.append(.sendPingResponse(payload))
                return actions
            }

            switch stage {
            case .awaitVersion:
                if type == WppMessageType.versionResponse {
                    if let st = status, st != 0 {
                        stage = .failed
                        actions.append(.fail(reason: "Version rejected with status \(WppStatus.describe(st))", phoneWasSilent: false, joinRefused: false))
                    } else if credentialsKnown {
                        stage = .awaitInfoRequest
                        actions.append(.sendStartRequest)
                    } else {
                        stage = .awaitCredentials
                    }
                }

            case .awaitInfoRequest:
                if type == WppMessageType.infoRequest {
                    stage = .settling
                    actions.append(.sendInfoResponse)
                }

            case .settling:
                if type == WppMessageType.infoRequest {
                    // Phone requested credentials again
                    actions.append(.sendInfoResponse)
                } else if type == WppMessageType.connectStatus {
                    if let st = status {
                        if st == 0 {
                            actions.append(.extendSettle)
                        } else {
                            stage = .failed
                            actions.append(.fail(reason: "Connect failed: \(WppStatus.describe(st))", phoneWasSilent: false, joinRefused: true))
                        }
                    }
                } else if type == WppMessageType.startResponse {
                    if let st = status, st != 0 {
                        stage = .failed
                        actions.append(.fail(reason: "Start rejected: \(WppStatus.describe(st))", phoneWasSilent: false, joinRefused: false))
                    } else {
                        actions.append(.extendSettle)
                    }
                }

            case .holding:
                // Already in holding state, pings handled above
                break

            default:
                break
            }

        case .tcpSessionUp:
            if stage == .settling || stage == .awaitInfoRequest || stage == .holding || stage == .awaitVersion {
                stage = .holding
                actions.append(.completeSuccess)
            }

        case .stageTimeout, .settleTimeout:
            if stage == .settling || stage == .awaitVersion || stage == .awaitInfoRequest {
                let silent = phoneWasSilent
                stage = .failed
                actions.append(.fail(reason: "Stage timeout in \(stage)", phoneWasSilent: silent, joinRefused: false))
            }

        case .networkWithdrawn:
            stage = .failed
            actions.append(.fail(reason: "Network withdrawn", phoneWasSilent: phoneWasSilent, joinRefused: false))

        case .peerClosed:
            if stage == .holding {
                stage = .done
            } else if stage != .done {
                stage = .failed
                actions.append(.fail(reason: "Peer closed connection", phoneWasSilent: phoneWasSilent, joinRefused: false))
            }

        case .sessionEnded:
            stage = .done
        }

        return actions
    }
}
