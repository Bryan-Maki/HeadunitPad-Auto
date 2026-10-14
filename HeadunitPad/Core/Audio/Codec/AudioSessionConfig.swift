//
//  AudioSessionConfig.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSessionConfig.kt
//

import Foundation

/// Snapshot of audio settings for the lifetime of a projection session.
public struct AudioSessionConfig: Equatable, Sendable {
    public let enabled: Bool
    public let staticFocus: Bool
    public let separateStreams: Bool
    public let aac: Bool
    public let attachHwDspEqualizer: Bool

    public init(
        enabled: Bool = true,
        staticFocus: Bool = true,
        separateStreams: Bool = false,
        aac: Bool = true,
        attachHwDspEqualizer: Bool = false
    ) {
        self.enabled = enabled
        self.staticFocus = staticFocus
        self.separateStreams = separateStreams
        self.aac = aac
        self.attachHwDspEqualizer = attachHwDspEqualizer
    }
}
