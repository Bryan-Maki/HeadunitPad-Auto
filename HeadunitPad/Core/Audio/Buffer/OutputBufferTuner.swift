//
//  OutputBufferTuner.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit OutputBufferTuner.kt
//

import Foundation

protocol PcmBufferTunable: AnyObject {
    var bufferFrames: Int { get }
    func setBufferFrames(_ frames: Int)
}

final class OutputBufferTuner {
    private var requestedFrames = -1
    private var appliedFrames = -1

    func update(output: PcmBufferTunable, targetFrames: Int, force: Bool = false) -> Bool {
        if !force && targetFrames == requestedFrames && output.bufferFrames == appliedFrames {
            return false
        }
        output.setBufferFrames(targetFrames)
        requestedFrames = targetFrames
        appliedFrames = output.bufferFrames
        return true
    }
}
