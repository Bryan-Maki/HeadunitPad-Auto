//
//  MsgType.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MsgType.kt
//

import Foundation

public enum MsgType {
    public static let SIZE = 2

    public static func isControl(_ type: Int) -> Bool {
        return type >= 1 && type <= 26
    }

    public static func name(_ type: Int, channel: UInt8) -> String {
        switch type {
        case Int(ControlMsgType.messageVersionRequest.rawValue): return "Version Request"
        case Int(ControlMsgType.messageVersionResponse.rawValue): return "Version Response"
        case Int(ControlMsgType.messageEncapsulatedSsl.rawValue): return "SSL Handshake Data"
        case Int(ControlMsgType.messageAuthComplete.rawValue): return "SSL Authentication Complete Notification"
        case Int(ControlMsgType.messageServiceDiscoveryRequest.rawValue): return "Service Discovery Request"
        case Int(ControlMsgType.messageServiceDiscoveryResponse.rawValue): return "Service Discovery Response"
        case Int(ControlMsgType.messageChannelOpenRequest.rawValue): return "Channel Open Request"
        case Int(ControlMsgType.messageChannelOpenResponse.rawValue): return "Channel Open Response"
        case Int(ControlMsgType.messageChannelCloseNotification.rawValue): return "Channel Close Notification"
        case Int(ControlMsgType.messagePingRequest.rawValue): return "Ping Request"
        case Int(ControlMsgType.messagePingResponse.rawValue): return "Ping Response"
        case Int(ControlMsgType.messageNavFocusRequest.rawValue): return "Navigation Focus Request"
        case Int(ControlMsgType.messageNavFocusNotification.rawValue): return "Navigation Focus Notification"
        case Int(ControlMsgType.messageByebyeRequest.rawValue): return "Byebye Request"
        case Int(ControlMsgType.messageByebyeResponse.rawValue): return "Byebye Response"
        case Int(ControlMsgType.messageVoiceSessionNotification.rawValue): return "Voice Session Notification"
        case Int(ControlMsgType.messageAudioFocusRequest.rawValue): return "Audio Focus Request"
        case Int(ControlMsgType.messageAudioFocusNotification.rawValue): return "Audio Focus Notification"
        case Int(ControlMsgType.messageCarConnectedDevicesRequest.rawValue): return "Car Connected Devices Request"
        case Int(ControlMsgType.messageCarConnectedDevicesResponse.rawValue): return "Car Connected Devices Response"
        case Int(ControlMsgType.messageUserSwitchRequest.rawValue): return "User Switch Request"
        case Int(ControlMsgType.messageBatteryStatusNotification.rawValue): return "Battery Status Notification"
        case Int(ControlMsgType.messageCallAvailabilityStatus.rawValue): return "Call Availability Status"
        case Int(ControlMsgType.messageUserSwitchResponse.rawValue): return "User Switch Response"
        case Int(ControlMsgType.messageServiceDiscoveryUpdate.rawValue): return "Service Discovery Update"

        case Int(MediaMsgType.mediaMessageData.rawValue): return "Media Data"
        case Int(MediaMsgType.mediaMessageCodecConfig.rawValue): return "Codec Config"
        case Int(MediaMsgType.mediaMessageSetup.rawValue): return "Media Setup Request"
        case Int(MediaMsgType.mediaMessageStart.rawValue):
            switch channel {
            case Channel.ID_SEN: return "Sensor Start Request"
            case Channel.ID_INP: return "Input Event"
            case Channel.ID_MPB: return "Media Playback Status"
            default: return "Media Start Request"
            }
        case Int(MediaMsgType.mediaMessageStop.rawValue):
            switch channel {
            case Channel.ID_SEN: return "Sensor Start Response"
            case Channel.ID_INP: return "Input Binding Request"
            case Channel.ID_MPB: return "Media Playback Status"
            default: return "Media Stop Request"
            }
        case Int(MediaMsgType.mediaMessageConfig.rawValue):
            switch channel {
            case Channel.ID_SEN: return "Sensor Event"
            case Channel.ID_INP: return "Input Binding Response"
            case Channel.ID_MPB: return "Media Playback Status"
            default: return "Media Config Response"
            }
        case Int(MediaMsgType.mediaMessageAck.rawValue): return "Codec/Media Data Ack"
        case Int(MediaMsgType.mediaMessageMicrophoneRequest.rawValue): return "Mic Start/Stop Request"
        case Int(MediaMsgType.mediaMessageMicrophoneResponse.rawValue): return "Mic Response"
        case Int(MediaMsgType.mediaMessageVideoFocusRequest.rawValue): return "Video Focus Request"
        case Int(MediaMsgType.mediaMessageVideoFocusNotification.rawValue): return "Video Focus Notification"
        case Int(MediaMsgType.mediaMessageUpdateUiConfigRequest.rawValue): return "Update UI Config Request"
        case Int(MediaMsgType.mediaMessageUpdateUiConfigReply.rawValue): return "Update UI Config Reply"
        case Int(MediaMsgType.mediaMessageAudioUnderflowNotification.rawValue): return "Audio Underflow Notification"

        case Int(ControlMsgType.messageUnexpectedMessage.rawValue): return "Unexpected Message"
        case Int(ControlMsgType.messageFramingError.rawValue): return "Framing Error Notification"
        default: return "Unknown (\(type))"
        }
    }
}
