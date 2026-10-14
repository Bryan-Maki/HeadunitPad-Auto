//
//  MicrophonePolicy.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit MicrophonePolicy.kt
//

import Foundation

enum MicrophonePolicy {
    enum Decline: Equatable {
        case none
        case userSetting
        case noMicrophone
    }

    static func declineReason(headUnitMicEnabled: Bool, recorderAvailable: Bool) -> Decline {
        if !headUnitMicEnabled {
            return .userSetting
        }
        if !recorderAvailable {
            return .noMicrophone
        }
        return .none
    }

    static func shouldCapture(headUnitMicEnabled: Bool, recorderAvailable: Bool) -> Bool {
        return declineReason(headUnitMicEnabled: headUnitMicEnabled, recorderAvailable: recorderAvailable) == .none
    }
}
