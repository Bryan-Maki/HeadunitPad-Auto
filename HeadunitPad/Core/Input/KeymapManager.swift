//
//  KeymapManager.swift
//  HeadunitPad
//
//  1:1 port of open-headunit Keymap management & CommManager key dispatch.
//  Routes hardware key commands (Bluetooth steering wheel buttons, keyboard, controllers)
//  to Android Auto with debouncing and configurable key mappings.
//

import Foundation
import UIKit

public final class KeymapManager {
    public static let shared = KeymapManager()

    private let defaults = UserDefaults.standard
    private let keymapStorageKey = "headunitpad-custom-keymap"

    public var onSendKey: ((_ aapKeyCode: Int, _ isPress: Bool) -> Void)?
    public var onNightModeToggle: (() -> Void)?

    private var keyStates: [Int: KeyDebouncePolicy.KeyState] = [:]
    private var customKeymap: [String: Int] = [:]

    public init() {
        loadKeymap()
    }

    public func loadKeymap() {
        if let stored = defaults.dictionary(forKey: keymapStorageKey) as? [String: Int] {
            customKeymap = stored
        } else {
            customKeymap = defaultKeymap()
        }
    }

    public func saveKeymap() {
        defaults.set(customKeymap, forKey: keymapStorageKey)
    }

    public func setMapping(physicalKey: String, aapKeyCode: Int) {
        customKeymap[physicalKey] = aapKeyCode
        saveKeymap()
    }

    public func removeMapping(physicalKey: String) {
        customKeymap.removeValue(forKey: physicalKey)
        saveKeymap()
    }

    public func resetToDefaults() {
        customKeymap = defaultKeymap()
        saveKeymap()
    }

    private func defaultKeymap() -> [String: Int] {
        return [
            UIKeyCommand.inputUpArrow: KeyCode.keyDpadUp,
            UIKeyCommand.inputDownArrow: KeyCode.keyDpadDown,
            UIKeyCommand.inputLeftArrow: KeyCode.keyDpadLeft,
            UIKeyCommand.inputRightArrow: KeyCode.keyDpadRight,
            "\r": KeyCode.keyDpadCenter,
            " ": KeyCode.keyMediaPlayPause,
            UIKeyCommand.inputEscape: KeyCode.keyBack,
            "\u{8}": KeyCode.keyDel, // Backspace
            "\t": KeyCode.keyTab
        ]
    }

    /// Resolves an incoming physical key identifier to an Android Auto KeyCode.
    public func resolveAapKeyCode(for input: String) -> Int? {
        return customKeymap[input]
    }

    /// Handles a key event with debouncing and delivers it to Android Auto.
    public func handleKeyEvent(
        aapKeyCode: Int,
        isPress: Bool,
        downTimeMs: Int64? = nil,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        if aapKeyCode == KeyCode.keyNightMode {
            if isPress {
                onNightModeToggle?()
            }
            return
        }

        let isMedia = KeyCode.isMediaKey(aapKeyCode)
        let state = keyStates[aapKeyCode] ?? KeyDebouncePolicy.KeyState()

        let decision = KeyDebouncePolicy.decide(
            state: state,
            isPress: isPress,
            downTime: downTimeMs,
            isMediaKey: isMedia,
            now: nowMs
        )

        keyStates[aapKeyCode] = decision.state

        if decision.releaseFirst {
            onSendKey?(aapKeyCode, false)
        }

        if decision.forward {
            onSendKey?(aapKeyCode, isPress)
        }
    }
}
