//
//  AapReadRecoveryPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit AapReadRecoveryPolicy.kt
//

import Foundation

/// Decides, for each way a read can come up short, whether the byte stream can still be framed.
public enum AapReadRecoveryPolicy {

    public enum Outcome: Sendable, Equatable {
        /// Alignment is intact and nothing was consumed that we cannot account for. Keep reading.
        case `continue`

        /// The peer closed the stream. Ordinary end of session.
        case disconnectEof

        /// Nothing arrived within the read timeout. Alignment is intact but connection is dead.
        case disconnectIdle

        /// Bytes were consumed and we cannot say how many, so framing alignment is lost.
        case disconnectDesync
    }

    public static let endOfStream: Int = -1
    public static let nothingRead: Int = 0

    /// The fixed-size message header read outcome evaluation.
    public static func afterHeaderRead(bytesRead: Int, expected: Int, isSocketTransport: Bool) -> Outcome {
        if bytesRead == expected {
            return .continue
        } else if bytesRead == endOfStream {
            return .disconnectEof
        } else if bytesRead == nothingRead {
            return isSocketTransport ? .disconnectIdle : .continue
        } else {
            return .disconnectDesync
        }
    }

    /// The 4-byte total accompanying a first fragment.
    public static func afterFragmentTotalRead(bytesRead: Int, expected: Int) -> Outcome {
        if bytesRead == expected {
            return .continue
        } else if bytesRead == endOfStream {
            return .disconnectEof
        } else {
            return .disconnectDesync
        }
    }

    /// The length the header declared, before any of the body has been read.
    public static func afterDeclaredLength(declaredLength: Int, bufferCapacity: Int) -> Outcome {
        if declaredLength >= 0 && declaredLength <= bufferCapacity {
            return .continue
        } else {
            return .disconnectDesync
        }
    }

    /// The message body read outcome evaluation.
    public static func afterBodyRead(bytesRead: Int, expected: Int) -> Outcome {
        if bytesRead == expected {
            return .continue
        } else if bytesRead == endOfStream {
            return .disconnectEof
        } else {
            return .disconnectDesync
        }
    }
}
