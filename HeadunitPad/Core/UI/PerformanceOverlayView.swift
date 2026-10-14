//
//  PerformanceOverlayView.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PerformanceOverlay.kt & DebugOverlayView.kt
//  Real-time HUD overlay showing FPS, CPU, thermal status, decoding latency, and bitrate.
//

import UIKit

public final class PerformanceOverlayView: UIView {

    public var enabledFields: Set<PerformanceOverlayField> = PerformanceOverlayPolicy.fromBits(PerformanceOverlayPolicy.defaultBits) {
        didSet {
            refreshDisplay()
        }
    }

    private let textLabel = UILabel()
    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        return UIVisualEffectView(effect: blur)
    }()

    private var sampleTimer: Timer?
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var currentFps: Int = 0
    private var lastLatencyMs: Double = 0
    private var currentBitrateKbps: Double = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .clear
        layer.cornerRadius = 10
        layer.masksToBounds = true
        layer.borderWidth = 1.0
        layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor

        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)

        textLabel.numberOfLines = 0
        textLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        textLabel.textColor = UIColor.green.withAlphaComponent(0.9)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])

        startMonitoring()
    }

    public func recordFrameReceived(latencyMs: Double = 0, bytes: Int = 0) {
        frameCount += 1
        if latencyMs > 0 {
            lastLatencyMs = latencyMs
        }
        if bytes > 0 {
            // Instantaneous estimate
            currentBitrateKbps = Double(bytes * 8) / 1000.0 * 30.0
        }
    }

    public func startMonitoring() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.samplePerformance()
        }
    }

    public func stopMonitoring() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    private func samplePerformance() {
        currentFps = frameCount
        frameCount = 0

        refreshDisplay()
    }

    private func refreshDisplay() {
        let thermalString: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalString = "Nominal"
        case .fair: thermalString = "Fair"
        case .serious: thermalString = "Serious (Warm)"
        case .critical: thermalString = "Critical"
        @unknown default: thermalString = "Unknown"
        }

        let formatted = PerformanceOverlayPolicy.format(
            fields: enabledFields,
            fps: currentFps > 0 ? currentFps : nil,
            appCpu: sampleAppCpuUsage(),
            totalCpu: nil,
            thermalState: thermalString,
            frameLatencyMs: lastLatencyMs > 0 ? lastLatencyMs : nil,
            bitrateKbps: currentBitrateKbps > 0 ? currentBitrateKbps : nil
        )

        DispatchQueue.main.async {
            self.textLabel.text = formatted
        }
    }

    private func sampleAppCpuUsage() -> Double? {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kernReturn = task_threads(mach_task_self_, &threadList, &threadCount)

        guard kernReturn == KERN_SUCCESS, let threads = threadList else {
            return nil
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS {
                let flags = threadInfo.flags
                if (flags & TH_FLAGS_IDLE) == 0 {
                    let cpuUsage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    totalUsage += cpuUsage
                }
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size)))
        return totalUsage
    }

    deinit {
        sampleTimer?.invalidate()
    }
}
