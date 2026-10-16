//
//  H264VideoRendererView.swift
//  HeadunitPad
//
//  VideoToolbox hardware-accelerated video renderer supporting both
//  H.264 (AVC) and H.265 (HEVC), with dynamic parameter-set tracking,
//  wireless packet-loss concealment, keyframe repair tracking, and margin cropping.
//

import UIKit
import AVFoundation
import CoreMedia
import VideoToolbox

public typealias VideoRendererView = H264VideoRendererView

public class H264VideoRendererView: UIView {

    public struct RendererDiagnostics {
        public var inputFrames = 0
        public var parsedFrames = 0
        public var spsNALs = 0
        public var ppsNALs = 0
        public var vpsNALs = 0
        public var idrFrames = 0
        public var formatDescriptions = 0
        public var formatFailures = 0
        public var missingConfigDrops = 0
        public var awaitingIDRDrops = 0
        public var sampleBuffers = 0
        public var sampleFailures = 0
        public var enqueuedSamples = 0
        public var notReadyDrops = 0
        public var layerFailures = 0
        public var queueDrops = 0
        public var lastNALTypes: [Int] = []
        public var activeCodec: String = "Unknown"
        public var concealedFrames = 0
        public var latencyReport: String = "None"
    }

    public var onFrameDisplayed: (() -> Void)?
    public var onKeyframeRequested: (() -> Void)?
    public var onCorruptionDetected: ((String) -> Void)?
    public var onVideoSizeResolved: ((CGSize) -> Void)?

    public var codecWidth: Int = 1920 {
        didSet { if codecWidth != oldValue { updateGeometry() } }
    }
    public var codecHeight: Int = 1080 {
        didSet { if codecHeight != oldValue { updateGeometry() } }
    }
    public var widthMargin: Int = 0 {
        didSet { if widthMargin != oldValue { updateGeometry() } }
    }
    public var heightMargin: Int = 0 {
        didSet { if heightMargin != oldValue { updateGeometry() } }
    }
    public var fitMode: VideoFitMode = .fillMargin {
        didSet { if fitMode != oldValue { updateGeometry() } }
    }

    private var lastNotifiedVideoSize: CGSize = .zero

    public let displayLayer = AVSampleBufferDisplayLayer()

    public private(set) var pinnedCodec: VideoCodecType?

    public struct FrameReleasePacer {
        public var nextScheduledPtsSeconds: Double = 0

        public init(nextScheduledPtsSeconds: Double = 0) {
            self.nextScheduledPtsSeconds = nextScheduledPtsSeconds
        }

        public mutating func nextPts(nowSeconds: Double, frameInterval: Double = 1.0 / 60.0) -> Double {
            var targetSeconds = max(nowSeconds, nextScheduledPtsSeconds)
            if targetSeconds - nowSeconds > frameInterval * 2.5 {
                targetSeconds = nowSeconds
            }
            nextScheduledPtsSeconds = targetSeconds + frameInterval
            return targetSeconds
        }

        public mutating func reset() {
            nextScheduledPtsSeconds = 0
        }
    }

    private var formatDescription: CMVideoFormatDescription?
    private var vps: Data?
    private var sps: Data?
    private var pps: Data?
    private var frameIndex: Int64 = 0
    public private(set) var framePacer = FrameReleasePacer()
    public var nextScheduledPtsSeconds: Double {
        return framePacer.nextScheduledPtsSeconds
    }
    private var decodedFrameCount: Int = 0
    private var notReadyStreak = 0

    private let processQueue = DispatchQueue(label: "com.headunitpad.videodecode", qos: .userInteractive)
    private let frameQueueLock = NSLock()
    private var pendingFrames: [Data] = []
    private var isProcessingFrame = false

    private let maxPendingFrames = 30
    private let maxPendingEssentialFrames = 60

    private var hasDecodedKeyframe = false
    private let diagnosticsLock = NSLock()
    private var diagnostics = RendererDiagnostics()

    private struct GeometryCache: Equatable {
        let bounds: CGRect
        let fitMode: VideoFitMode
        let codecW: Int
        let codecH: Int
        let marginW: Int
        let marginH: Int
    }
    private var lastAppliedGeometry: GeometryCache?

    // Recovery, concealment, and latency monitors
    private let keyframeRepairTracker = KeyframeRepairTracker()
    private let latencyMonitor = DecodeLatencyMonitor()
    private var concealmentState: CorruptionConcealmentPolicy.State = .armed
    private var concealmentWindowOpenedMs: Int64 = 0
    private var sessionHasRendered: Bool = false

    // Real-time HUD performance properties
    public private(set) var currentFps: Int = 0
    private var fpsFrameCount: Int = 0
    private var lastFpsTimestamp: TimeInterval = 0

    public var droppedFrames: Int {
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        return diagnostics.queueDrops + diagnostics.notReadyDrops + diagnostics.missingConfigDrops
    }

    public var keyframeRepairs: Int {
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        return diagnostics.concealedFrames
    }

    public var decodeLatency: (medianMs: Double, p95Ms: Double) {
        guard let rep = latencyMonitor.peekReport() else { return (0.0, 0.0) }
        return (Double(rep.medianUs) / 1000.0, Double(rep.p95Us) / 1000.0)
    }

    private let activeClipView = UIView()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.masksToBounds = true
        activeClipView.clipsToBounds = true
        activeClipView.isUserInteractionEnabled = false
        addSubview(activeClipView)
        displayLayer.videoGravity = .resize
        activeClipView.layer.addSublayer(displayLayer)
        applyGeometry()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        applyGeometry()
    }

    public func updateGeometry() {
        DispatchQueue.main.async { [weak self] in
            self?.applyGeometry()
        }
    }

    public func applyGeometry() {
        let viewBounds = self.bounds
        guard viewBounds.width > 0 && viewBounds.height > 0 else { return }

        let screenConfig = HeadUnitScreenConfig.shared
        let fitMode = self.fitMode
        let codecW = self.codecWidth > 0 ? self.codecWidth : screenConfig.getNegotiatedWidth()
        let codecH = self.codecHeight > 0 ? self.codecHeight : screenConfig.getNegotiatedHeight()
        let marginW = self.widthMargin
        let marginH = self.heightMargin

        let currentGeom = GeometryCache(
            bounds: viewBounds,
            fitMode: fitMode,
            codecW: codecW,
            codecH: codecH,
            marginW: marginW,
            marginH: marginH
        )
        if lastAppliedGeometry == currentGeom {
            return
        }
        lastAppliedGeometry = currentGeom

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let activeW = max(1, codecW - marginW)
        let activeH = max(1, codecH - marginH)

        let activeRect = ProjectionGeometryPolicy.activeDisplayRect(
            bounds: viewBounds,
            activeW: activeW,
            activeH: activeH,
            fitMode: fitMode
        )

        let boundsLandscape = viewBounds.width > viewBounds.height
        let activeLandscape = activeW > activeH
        let isMismatched = boundsLandscape != activeLandscape

        if marginW > 0 || marginH > 0 {
            activeClipView.frame = activeRect
            let overscanFrame = ProjectionGeometryPolicy.overscanLayerFrame(
                activeRect: CGRect(origin: .zero, size: activeRect.size),
                codecW: codecW,
                codecH: codecH,
                activeW: activeW,
                activeH: activeH
            )
            displayLayer.videoGravity = .resize
            displayLayer.frame = overscanFrame
        } else {
            activeClipView.frame = viewBounds
            displayLayer.frame = activeClipView.bounds
            switch fitMode {
            case .contain, .fit:
                displayLayer.videoGravity = .resizeAspect
                displayLayer.frame = activeRect
            case .cover:
                displayLayer.videoGravity = .resizeAspectFill
                displayLayer.frame = activeRect
            case .fill, .fillMargin:
                if isMismatched {
                    displayLayer.videoGravity = .resizeAspect
                } else {
                    displayLayer.videoGravity = .resize
                }
                displayLayer.frame = activeRect
            case .stretch:
                displayLayer.videoGravity = .resize
                displayLayer.frame = activeRect
            }
        }

        CATransaction.commit()
    }

    public func reset() {
        diagnosticsLock.lock()
        diagnostics = RendererDiagnostics()
        diagnosticsLock.unlock()

        frameQueueLock.lock()
        pendingFrames.removeAll()
        isProcessingFrame = false
        frameQueueLock.unlock()

        keyframeRepairTracker.reset()
        latencyMonitor.reset()
        concealmentState = .armed
        concealmentWindowOpenedMs = 0
        sessionHasRendered = false

        processQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameIndex = 0
            self.framePacer.reset()
            self.decodedFrameCount = 0
            self.vps = nil
            self.sps = nil
            self.pps = nil
            self.formatDescription = nil
            self.hasDecodedKeyframe = false
            self.pinnedCodec = nil
            self.lastNotifiedVideoSize = .zero
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.notReadyStreak = 0
            self.displayLayer.flushAndRemoveImage()
        }
    }

    public func enqueueAnnexBFrame(_ frame: Data) {
        guard !frame.isEmpty else { return }
        updateDiagnostics { $0.inputFrames += 1 }
        enqueueFrameForProcessing(frame)
    }

    public func reportCorruption(reason: String) {
        onCorruptionDetected?(reason)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let outcome = CorruptionConcealmentPolicy.next(
            nowMs: nowMs,
            state: concealmentState,
            windowOpenedMs: concealmentWindowOpenedMs,
            corruptionReported: true,
            keyframeRepaired: false,
            sessionHasRendered: sessionHasRendered
        )
        if outcome == .open {
            concealmentState = .concealing
            concealmentWindowOpenedMs = nowMs
        }
        onKeyframeRequested?()
    }

    public func diagnosticLines() -> [String] {
        diagnosticsLock.lock()
        let snapshot = diagnostics
        diagnosticsLock.unlock()

        let nalTypes = snapshot.lastNALTypes.isEmpty
            ? "None"
            : snapshot.lastNALTypes.map(String.init).joined(separator: ",")

        let latencyStr = latencyMonitor.report()?.description ?? snapshot.latencyReport

        return [
            "Renderer active codec: \(snapshot.activeCodec)",
            "Renderer input frames: \(snapshot.inputFrames)",
            "Renderer parsed frames: \(snapshot.parsedFrames)",
            "Renderer VPS/SPS/PPS NALs: \(snapshot.vpsNALs)/\(snapshot.spsNALs)/\(snapshot.ppsNALs)",
            "Renderer IDR/IRAP frames: \(snapshot.idrFrames)",
            "Renderer format descriptions/failures: \(snapshot.formatDescriptions)/\(snapshot.formatFailures)",
            "Renderer drops missing config/awaiting IDR: \(snapshot.missingConfigDrops)/\(snapshot.awaitingIDRDrops)",
            "Renderer sample buffers/failures: \(snapshot.sampleBuffers)/\(snapshot.sampleFailures)",
            "Renderer enqueued/not-ready/layer failures: \(snapshot.enqueuedSamples)/\(snapshot.notReadyDrops)/\(snapshot.layerFailures)",
            "Renderer queue drops/concealed: \(snapshot.queueDrops)/\(snapshot.concealedFrames)",
            "Renderer last NAL types: \(nalTypes)",
            "Renderer latency: \(latencyStr)",
            "Renderer display status: \(displayStatusDescription())",
            "Renderer display error: \(displayLayer.error?.localizedDescription ?? "None")",
        ]
    }

    private func enqueueFrameForProcessing(_ frame: Data) {
        var droppedFrames = 0

        frameQueueLock.lock()
        let fps = ProjectionSettings.fpsLimit.rawValue == 1 ? 60 : 30
        let capacity = VideoFeedQueuePolicy.capacityFor(fpsLimit: fps)
        let dynamicMax = min(capacity, maxPendingFrames)

        if pendingFrames.count >= dynamicMax {
            if let dropIndex = pendingFrames.firstIndex(where: { !isEssentialFrame($0) }) {
                pendingFrames.remove(at: dropIndex)
                droppedFrames = 1
            } else if pendingFrames.count >= maxPendingEssentialFrames {
                pendingFrames.removeFirst()
                droppedFrames = 1
            }
        }
        pendingFrames.append(frame)

        let shouldStartProcessing = !isProcessingFrame
        if shouldStartProcessing {
            isProcessingFrame = true
        }
        frameQueueLock.unlock()

        if droppedFrames > 0 {
            updateDiagnostics { $0.queueDrops += droppedFrames }
            onKeyframeRequested?()
        }

        guard shouldStartProcessing else { return }
        processQueue.async { [weak self] in
            self?.processFrameLoop()
        }
    }

    private func processFrameLoop() {
        while true {
            let nextFrame: Data?
            frameQueueLock.lock()
            if pendingFrames.isEmpty {
                isProcessingFrame = false
                frameQueueLock.unlock()
                return
            }
            nextFrame = pendingFrames.removeFirst()
            frameQueueLock.unlock()

            guard let frame = nextFrame else { continue }
            processSingleFrame(frame)
        }
    }

    private func processSingleFrame(_ frame: Data) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let nalUnits = H264NALParser.nalUnits(from: frame)
        guard !nalUnits.isEmpty else { return }

        // Classify codec from NAL headers or config
        let isHevcStream = detectHevc(from: nalUnits)
        let isHevc = (pinnedCodec == .hevc) || isHevcStream

        if pinnedCodec == nil {
            pinnedCodec = isHevc ? .hevc : .h264
            updateDiagnostics { $0.activeCodec = isHevc ? "HEVC (H.265)" : "H.264 (AVC)" }
        }

        // Scan parameter sets, slice NALUs, and keyframe status
        var extractedVPS: Data?
        var extractedSPS: Data?
        var extractedPPS: Data?
        var nalTypeInts: [Int] = []
        var accessUnitNALs: [Data] = []
        var hasVclSlice = false
        var isKeyframe = false

        if isHevc {
            for nal in nalUnits {
                guard let first = nal.first else { continue }
                let nalType = Int((first & 0x7E) >> 1)
                nalTypeInts.append(nalType)
                if (16...21).contains(nalType) {
                    isKeyframe = true
                }
                if nalType == 32 {
                    extractedVPS = nal
                } else if nalType == 33 {
                    extractedSPS = nal
                } else if nalType == 34 {
                    extractedPPS = nal
                } else if nalType == 35 {
                    // AUD - skip in HVCC sample buffer
                    continue
                } else {
                    accessUnitNALs.append(nal)
                    if (0...21).contains(nalType) {
                        hasVclSlice = true
                    }
                }
            }
        } else {
            for nal in nalUnits {
                guard let first = nal.first else { continue }
                let nalType = Int(first & 0x1F)
                nalTypeInts.append(nalType)
                if nalType == 5 {
                    isKeyframe = true
                }
                if nalType == 7 {
                    extractedSPS = nal
                } else if nalType == 8 {
                    extractedPPS = nal
                } else if nalType == 9 {
                    // AUD - skip in AVCC sample buffer
                    continue
                } else {
                    accessUnitNALs.append(nal)
                    if (1...5).contains(nalType) {
                        hasVclSlice = true
                    }
                }
            }
        }

        updateDiagnostics {
            $0.parsedFrames += 1
            $0.lastNALTypes = nalTypeInts
            if isHevc {
                $0.vpsNALs += nalTypeInts.filter { $0 == 32 }.count
                $0.spsNALs += nalTypeInts.filter { $0 == 33 }.count
                $0.ppsNALs += nalTypeInts.filter { $0 == 34 }.count
            } else {
                $0.spsNALs += nalTypeInts.filter { $0 == 7 }.count
                $0.ppsNALs += nalTypeInts.filter { $0 == 8 }.count
            }
            if isKeyframe {
                $0.idrFrames += 1
            }
        }

        var paramSetsChanged = false
        if let v = extractedVPS, v != self.vps {
            self.vps = v
            paramSetsChanged = true
        }
        if let s = extractedSPS, s != self.sps {
            self.sps = s
            paramSetsChanged = true
        }
        if let p = extractedPPS, p != self.pps {
            self.pps = p
            paramSetsChanged = true
        }

        // Build format description when parameter sets are ready or have changed
        if formatDescription == nil || paramSetsChanged {
            if isHevc, let v = vps, let s = sps, let p = pps {
                if let desc = createHevcFormatDescription(vps: v, sps: s, pps: p) {
                    formatDescription = desc
                    updateDiagnostics { $0.formatDescriptions += 1 }
                } else {
                    updateDiagnostics { $0.formatFailures += 1 }
                }
            } else if !isHevc, let s = sps, let p = pps {
                if let desc = createH264FormatDescription(sps: s, pps: p) {
                    formatDescription = desc
                    updateDiagnostics { $0.formatDescriptions += 1 }
                } else {
                    updateDiagnostics { $0.formatFailures += 1 }
                }
            }
        }

        if let formatDesc = formatDescription, paramSetsChanged {
            let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
            if dims.width > 0 && dims.height > 0 {
                let resolved = CGSize(width: Int(dims.width), height: Int(dims.height))
                if resolved != lastNotifiedVideoSize {
                    lastNotifiedVideoSize = resolved
                    DispatchQueue.main.async { [weak self] in
                        self?.onVideoSizeResolved?(resolved)
                    }
                }
            }
        }

        guard let formatDesc = formatDescription else {
            updateDiagnostics { $0.missingConfigDrops += 1 }
            return
        }

        // Pure parameter-set configuration packet (e.g. 0x0001 SPS/PPS): formatDescription is ready, no VCL slice to decode.
        guard hasVclSlice, !accessUnitNALs.isEmpty else {
            return
        }

        // Drop predictive frames until first keyframe arrives
        if !hasDecodedKeyframe {
            guard isKeyframe else {
                updateDiagnostics { $0.awaitingIDRDrops += 1 }
                return
            }
            hasDecodedKeyframe = true
        }

        if isKeyframe {
            keyframeRepairTracker.onKeyframeFed(ptsUs: frameIndex)
        }

        // Check corruption concealment policy
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let repairConfirmed = isKeyframe && keyframeRepairTracker.keyframeDecoded
        let outcome = CorruptionConcealmentPolicy.next(
            nowMs: nowMs,
            state: concealmentState,
            windowOpenedMs: concealmentWindowOpenedMs,
            corruptionReported: false,
            keyframeRepaired: repairConfirmed,
            sessionHasRendered: sessionHasRendered
        )

        switch outcome {
        case .closeRepaired, .rearm:
            concealmentState = .armed
        case .closeExpired:
            concealmentState = .disarmed
        case .conceal:
            updateDiagnostics { $0.concealedFrames += 1 }
            return
        case .open:
            concealmentState = .concealing
            concealmentWindowOpenedMs = nowMs
            updateDiagnostics { $0.concealedFrames += 1 }
            return
        case .show:
            break
        }

        // Package all video NALUs of this Access Unit (e.g. SEI + multiple Slices) into one 4-byte length-prefixed sample buffer
        let lengthSampleData = makeLengthPrefixedSample(from: accessUnitNALs)
        guard !lengthSampleData.isEmpty else { return }

        guard let sampleBuffer = makeSampleBuffer(data: lengthSampleData, formatDescription: formatDesc) else {
            updateDiagnostics { $0.sampleFailures += 1 }
            return
        }
        updateDiagnostics { $0.sampleBuffers += 1 }

        let currentPts = frameIndex
        let elapsedUs = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1_000_000)
        latencyMonitor.onFrameDecoded(latencyUs: elapsedUs)

        if displayLayer.status == .failed {
            updateDiagnostics { $0.layerFailures += 1 }
            DispatchQueue.main.async { [weak self] in
                self?.displayLayer.flushAndRemoveImage()
            }
            formatDescription = nil
            frameIndex = 0
            hasDecodedKeyframe = false
            notReadyStreak = 0
            onKeyframeRequested?()
            return
        }

        guard displayLayer.isReadyForMoreMediaData else {
            updateDiagnostics { $0.notReadyDrops += 1 }
            notReadyStreak += 1
            onKeyframeRequested?()

            if notReadyStreak == 30 {
                DispatchQueue.main.async { [weak self] in
                    self?.displayLayer.flush()
                }
            } else if notReadyStreak >= 90 {
                DispatchQueue.main.async { [weak self] in
                    self?.displayLayer.flushAndRemoveImage()
                }
                formatDescription = nil
                frameIndex = 0
                hasDecodedKeyframe = false
                notReadyStreak = 0
            }
            return
        }

        notReadyStreak = 0
        displayLayer.enqueue(sampleBuffer)
        let nowTime = CACurrentMediaTime()
        fpsFrameCount += 1
        if lastFpsTimestamp == 0 {
            lastFpsTimestamp = nowTime
        } else if nowTime - lastFpsTimestamp >= 1.0 {
            currentFps = Int((Double(fpsFrameCount) / (nowTime - lastFpsTimestamp)).rounded())
            fpsFrameCount = 0
            lastFpsTimestamp = nowTime
        }
        sessionHasRendered = true
        _ = keyframeRepairTracker.onFrameRendered(ptsUs: currentPts)

        updateDiagnostics { $0.enqueuedSamples += 1 }
        onFrameDisplayed?()
    }

    private func detectHevc(from nalUnits: [Data]) -> Bool {
        if ProjectionSettings.videoCodecPreference == .h264 { return false }
        if ProjectionSettings.videoCodecPreference == .hevc { return true }

        for nal in nalUnits {
            guard let first = nal.first else { continue }
            let hevcType = (first & 0x7E) >> 1
            if hevcType == 32 || hevcType == 33 || hevcType == 34 {
                return true
            }
        }
        return false
    }

    private func isEssentialFrame(_ frame: Data) -> Bool {
        let nalUnits = H264NALParser.nalUnits(from: frame)
        for nal in nalUnits {
            guard let first = nal.first else { continue }
            let avcType = first & 0x1F
            if avcType == 5 || avcType == 7 || avcType == 8 {
                return true
            }
            let hevcType = (first & 0x7E) >> 1
            if hevcType == 32 || hevcType == 33 || hevcType == 34 || (16...21).contains(hevcType) {
                return true
            }
        }
        return false
    }

    private func createH264FormatDescription(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        return sps.withUnsafeBytes { spsPtr in
            pps.withUnsafeBytes { ppsPtr in
                guard let spsBase = spsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsBase = ppsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return nil
                }
                var formatDesc: CMFormatDescription?
                let parameterSetPointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let parameterSetSizes: [Int] = [sps.count, pps.count]

                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDesc
                )
                guard status == noErr else { return nil }
                return formatDesc
            }
        }
    }

    private func createHevcFormatDescription(vps: Data, sps: Data, pps: Data) -> CMVideoFormatDescription? {
        return vps.withUnsafeBytes { vpsPtr in
            sps.withUnsafeBytes { spsPtr in
                pps.withUnsafeBytes { ppsPtr in
                    guard let vpsBase = vpsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let spsBase = spsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let ppsBase = ppsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return nil
                    }
                    var formatDesc: CMFormatDescription?
                    let parameterSetPointers: [UnsafePointer<UInt8>] = [vpsBase, spsBase, ppsBase]
                    let parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]

                    let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: parameterSetPointers,
                        parameterSetSizes: parameterSetSizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &formatDesc
                    )
                    guard status == noErr else { return nil }
                    return formatDesc
                }
            }
        }
    }

    private func makeLengthPrefixedSample(from nalUnits: [Data]) -> Data {
        var out = Data()
        for nal in nalUnits {
            guard !nal.isEmpty else { continue }
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(nal)
        }
        return out
    }

    private func makeSampleBuffer(data: Data, formatDescription: CMVideoFormatDescription) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else { return nil }

        let copyStatus = data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        guard copyStatus == noErr else { return nil }

        let nowSeconds = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        let is30Fps = (ProjectionSettings.effectiveFpsLimit.rawValue == 2 || ProjectionSettings.effectiveFpsLimit == .fps30)
        let frameInterval: Double = is30Fps ? (1.0 / 30.0) : (1.0 / 60.0)
        let targetSeconds = framePacer.nextPts(nowSeconds: nowSeconds, frameInterval: frameInterval)
        let pts = CMTimeMakeWithSeconds(targetSeconds, preferredTimescale: 1_000_000_000)
        let duration = CMTimeMakeWithSeconds(frameInterval, preferredTimescale: 1_000_000_000)
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        frameIndex += 1

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = data.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0),
                to: CFMutableDictionary.self
            )
            if decodedFrameCount == 0 {
                CFDictionarySetValue(
                    dictionary,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            } else {
                CFDictionarySetValue(
                    dictionary,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanFalse).toOpaque()
                )
            }
        }
        decodedFrameCount += 1
        return sampleBuffer
    }

    private func updateDiagnostics(_ update: (inout RendererDiagnostics) -> Void) {
        diagnosticsLock.lock()
        update(&diagnostics)
        diagnosticsLock.unlock()
    }

    private func displayStatusDescription() -> String {
        switch displayLayer.status {
        case .unknown: return "Unknown"
        case .rendering: return "Rendering"
        case .failed: return "Failed"
        @unknown default: return "Other"
        }
    }
}
