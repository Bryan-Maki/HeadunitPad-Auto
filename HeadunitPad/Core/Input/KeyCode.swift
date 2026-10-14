//
//  KeyCode.swift
//  HeadunitPad
//
//  1:1 port of open-headunit KeyCode.kt
//  Standard Android Auto key codes (based on Android KeyEvent numbers) and conversions.
//

import Foundation

public enum KeyCode {
    public static let keyUnknown = 0
    public static let keySoftLeft = 1
    public static let keySoftRight = 2
    public static let keyHome = 3
    public static let keyBack = 4
    public static let keyCall = 5
    public static let keyEndCall = 6

    public static let key0 = 7
    public static let key1 = 8
    public static let key2 = 9
    public static let key3 = 10
    public static let key4 = 11
    public static let key5 = 12
    public static let key6 = 13
    public static let key7 = 14
    public static let key8 = 15
    public static let key9 = 16
    public static let keyStar = 17
    public static let keyPound = 18

    public static let keyDpadUp = 19
    public static let keyDpadDown = 20
    public static let keyDpadLeft = 21
    public static let keyDpadRight = 22
    public static let keyDpadCenter = 23
    public static let keyVolumeUp = 24
    public static let keyVolumeDown = 25

    public static let keyTab = 61
    public static let keySpace = 62
    public static let keyEnter = 66
    public static let keyDel = 67

    public static let keyMediaPlayPause = 85
    public static let keyMediaStop = 86
    public static let keyMediaNext = 87
    public static let keyMediaPrevious = 88
    public static let keyMediaPlay = 126
    public static let keyMediaPause = 127

    public static let keySearch = 84
    public static let keyMusic = 209
    public static let keyEscape = 111

    public static let keyScrollWheel = 65536
    public static let keyNightMode = 65539

    public static let supported: Set<Int> = [
        keySoftLeft, keySoftRight, keyHome, keyBack, keyCall, keyEndCall,
        key0, key1, key2, key3, key4, key5, key6, key7, key8, key9, keyStar, keyPound,
        keyDpadUp, keyDpadDown, keyDpadLeft, keyDpadRight, keyDpadCenter,
        keyVolumeUp, keyVolumeDown, keyTab, keySpace, keyEnter, keyDel,
        keyMediaPlayPause, keyMediaStop, keyMediaNext, keyMediaPrevious,
        keyMediaPlay, keyMediaPause, keySearch, keyMusic, keyEscape,
        keyScrollWheel, keyNightMode
    ]

    public static func isMediaKey(_ code: Int) -> Bool {
        switch code {
        case keyMediaPlay, keyMediaPause, keyMediaPlayPause, keyMediaNext, keyMediaPrevious, keyMediaStop:
            return true
        default:
            return false
        }
    }

    public static func convert(_ code: Int) -> Int {
        if supported.contains(code) {
            return code
        }
        return keyUnknown
    }
}
