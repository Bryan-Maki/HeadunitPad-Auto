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
        // Protocol-correct (matching open-headunit UpdateUiConfigRequest.kt):
        // UiConfig MUST ONLY set Field 1 (margins). Never set Field 4 (ui_theme),
        // otherwise Gearhead aborts the projection session during startup.
        let uiConfig = UiConfig(margins: insets, uiTheme: nil)
        let requestProto = UpdateUiConfigRequestProto(uiConfig: uiConfig)

        return AapMessage(
            channel: Int(Channel.ID_VID),
            type: Int(MediaMsgType.mediaMessageUpdateUiConfigRequest.rawValue),
            proto: requestProto
        )
    }
}
