//
//  CallState.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit CallState.kt
//

import Foundation

enum CallState {
    static func isCallActive(audioMode: Int, appHoldsCommunicationMode: Bool) -> Bool {
        // audioMode equivalents:
        // 2: MODE_IN_CALL
        // 3: MODE_IN_COMMUNICATION
        switch audioMode {
        case 2:
            return true
        case 3:
            return !appHoldsCommunicationMode
        default:
            return false
        }
    }

    static func isCallStarting(audioMode: Int) -> Bool {
        // 1: MODE_RINGTONE
        return audioMode == 1
    }
}
