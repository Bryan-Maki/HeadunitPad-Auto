//
//  MicSessionController.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicSessionController.kt
//

import Foundation

public final class MicSessionController {
    public final class CaptureCallbacks {
        public let data: (Data, Int, Int) -> Void
        public let failed: () -> Void
        public let isCurrent: () -> Bool

        public init(
            data: @escaping (Data, Int, Int) -> Void,
            failed: @escaping () -> Void,
            isCurrent: @escaping () -> Bool
        ) {
            self.data = data
            self.failed = failed
            self.isCurrent = isCurrent
        }
    }

    private let lock = NSLock()
    private let lifecycle: (@escaping () -> Void) -> Void
    private let sending: (@escaping () -> Void) -> Void
    private let startCapture: (CaptureCallbacks) -> Int
    private let stopCapture: () -> Void
    private let response: (Int, Bool) -> Void
    private let data: (Data, Int64) -> Void
    private let clockMs: () -> Int64
    private let timestampUs: () -> Int64
    private let report: (MicUplinkMonitor.Report) -> Void

    private final class Packet {
        let bytes: Data
        let timestamp: Int64
        let peak: Int

        init(bytes: Data, timestamp: Int64, peak: Int) {
            self.bytes = bytes
            self.timestamp = timestamp
            self.peak = peak
        }
    }

    private final class Run {
        let id: Int
        var open = true
        let chunks = MicChunkAccumulator()
        let monitor = MicUplinkMonitor()
        var flow: MicFlowControl<Packet>!
        var token: Int64 = 0

        init(id: Int, window: Int, clockMs: Int64, flowHandler: @escaping (Int64, Packet) -> Void) {
            self.id = id
            self.monitor.onSessionStart(nowMs: clockMs)
            self.flow = MicFlowControl<Packet>(dispatch: flowHandler)
            self.token = self.flow.begin(sessionId: id, maxUnacked: window)
        }
    }

    private var sequence = 0
    private var current: Run?
    private var stopped = false

    public init(
        lifecycle: @escaping (@escaping () -> Void) -> Void,
        sending: @escaping (@escaping () -> Void) -> Void,
        startCapture: @escaping (CaptureCallbacks) -> Int,
        stopCapture: @escaping () -> Void,
        response: @escaping (Int, Bool) -> Void,
        data: @escaping (Data, Int64) -> Void,
        clockMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        timestampUs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000_000) },
        report: @escaping (MicUplinkMonitor.Report) -> Void = { _ in }
    ) {
        self.lifecycle = lifecycle
        self.sending = sending
        self.startCapture = startCapture
        self.stopCapture = stopCapture
        self.response = response
        self.data = data
        self.clockMs = clockMs
        self.timestampUs = timestampUs
        self.report = report
    }

    public func open(window: Int) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        guard (1...4096).contains(window) else {
            rejectLocked()
            lock.unlock()
            return
        }

        if let existing = current {
            let id = existing.id
            let isOpen = existing.open
            lock.unlock()
            lifecycle { [weak self] in
                self?.response(id, isOpen)
            }
            return
        }

        sequence += 1
        let runId = sequence
        var runRef: Run!

        let run = Run(id: runId, window: window, clockMs: clockMs()) { [weak self] token, packet in
            guard let self = self else { return }
            self.sending {
                self.lock.lock()
                guard let cur = self.current, cur.id == runId, cur.open else {
                    self.lock.unlock()
                    return
                }
                let claimed = cur.flow.claim(token: token, frame: packet)
                if claimed {
                    cur.monitor.onFrame(payloadBytes: packet.bytes.count, framePeak: packet.peak, nowMs: self.clockMs())
                }
                self.lock.unlock()

                if claimed {
                    self.data(packet.bytes, packet.timestamp)
                }
            }
        }
        runRef = run
        current = run
        lock.unlock()

        lifecycle { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let requested = runRef.open
            self.lock.unlock()

            let result: Int
            if requested {
                result = self.startCapture(CaptureCallbacks(
                    data: { [weak self] bytes, length, peak in
                        self?.captured(run: runRef, bytes: bytes, length: length, peak: peak)
                    },
                    failed: { [weak self] in
                        self?.captureFailed(run: runRef)
                    },
                    isCurrent: { [weak self] in
                        guard let self = self else { return false }
                        self.lock.lock()
                        defer { self.lock.unlock() }
                        return runRef.open && (self.current === runRef)
                    }
                ))
            } else {
                result = -1
            }

            if result != 0 {
                self.lock.lock()
                let summary = runRef.open ? self.retireLocked(run: runRef, rejectedBytes: 0) : nil
                self.lock.unlock()
                if let summary = summary {
                    self.report(summary)
                }
                self.stopCapture()
            }

            self.lock.lock()
            self.response(runRef.id, result == 0)
            if runRef.open && (self.current === runRef) && result == 0 {
                runRef.flow.activate(token: runRef.token)
            }
            self.lock.unlock()
        }
    }

    public func close(reply: Bool = false, shutdown: Bool = false) {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        if shutdown { stopped = true }
        let run = current
        let id = run?.id ?? sequence
        let summary = run != nil ? retireLocked(run: run!, rejectedBytes: 0) : nil
        lock.unlock()

        lifecycle { [weak self] in
            if let summary = summary {
                self?.report(summary)
            }
            self?.stopCapture()
            if reply {
                self?.response(id, true)
            }
        }
    }

    public func acknowledge(id: Int, count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let run = current, run.flow.acknowledge(sessionId: id, count: count) else {
            return false
        }
        for _ in 0..<count {
            run.monitor.onAck()
        }
        return true
    }

    private func rejectLocked() {
        let run = current
        let id = run?.id ?? sequence
        let summary = run != nil ? retireLocked(run: run!, rejectedBytes: 0) : nil
        lifecycle { [weak self] in
            if let summary = summary {
                self?.report(summary)
            }
            if run != nil { self?.stopCapture() }
            self?.response(id, false)
        }
    }

    private func captured(run: Run, bytes: Data, length: Int, peak: Int) {
        lock.lock()
        guard run.open, current === run, length > 0 else {
            lock.unlock()
            return
        }

        let discarded = run.chunks.offerWhile(src: bytes, srcLen: length, capturedAtUs: timestampUs(), peak: peak) { chunk, size, stamp, level in
            let pkt = Packet(bytes: chunk.subdata(in: 0..<size), timestamp: stamp, peak: level)
            return run.flow.offer(frame: pkt) == .accepted
        }

        if discarded != 0 {
            let summary = retireLocked(run: run, rejectedBytes: discarded)
            lock.unlock()
            lifecycle { [weak self] in
                if let summary = summary {
                    self?.report(summary)
                }
                self?.stopCapture()
                self?.response(run.id, false)
            }
        } else {
            lock.unlock()
        }
    }

    private func captureFailed(run: Run) {
        lock.lock()
        guard run.open, current === run else {
            lock.unlock()
            return
        }
        let summary = retireLocked(run: run, rejectedBytes: 0)
        lock.unlock()

        lifecycle { [weak self] in
            if let summary = summary {
                self?.report(summary)
            }
            self?.stopCapture()
            self?.response(run.id, false)
        }
    }

    private func retireLocked(run: Run, rejectedBytes: Int) -> MicUplinkMonitor.Report? {
        run.open = false
        if current === run { current = nil }
        let cancelled = run.flow.close().reduce(0) { $0 + $1.bytes.count }
        run.monitor.onDiscarded(bytes: cancelled + run.chunks.reset() + rejectedBytes)
        return run.monitor.onSessionEnd(nowMs: clockMs())
    }
}
