//
//  ServiceDiscoveryResponse.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ServiceDiscoveryResponse.kt
//

import Foundation

public final class AapServiceDiscoveryResponseMessage {
    public static func make(
        screenConfig: HeadUnitScreenConfig = HeadUnitScreenConfig.shared,
        fpsLimit: Int = 60,
        rightHandDrive: Bool = false,
        useGps: Bool = true,
        useMic: Bool = true,
        requestedDpi: Int = 160,
        vehicleMake: String = "Apple",
        vehicleModel: String = "iPad",
        vehicleYear: String = "2024",
        vehicleId: String = "iPad-HeadunitPad",
        headUnitMake: String = "HeadunitPad",
        headUnitModel: String = "HeadunitPad-Auto"
    ) -> AapMessage {
        var services: [ControlService] = []

        // 1. Sensors Service (Channel 1)
        var sensorTypes: [ControlService.SensorSourceService.Sensor] = [
            ControlService.SensorSourceService.Sensor(type: .drivingStatus),
            ControlService.SensorSourceService.Sensor(type: .night)
        ]
        if useGps {
            sensorTypes.append(ControlService.SensorSourceService.Sensor(type: .location))
        }
        let sensorSource = ControlService.SensorSourceService(sensors: sensorTypes)
        services.append(ControlService(id: UInt32(Channel.ID_SEN), sensorSourceService: sensorSource))

        // 2. Video Service (Channel 2)
        let negotiatedRes = screenConfig.negotiatedResolutionType
        let phoneWidthMargin = screenConfig.getWidthMargin()
        let phoneHeightMargin = screenConfig.getHeightMargin()
        let densityDecision = screenConfig.densityDecision(requestedDpi: requestedDpi)
        let par = screenConfig.getPixelAspectRatioE4()

        screenConfig.recordAnnouncedMargins(widthMargin: phoneWidthMargin, heightMargin: phoneHeightMargin)
        screenConfig.recordAnnouncedCanvas()

        let frameRateType: ControlService.MediaSinkService.VideoConfiguration.VideoFrameRateType =
            (fpsLimit == 30) ? ._30 : ._60

        // Use CodecTypeSelectionPolicy & user preference
        let userPref = ProjectionSettings.videoCodecPreference
        let allowsHevc = (userPref != .h264)
        let prefersHevc = (userPref == .hevc)
        let isHighRes = (negotiatedRes == ._2560x1440 || negotiatedRes == ._3840x2160)
        let effectiveCodec: MediaCodecType = (prefersHevc || (isHighRes && allowsHevc))
            ? .mediaCodecVideoH265
            : .mediaCodecVideoH264Bp

        let videoConfig = ControlService.MediaSinkService.VideoConfiguration(
            codecResolution: negotiatedRes,
            frameRate: frameRateType,
            marginWidth: UInt32(phoneWidthMargin),
            marginHeight: UInt32(phoneHeightMargin),
            density: UInt32(densityDecision.announced),
            pixelAspectRatioE4: UInt32(par),
            videoCodecType: effectiveCodec
        )

        let mediaSink = ControlService.MediaSinkService(
            availableType: effectiveCodec,
            audioType: .none,
            videoConfigs: [videoConfig],
            availableWhileInCall: true
        )
        services.append(ControlService(id: UInt32(Channel.ID_VID), mediaSinkService: mediaSink))

        // 3. Input Service (Channel 3)
        let touchConfig = ControlService.InputSourceService.TouchConfig(
            width: UInt32(screenConfig.getNegotiatedWidth()),
            height: UInt32(screenConfig.getNegotiatedHeight())
        )
        let inputService = ControlService.InputSourceService(
            keycodesSupported: [1, 2, 3, 4, 19, 20, 21, 22, 66, 84, 85, 87, 88],
            touchscreen: touchConfig,
            touchpad: touchConfig
        )
        services.append(ControlService(id: UInt32(Channel.ID_INP), inputSourceService: inputService))

        // 4. Audio Services (Channels 4, 5, 6)
        // Audio2 (System)
        let audio2Sink = ControlService.MediaSinkService(
            availableType: .mediaCodecAudioPcm,
            audioType: .system,
            audioConfigs: [AudioConfigs.get(channel: Channel.ID_AU2)]
        )
        services.append(ControlService(id: UInt32(Channel.ID_AU2), mediaSinkService: audio2Sink))

        // Audio1 (Guidance)
        let audio1Sink = ControlService.MediaSinkService(
            availableType: .mediaCodecAudioPcm,
            audioType: .speech,
            audioConfigs: [AudioConfigs.get(channel: Channel.ID_AU1)]
        )
        services.append(ControlService(id: UInt32(Channel.ID_AU1), mediaSinkService: audio1Sink))

        // Audio0 (Media)
        let audio0Sink = ControlService.MediaSinkService(
            availableType: .mediaCodecAudioPcm,
            audioType: .media,
            audioConfigs: [AudioConfigs.get(channel: Channel.ID_AUD)]
        )
        services.append(ControlService(id: UInt32(Channel.ID_AUD), mediaSinkService: audio0Sink))

        // 5. Microphone Service (Channel 7)
        if useMic {
            let micConfig = AudioConfiguration(
                sampleRate: UInt32(MicCaptureFormat.SAMPLE_RATE_HZ),
                numberOfBits: UInt32(MicCaptureFormat.BITS),
                numberOfChannels: UInt32(MicCaptureFormat.CHANNELS)
            )
            let micSource = ControlService.MediaSourceService(
                type: .mediaCodecAudioPcm,
                audioConfig: micConfig,
                availableWhileInCall: true
            )
            services.append(ControlService(id: UInt32(Channel.ID_MIC), mediaSourceService: micSource))
        }

        // 6. Media Playback Service (Channel 9)
        services.append(ControlService(
            id: UInt32(Channel.ID_MPB),
            mediaPlaybackService: ControlService.MediaPlaybackStatusService()
        ))

        // 7. Navigation Status Service (Channel 10)
        let navService = ControlService.NavigationStatusService(
            minimumIntervalMs: 1000,
            type: .imageCodesOnly
        )
        services.append(ControlService(id: UInt32(Channel.ID_NAV), navigationStatusService: navService))

        // 8. HeadUnitInfo
        let huInfo = HeadUnitInfo(
            make: vehicleMake,
            model: vehicleModel,
            year: vehicleYear,
            vehicleId: vehicleId,
            headUnitMake: headUnitMake,
            headUnitModel: headUnitModel,
            headUnitSoftwareBuild: "1",
            headUnitSoftwareVersion: "0.1.0",
            vehicleType: 1 // Car
        )

        let response = ServiceDiscoveryResponseProto(
            services: services,
            make: vehicleMake,
            model: vehicleModel,
            year: vehicleYear,
            vehicleId: vehicleId,
            driverPosition: rightHandDrive ? .right : .left,
            headUnitMake: headUnitMake,
            headUnitModel: headUnitModel,
            headUnitSoftwareBuild: "1",
            headUnitSoftwareVersion: "0.1.0",
            canPlayNativeMediaDuringVr: false,
            displayName: "HeadunitPad-Auto",
            headunitInfo: huInfo
        )

        return AapMessage(
            channel: Int(Channel.ID_CTR),
            type: Int(ControlMsgType.messageServiceDiscoveryResponse.rawValue),
            proto: response
        )
    }
}
