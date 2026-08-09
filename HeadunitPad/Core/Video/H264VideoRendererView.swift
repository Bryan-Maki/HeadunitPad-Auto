import UIKit
import AVFoundation
import CoreMedia

final class H264VideoRendererView: UIView {
    private struct RendererDiagnostics {
        var inputFrames = 0
        var parsedFrames = 0
        var spsNALs = 0
        var ppsNALs = 0
        var idrFrames = 0
        var formatDescriptions = 0
        var formatFailures = 0
        var missingConfigDrops = 0
        var awaitingIDRDrops = 0
        var sampleBuffers = 0
        var sampleFailures = 0
        var enqueuedSamples = 0
        var notReadyDrops = 0
        var layerFailures = 0
        var queueDrops = 0
        var lastNALTypes: [UInt8] = []
    }

    var onFrameDisplayed: (() -> Void)?

    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private var displayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }

    private var formatDescription: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    private var frameIndex: Int64 = 0
    private var notReadyStreak = 0
    private let processQueue = DispatchQueue(label: "com.headunitpad.video.process", qos: .userInteractive)
    private let frameQueueLock = NSLock()
    private var pendingFrames: [Data] = []
    private var isProcessingFrame = false
    private let maxPendingFrames = 4
    // Parameter sets arrive once per session, so a backlog of frames the decoder
    // still needs is allowed to grow well past the normal cap before anything goes.
    private let maxPendingEssentialFrames = 12
    private var hasDecodedKeyframe = false
    private let diagnosticsLock = NSLock()
    private var diagnostics = RendererDiagnostics()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
    }

    func reset() {
        diagnosticsLock.lock()
        diagnostics = RendererDiagnostics()
        diagnosticsLock.unlock()
        frameQueueLock.lock()
        pendingFrames.removeAll()
        isProcessingFrame = false
        frameQueueLock.unlock()

        processQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameIndex = 0
            self.sps = nil
            self.pps = nil
            self.formatDescription = nil
            self.hasDecodedKeyframe = false
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.notReadyStreak = 0
            self.displayLayer.flushAndRemoveImage()
        }
    }

    func enqueueAnnexBFrame(_ frame: Data) {
        guard !frame.isEmpty else { return }
        updateDiagnostics { $0.inputFrames += 1 }
        enqueueFrameForProcessing(frame)
    }

    func diagnosticLines() -> [String] {
        diagnosticsLock.lock()
        let snapshot = diagnostics
        diagnosticsLock.unlock()
        let nalTypes = snapshot.lastNALTypes.isEmpty
            ? "None"
            : snapshot.lastNALTypes.map(String.init).joined(separator: ",")
        return [
            "Renderer input frames: \(snapshot.inputFrames)",
            "Renderer parsed frames: \(snapshot.parsedFrames)",
            "Renderer SPS/PPS NALs: \(snapshot.spsNALs)/\(snapshot.ppsNALs)",
            "Renderer IDR frames: \(snapshot.idrFrames)",
            "Renderer format descriptions/failures: \(snapshot.formatDescriptions)/\(snapshot.formatFailures)",
            "Renderer drops missing config/awaiting IDR: \(snapshot.missingConfigDrops)/\(snapshot.awaitingIDRDrops)",
            "Renderer sample buffers/failures: \(snapshot.sampleBuffers)/\(snapshot.sampleFailures)",
            "Renderer enqueued/not-ready/layer failures: \(snapshot.enqueuedSamples)/\(snapshot.notReadyDrops)/\(snapshot.layerFailures)",
            "Renderer queue drops: \(snapshot.queueDrops)",
            "Renderer last NAL types: \(nalTypes)",
            "Renderer display status: \(displayStatusDescription())",
            "Renderer display error: \(displayLayer.error?.localizedDescription ?? "None")",
        ]
    }

    private func enqueueFrameForProcessing(_ frame: Data) {
        var droppedFrames = 0

        frameQueueLock.lock()
        if pendingFrames.count >= maxPendingFrames {
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
        let nalUnits = H264NALParser.nalUnits(from: frame)
        guard !nalUnits.isEmpty else { return }

        let nalTypes = nalUnits.compactMap { $0.first.map { $0 & 0x1F } }
        updateDiagnostics {
            $0.parsedFrames += 1
            $0.lastNALTypes = nalTypes
            $0.spsNALs += nalTypes.filter { $0 == 7 }.count
            $0.ppsNALs += nalTypes.filter { $0 == 8 }.count
        }

        let hasIDR = nalTypes.contains(5)
        if hasIDR {
            updateDiagnostics { $0.idrFrames += 1 }
        }

        for nal in nalUnits {
            guard let header = nal.first else { continue }
            let nalType = header & 0x1F
            if nalType == 7 { sps = nal }
            if nalType == 8 { pps = nal }
        }

        if formatDescription == nil, let sps, let pps {
            if let desc = createFormatDescription(sps: sps, pps: pps) {
                formatDescription = desc
                updateDiagnostics { $0.formatDescriptions += 1 }
            } else {
                updateDiagnostics { $0.formatFailures += 1 }
            }
        }

        guard let formatDescription else {
            updateDiagnostics { $0.missingConfigDrops += 1 }
            return
        }

        // Drop predictive frames until first keyframe to avoid startup block artifacts.
        if !hasDecodedKeyframe {
            guard hasIDR else {
                updateDiagnostics { $0.awaitingIDRDrops += 1 }
                return
            }
            hasDecodedKeyframe = true
        }

        let avccData = makeAVCCSample(from: nalUnits)
        guard !avccData.isEmpty else { return }
        guard let sampleBuffer = makeSampleBuffer(data: avccData, formatDescription: formatDescription) else {
            updateDiagnostics { $0.sampleFailures += 1 }
            return
        }
        updateDiagnostics { $0.sampleBuffers += 1 }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.displayLayer.status == .failed {
                self.updateDiagnostics { $0.layerFailures += 1 }
                // Full reset helps recover from persistent AVSampleBufferDisplayLayer failures.
                self.displayLayer.flushAndRemoveImage()
                self.processQueue.async {
                    self.formatDescription = nil
                    self.frameIndex = 0
                    self.hasDecodedKeyframe = false
                }
                self.notReadyStreak = 0
                return
            }

            guard self.displayLayer.isReadyForMoreMediaData else {
                self.updateDiagnostics { $0.notReadyDrops += 1 }
                self.notReadyStreak += 1

                if self.notReadyStreak == 30 {
                    self.displayLayer.flush()
                } else if self.notReadyStreak >= 90 {
                    self.displayLayer.flushAndRemoveImage()
                    self.processQueue.async {
                        self.formatDescription = nil
                        self.frameIndex = 0
                        self.hasDecodedKeyframe = false
                    }
                    self.notReadyStreak = 0
                }
                return
            }

            self.notReadyStreak = 0
            self.displayLayer.enqueue(sampleBuffer)
            self.updateDiagnostics { $0.enqueuedSamples += 1 }
            self.onFrameDisplayed?()
        }
    }

    /// Frames carrying parameter sets or a keyframe must survive queue pressure.
    /// The stream sends SPS/PPS once, so dropping that frame costs the decoder its
    /// only chance to build a format description and every later frame is wasted.
    private func isEssentialFrame(_ frame: Data) -> Bool {
        let nalUnits = H264NALParser.nalUnits(from: frame)
        for nal in nalUnits {
            guard let header = nal.first else { continue }
            switch header & 0x1F {
            case 5, 7, 8:
                return true
            default:
                continue
            }
        }
        return false
    }

    private func createFormatDescription(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        return sps.withUnsafeBytes { spsPtr in
            return pps.withUnsafeBytes { ppsPtr in
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

    private func makeAVCCSample(from nalUnits: [Data]) -> Data {
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

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 30),
            decodeTimeStamp: .invalid
        )
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
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
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
