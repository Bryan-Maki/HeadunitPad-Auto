//
//  AapMediaPlayback.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AapMediaPlayback.kt
//  Processes playback status and track metadata (title, artist, album, album art) from Android Auto.
//

import Foundation
import UIKit

public final class AapMediaPlayback {
    public static let shared = AapMediaPlayback()

    public static let msgMediaPlaybackStatus: UInt16 = 32769
    public static let msgMediaPlaybackInput: UInt16 = 32770
    public static let msgMediaPlaybackMetadata: UInt16 = 32771

    public var onMediaMetadata: ((MediaMetaData) -> Void)?
    public var onPlaybackStatus: ((MediaPlaybackStatus) -> Void)?

    public init() {}

    public func process(message: AapMessage) -> Bool {
        guard message.channelUInt8 == Channel.ID_MED else { return false }

        switch message.typeUInt16 {
        case AapMediaPlayback.msgMediaPlaybackMetadata:
            do {
                var reader = ProtoReader(data: message.data)
                let meta = try MediaMetaData(from: &reader)
                onMediaMetadata?(meta)

                // Update NowPlayingCoordinator
                var artworkImage: UIImage? = nil
                if let artData = meta.albumArt, !artData.isEmpty {
                    artworkImage = UIImage(data: artData)
                }

                NowPlayingCoordinator.shared.updateMetadata(
                    NowPlayingMetadata(
                        title: meta.song ?? "Android Auto",
                        artist: meta.artist ?? "Unknown Artist",
                        album: meta.album ?? "Projection",
                        durationSeconds: meta.durationSeconds != nil ? Double(meta.durationSeconds!) : nil,
                        artworkImage: artworkImage
                    )
                )
            } catch {
                print("AapMediaPlayback: Failed to parse MediaMetaData: \(error)")
            }
            return true

        case AapMediaPlayback.msgMediaPlaybackStatus:
            do {
                var reader = ProtoReader(data: message.data)
                let status = try MediaPlaybackStatus(from: &reader)
                onPlaybackStatus?(status)

                let isPlaying = status.state == .playing
                NowPlayingCoordinator.shared.updatePlaybackState(
                    NowPlayingPlaybackState(
                        isPlaying: isPlaying,
                        elapsedSeconds: status.playbackSeconds != nil ? Double(status.playbackSeconds!) : 0
                    )
                )
            } catch {
                print("AapMediaPlayback: Failed to parse MediaPlaybackStatus: \(error)")
            }
            return true

        default:
            return false
        }
    }
}
