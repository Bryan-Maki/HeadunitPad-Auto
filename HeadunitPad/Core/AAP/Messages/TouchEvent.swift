//
//  TouchEvent.swift
//  HeadunitPad
//
//  1:1 port of open-headunit TouchEvent.kt
//

import Foundation

public final class AapTouchEventMessage {
    public static func make(
        timestampNs: UInt64 = UInt64(DispatchTime.now().uptimeNanoseconds / 1000),
        action: ProtoTouchEvent.PointerAction,
        actionIndex: Int,
        pointers: [(id: Int, x: Int, y: Int)]
    ) -> AapMessage {
        var pointerList: [ProtoTouchEvent.Pointer] = []
        for p in pointers {
            pointerList.append(ProtoTouchEvent.Pointer(
                x: UInt32(max(0, p.x)),
                y: UInt32(max(0, p.y)),
                pointerId: UInt32(max(0, p.id))
            ))
        }

        let touchEvent = ProtoTouchEvent(
            pointerData: pointerList,
            actionIndex: UInt32(max(0, actionIndex)),
            action: action
        )

        let inputReport = InputReport(
            timestamp: timestampNs,
            touchEvent: touchEvent
        )

        return AapMessage(
            channel: Int(Channel.ID_INP),
            type: Int(InputMsgType.event.rawValue),
            proto: inputReport
        )
    }

    public static func make(
        timestampUs: UInt64,
        action: ProtoTouchEvent.PointerAction,
        actionIndex: Int,
        pointers: [(id: Int, x: Int, y: Int)]
    ) -> AapMessage {
        return make(
            timestampNs: timestampUs,
            action: action,
            actionIndex: actionIndex,
            pointers: pointers
        )
    }
}
