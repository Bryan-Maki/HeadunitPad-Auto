//
//  UpdateUiConfigRequest.swift
//  HeadunitPad
//
//  1:1 port of open-headunit UpdateUiConfigRequest.kt
//

import Foundation

public final class UpdateUiConfigRequest {
    public static func make(left: Int, top: Int, right: Int, bottom: Int, uiTheme: Int32? = nil) -> AapMessage {
        let insets = MediaInsets(
            top: Int32(top),
            bottom: Int32(bottom),
            left: Int32(left),
            right: Int32(right)
        )
        let themeVal: Int32? = uiTheme ?? {
            let isNight = ProjectionSettings.effectiveIsNightMode()
            switch ProjectionSettings.nightMode {
            case .day: return 1
            case .night: return 2
            case .auto, .system: return isNight ? 2 : 1
            }
        }()
        let uiConfig = UiConfig(margins: insets, uiTheme: themeVal)
        let requestProto = UpdateUiConfigRequestProto(uiConfig: uiConfig)

        return AapMessage(
            channel: Int(Channel.ID_VID),
            type: Int(MediaMsgType.mediaMessageUpdateUiConfigRequest.rawValue),
            proto: requestProto
        )
    }
}
