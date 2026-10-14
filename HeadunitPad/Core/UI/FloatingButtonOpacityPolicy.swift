//
//  FloatingButtonOpacityPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit FloatingButtonOpacityPolicy.kt
//  Calculates the target opacity and touchability for the floating overlay button.
//

import Foundation
import CoreGraphics

public enum FloatingButtonOpacityPolicy {

    public static let defaultConnectedOpacityPercent: Int = 80
    public static let defaultDisconnectedOpacityPercent: Int = 30
    public static let idleFadeTimeoutSeconds: TimeInterval = 4.0

    /// Calculates target opacity alpha (0.0 to 1.0).
    ///
    /// - Parameters:
    ///   - isConnectionStatusMode: Whether connection status mode is enabled.
    ///   - isConnected: Whether a phone session is currently connected.
    ///   - connectedOpacityPercent: Opacity percent (10 to 100) when connected.
    ///   - disconnectedOpacityPercent: Opacity percent (0 to 100) when disconnected in status mode.
    public static func targetAlpha(
        isConnectionStatusMode: Bool,
        isConnected: Bool,
        connectedOpacityPercent: Int = defaultConnectedOpacityPercent,
        disconnectedOpacityPercent: Int = defaultDisconnectedOpacityPercent
    ) -> CGFloat {
        let configuredAlpha = CGFloat(max(10, min(100, connectedOpacityPercent))) / 100.0
        let disconnectedAlpha = CGFloat(max(0, min(100, disconnectedOpacityPercent))) / 100.0

        if isConnectionStatusMode && !isConnected {
            return disconnectedAlpha
        } else {
            return configuredAlpha
        }
    }

    /// An overlay at 0% opacity carries no user interaction so it does not intercept touches underneath.
    public static func isTouchable(targetAlpha: CGFloat) -> Bool {
        return targetAlpha > 0.05
    }

    /// Dimmed idle alpha when the button has not been interacted with for several seconds.
    public static func idleAlpha(baseAlpha: CGFloat) -> CGFloat {
        return max(0.25, baseAlpha * 0.4)
    }
}
