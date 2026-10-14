//
//  AudioOutputPolicy.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit AudioOutputPolicy.kt
//

import Foundation

enum AudioOutputPolicy {
    static func useAAudio(sdk: Int, stream: Int, attachHwDsp: Bool, enabled: Bool) -> Bool {
        return enabled && sdk >= 28 && stream == 3
    }
}
