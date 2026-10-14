//
//  DecoderExceptionPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DecoderExceptionPolicy.kt
//  Differentiates transient decoder glitches from recoverable faults and fatal component failures.
//

import Foundation

public enum DecoderExceptionPolicy {

    public enum Response: Equatable {
        case continueExecution
        case countStrike
        case restartNow
    }

    public static func responseTo(
        isCodecException: Bool,
        isTransient: Bool,
        isRecoverable: Bool
    ) -> Response {
        if !isCodecException { return .countStrike }
        if isTransient { return .continueExecution }
        if isRecoverable { return .countStrike }
        return .restartNow
    }

    public static func describe(_ response: Response) -> String {
        switch response {
        case .continueExecution:
            return "the component says it was only busy"
        case .countStrike:
            return "the component can be reconfigured"
        case .restartNow:
            return "the component says it cannot recover"
        }
    }
}
