//
//  VideoBackpressurePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoBackpressurePolicy.kt
//  Separates "the decoder could not keep up" from link or reassembly drops.
//

import Foundation

public enum VideoBackpressurePolicy {

    public static let waitPercent: Int64 = 10
    public static let windowsBeforeReport: Int = 2

    public static func isBackpressureWindow(windowMs: Int64, inputWaitMs: Int64, dropped: Int64) -> Bool {
        if dropped <= 0 || windowMs <= 0 || inputWaitMs <= 0 { return false }
        return inputWaitMs * 100 >= windowMs * waitPercent
    }

    public static func shouldReport(backpressureWindows: Int, alreadyReported: Bool) -> Bool {
        return !alreadyReported && backpressureWindows >= windowsBeforeReport
    }
}
