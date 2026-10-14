//
//  PlaybackProto.swift
//  HeadunitPad
//
//  Android Auto playback.proto pure Swift models.
//

import Foundation

public enum PlaybackMsgType: Int32, CaseIterable {
    case msgPlaybackMetadata = 0x8001
    case msgPlaybackStartResponse = 0x8002
    case msgPlaybackMetadataStart = 0x8003
}

public struct MediaPlaybackStatus: ProtoCodable, Equatable {
    public enum State: Int32, CaseIterable {
        case stopped = 1
        case playing = 2
        case paused = 3
    }

    public var state: State?
    public var mediaSource: String?
    public var playbackSeconds: UInt32?
    public var shuffle: Bool?
    public var repeatMode: Bool?
    public var repeatOne: Bool?

    public init(
        state: State? = nil,
        mediaSource: String? = nil,
        playbackSeconds: UInt32? = nil,
        shuffle: Bool? = nil,
        repeatMode: Bool? = nil,
        repeatOne: Bool? = nil
    ) {
        self.state = state
        self.mediaSource = mediaSource
        self.playbackSeconds = playbackSeconds
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.repeatOne = repeatOne
    }

    public func encode(to writer: inout ProtoWriter) {
        if let state = state { writer.writeEnum(fieldNumber: 1, value: state.rawValue) }
        if let mediaSource = mediaSource { writer.writeString(fieldNumber: 2, value: mediaSource) }
        if let playbackSeconds = playbackSeconds { writer.writeUInt32(fieldNumber: 3, value: playbackSeconds) }
        if let shuffle = shuffle { writer.writeBool(fieldNumber: 4, value: shuffle) }
        if let repeatMode = repeatMode { writer.writeBool(fieldNumber: 5, value: repeatMode) }
        if let repeatOne = repeatOne { writer.writeBool(fieldNumber: 6, value: repeatOne) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1:
                let raw = try reader.readInt32()
                self.state = State(rawValue: raw)
            case 2: self.mediaSource = try reader.readString()
            case 3: self.playbackSeconds = try reader.readUInt32()
            case 4: self.shuffle = try reader.readBool()
            case 5: self.repeatMode = try reader.readBool()
            case 6: self.repeatOne = try reader.readBool()
            default: try reader.skipField(wireType: wireType)
            }
        }
    }
}

public struct MediaMetaData: ProtoCodable, Equatable {
    public var song: String?
    public var artist: String?
    public var album: String?
    public var albumArt: Data?
    public var playlist: String?
    public var durationSeconds: UInt32?
    public var rating: Int32?

    public init(
        song: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArt: Data? = nil,
        playlist: String? = nil,
        durationSeconds: UInt32? = nil,
        rating: Int32? = nil
    ) {
        self.song = song
        self.artist = artist
        self.album = album
        self.albumArt = albumArt
        self.playlist = playlist
        self.durationSeconds = durationSeconds
        self.rating = rating
    }

    public func encode(to writer: inout ProtoWriter) {
        if let song = song { writer.writeString(fieldNumber: 1, value: song) }
        if let artist = artist { writer.writeString(fieldNumber: 2, value: artist) }
        if let album = album { writer.writeString(fieldNumber: 3, value: album) }
        if let albumArt = albumArt { writer.writeBytes(fieldNumber: 4, value: albumArt) }
        if let playlist = playlist { writer.writeString(fieldNumber: 5, value: playlist) }
        if let durationSeconds = durationSeconds { writer.writeUInt32(fieldNumber: 6, value: durationSeconds) }
        if let rating = rating { writer.writeInt32(fieldNumber: 7, value: rating) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: self.song = try reader.readString()
            case 2: self.artist = try reader.readString()
            case 3: self.album = try reader.readString()
            case 4: self.albumArt = try reader.readBytes()
            case 5: self.playlist = try reader.readString()
            case 6: self.durationSeconds = try reader.readUInt32()
            case 7: self.rating = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
    }
}
