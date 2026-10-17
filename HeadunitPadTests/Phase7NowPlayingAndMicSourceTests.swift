//
//  Phase7NowPlayingAndMicSourceTests.swift
//  HeadunitPadTests
//
//  Comprehensive test suite for Phase 7:
//  - MicrophoneSource enum & effectiveUseIpadMic deduction policy
//  - AapServiceDiscoveryResponse Motorcycle profile fallback when useMic == false
//  - PlaybackProto MediaMetaData & MediaPlaybackStatus serialization & decoding
//  - SettingsBackupManager round-trip with isAutoDpi & microphoneSource + legacy JSON compatibility
//

import XCTest
import Foundation
@testable import HeadunitPad

final class Phase7NowPlayingAndMicSourceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ProjectionSettings.resetToDefaults()
    }

    override func tearDown() {
        ProjectionSettings.resetToDefaults()
        super.tearDown()
    }

    // MARK: - 1. MicrophoneSource & Effective Routing Deduction

    func testMicrophoneSourceEnumMetadata() {
        XCTAssertEqual(MicrophoneSource.followAudioOutput.rawValue, 0)
        XCTAssertEqual(MicrophoneSource.ipad.rawValue, 1)
        XCTAssertEqual(MicrophoneSource.phone.rawValue, 2)

        XCTAssertEqual(MicrophoneSource.followAudioOutput.title, "Follow Audio Output")
        XCTAssertEqual(MicrophoneSource.ipad.title, "iPad Microphone")
        XCTAssertEqual(MicrophoneSource.phone.title, "Phone / Car BT Mic")
    }

    func testEffectiveUseIpadMicWhenFollowAudioOutput() {
        ProjectionSettings.microphoneSource = .followAudioOutput

        // If audio output target is iPad -> use iPad microphone
        ProjectionSettings.audioOutputTarget = .ipad
        XCTAssertTrue(ProjectionSettings.effectiveUseIpadMic, "Should use iPad mic when audio output is iPad")

        // If audio output target is Phone -> use Phone microphone
        ProjectionSettings.audioOutputTarget = .phone
        XCTAssertFalse(ProjectionSettings.effectiveUseIpadMic, "Should not use iPad mic when audio output is Phone")
    }

    func testEffectiveUseIpadMicWhenForcedIpad() {
        ProjectionSettings.microphoneSource = .ipad

        // Always true regardless of audio output target
        ProjectionSettings.audioOutputTarget = .ipad
        XCTAssertTrue(ProjectionSettings.effectiveUseIpadMic)

        ProjectionSettings.audioOutputTarget = .phone
        XCTAssertTrue(ProjectionSettings.effectiveUseIpadMic, "Should still use iPad mic even if audio is routed to phone")
    }

    func testEffectiveUseIpadMicWhenForcedPhone() {
        ProjectionSettings.microphoneSource = .phone

        // Always false regardless of audio output target
        ProjectionSettings.audioOutputTarget = .ipad
        XCTAssertFalse(ProjectionSettings.effectiveUseIpadMic, "Should not use iPad mic if phone mic is forced")

        ProjectionSettings.audioOutputTarget = .phone
        XCTAssertFalse(ProjectionSettings.effectiveUseIpadMic)
    }

    // MARK: - 2. AAP ServiceDiscoveryResponse with Motorcycle Profile Policy

    func testServiceDiscoveryResponseWithMicEnabled() throws {
        let message = AapServiceDiscoveryResponseMessage.make(
            useMic: true,
            vehicleId: "iPad-HeadunitPad"
        )

        var reader = ProtoReader(data: message.payload)
        let proto = try ServiceDiscoveryResponseProto(from: &reader)

        // Must announce Channel.ID_MIC (7)
        let micService = proto.services.first(where: { $0.id == UInt32(Channel.ID_MIC) })
        XCTAssertNotNil(micService, "Service discovery response must include MIC service when useMic is true")

        // Car profile: vehicleType == 1, no "-moto" suffix
        XCTAssertEqual(proto.headunitInfo?.vehicleType, 1, "Vehicle type should be Car (1)")
        XCTAssertEqual(proto.headunitInfo?.vehicleId, "iPad-HeadunitPad")
        XCTAssertEqual(proto.vehicleId, "iPad-HeadunitPad")
        XCTAssertFalse(proto.vehicleId.hasSuffix("-moto"))
    }

    func testServiceDiscoveryResponseWithMicDisabledDeclaresMotorcycle() throws {
        let message = AapServiceDiscoveryResponseMessage.make(
            useMic: false,
            vehicleId: "iPad-HeadunitPad"
        )

        var reader = ProtoReader(data: message.payload)
        let proto = try ServiceDiscoveryResponseProto(from: &reader)

        // Must NOT announce Channel.ID_MIC (7)
        let micService = proto.services.first(where: { $0.id == UInt32(Channel.ID_MIC) })
        XCTAssertNil(micService, "Service discovery response must omit MIC service when useMic is false")

        // Motorcycle profile to prevent Android Auto handshake abort: vehicleType == 3, vehicleId has "-moto" suffix
        XCTAssertEqual(proto.headunitInfo?.vehicleType, 3, "Vehicle type must be MOTORCYCLE (3) when mic is omitted")
        XCTAssertEqual(proto.headunitInfo?.vehicleId, "iPad-HeadunitPad-moto")
        XCTAssertEqual(proto.vehicleId, "iPad-HeadunitPad-moto")
        XCTAssertTrue(proto.vehicleId.hasSuffix("-moto"))
    }

    // MARK: - 3. PlaybackProto Strong-Type Serialization & Parsing

    func testMediaMetaDataSerializationAndDeserialization() throws {
        let artBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        let original = MediaMetaData(
            song: "Blinding Lights",
            artist: "The Weeknd",
            album: "After Hours",
            albumArt: artBytes,
            playlist: "Favorites",
            durationSeconds: 200,
            rating: 5
        )

        var writer = ProtoWriter()
        original.encode(to: &writer)
        let encodedData = writer.data

        XCTAssertFalse(encodedData.isEmpty)

        var reader = ProtoReader(data: encodedData)
        let decoded = try MediaMetaData(from: &reader)

        XCTAssertEqual(decoded.song, "Blinding Lights")
        XCTAssertEqual(decoded.artist, "The Weeknd")
        XCTAssertEqual(decoded.album, "After Hours")
        XCTAssertEqual(decoded.albumArt, artBytes)
        XCTAssertEqual(decoded.playlist, "Favorites")
        XCTAssertEqual(decoded.durationSeconds, 200)
        XCTAssertEqual(decoded.rating, 5)
    }

    func testMediaPlaybackStatusSerializationAndDeserialization() throws {
        let original = MediaPlaybackStatus(
            state: .playing,
            mediaSource: "Apple Music",
            playbackSeconds: 125,
            shuffle: true,
            repeatMode: true,
            repeatOne: false
        )

        var writer = ProtoWriter()
        original.encode(to: &writer)
        let encodedData = writer.data

        XCTAssertFalse(encodedData.isEmpty)

        var reader = ProtoReader(data: encodedData)
        let decoded = try MediaPlaybackStatus(from: &reader)

        XCTAssertEqual(decoded.state, .playing)
        XCTAssertEqual(decoded.mediaSource, "Apple Music")
        XCTAssertEqual(decoded.playbackSeconds, 125)
        XCTAssertEqual(decoded.shuffle, true)
        XCTAssertEqual(decoded.repeatMode, true)
        XCTAssertEqual(decoded.repeatOne, false)
    }

    // MARK: - 4. SettingsBackupManager Round-Trip & Legacy JSON Compatibility

    func testSettingsBackupManagerRoundTripWithPhase7Properties() throws {
        // Set specific non-default values
        ProjectionSettings.isAutoDpi = false
        ProjectionSettings.dpi = 220
        ProjectionSettings.microphoneSource = .phone
        ProjectionSettings.audioOutputTarget = .phone

        let json = SettingsBackupManager.exportToJson()
        XCTAssertTrue(json.contains("\"isAutoDpi\" : false"))
        XCTAssertTrue(json.contains("\"microphoneSource\" : 2"))

        // Reset to default
        ProjectionSettings.resetToDefaults()
        XCTAssertTrue(ProjectionSettings.isAutoDpi)
        XCTAssertEqual(ProjectionSettings.microphoneSource, .followAudioOutput)

        // Restore from json
        let count = try SettingsBackupManager.importFromJson(json)
        XCTAssertEqual(count, 17)
        XCTAssertFalse(ProjectionSettings.isAutoDpi)
        XCTAssertEqual(ProjectionSettings.dpi, 220)
        XCTAssertEqual(ProjectionSettings.microphoneSource, .phone)
        XCTAssertEqual(ProjectionSettings.audioOutputTarget, .phone)
        XCTAssertFalse(ProjectionSettings.effectiveUseIpadMic)
    }

    func testSettingsBackupManagerLegacyJsonCompatibilityWithoutPhase7Fields() throws {
        let legacyJson = """
        {
          "exportedAt" : "2026-10-17T00:00:00Z",
          "format" : "headunitpad-auto-settings",
          "settings" : {
            "audioCodecPreference" : 1,
            "audioOutputTarget" : 0,
            "autoReconnect" : true,
            "autoResumePlayback" : true,
            "connectionMode" : 1,
            "dpi" : 180,
            "fitMode" : 1,
            "fpsLimit" : 1,
            "gpsSource" : 0,
            "horizontalMargin" : 0,
            "nightMode" : 0,
            "orientation" : 0,
            "resolution" : 0,
            "rightHandDrive" : false,
            "showPerformanceOverlay" : false,
            "verticalMargin" : 0,
            "videoCodecPreference" : "h264"
          },
          "version" : 1
        }
        """

        ProjectionSettings.microphoneSource = .phone
        ProjectionSettings.isAutoDpi = false

        // Importing legacy JSON without isAutoDpi or microphoneSource should succeed cleanly
        let count = try SettingsBackupManager.importFromJson(legacyJson)
        XCTAssertEqual(count, 17)
        XCTAssertEqual(ProjectionSettings.dpi, 180)
        // Existing values remain if omitted in JSON
        XCTAssertEqual(ProjectionSettings.microphoneSource, .phone)
        XCTAssertFalse(ProjectionSettings.isAutoDpi)
    }
}
