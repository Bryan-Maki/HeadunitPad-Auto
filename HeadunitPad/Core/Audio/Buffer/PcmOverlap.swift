//
//  PcmOverlap.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PcmOverlap.kt
//

import Foundation

/// Chooses a forward splice within the recovery policy's existing consumption budget.
public final class PcmOverlap {
    public private(set) var matched = false
    public private(set) var protectAttack = false

    public init() {}

    public func shift(ring: [Int16], head: Int, channels: Int, overlapFrames: Int, maximum: Int) -> Int {
        matched = false
        protectAttack = false
        if maximum <= 0 { return 0 }

        var best = 1
        var bestError = Double.infinity
        var attack = false

        for shift in stride(from: maximum, through: 1, by: -1) {
            var worstChannel = 0.0

            for ch in 0..<channels {
                var difference: Int64 = 0
                var energy: Int64 = 0
                var originalEnergy: Int64 = 0
                var advancedEnergy: Int64 = 0
                var originalPeak: Int64 = 0
                var advancedPeak: Int64 = 0

                var originalIndex = head + ch
                var advancedIndex = head + shift * channels + ch
                if advancedIndex >= ring.count { advancedIndex -= ring.count }

                for _ in 0..<overlapFrames {
                    let a = Int64(ring[originalIndex])
                    let b = Int64(ring[advancedIndex])
                    difference += (a - b) * (a - b)
                    let aa = a * a
                    let bb = b * b
                    energy += aa + bb

                    if shift == maximum {
                        originalEnergy += aa
                        advancedEnergy += bb
                        originalPeak = max(originalPeak, aa)
                        advancedPeak = max(advancedPeak, bb)
                    }

                    originalIndex += channels
                    advancedIndex += channels
                    if originalIndex >= ring.count { originalIndex -= ring.count }
                    if advancedIndex >= ring.count { advancedIndex -= ring.count }
                }

                let error = (energy == 0) ? 0.0 : Double(difference) / Double(energy)
                worstChannel = max(worstChannel, error)

                if shift == maximum && (originalPeak * Int64(overlapFrames) > 64 * originalEnergy ||
                                        advancedPeak * Int64(overlapFrames) > 64 * advancedEnergy) {
                    attack = true
                }
            }

            if worstChannel <= 0.05 {
                matched = true
                return shift
            }
            if worstChannel < bestError {
                bestError = worstChannel
                best = shift
            }
        }

        protectAttack = attack && bestError > 0.5
        return best
    }
}
