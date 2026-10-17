//
//  SettingsViewController.swift
//  HeadunitPad
//
//  Native iPadOS insetGrouped Settings Controller for HeadunitPad-Auto.
//  Hosts embedded interactive DpiPreviewView, pipeline preferences,
//  smart sensors, diagnostics, logs and settings backup/restore.
//

import UIKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Enums & Types

    enum ChangeImpact {
        case uiOnly
        case nightModeChanged
        case geometryChanged
        case requiresReconnect
    }

    enum SettingsSection: Int, CaseIterable {
        case activeSession = 0
        case displayLayout = 1
        case videoAudio = 2
        case smartSensors = 3
        case connectionAutomation = 4
        case diagnosticsBackup = 5

        var title: String? {
            switch self {
            case .activeSession:
                return ConnectionManager.shared.state == .running ? "Active Session" : nil
            case .displayLayout:
                return "Display & Coolwalk Layout"
            case .videoAudio:
                return "Video & Audio Pipeline"
            case .smartSensors:
                return "Smart Sensors & Night Mode"
            case .connectionAutomation:
                return "Connection & Automation"
            case .diagnosticsBackup:
                return "Diagnostics, Logs & Backup"
            }
        }
    }

    // MARK: - Public Callbacks

    var onSettingsChanged: ((ChangeImpact) -> Void)?
    var onProvideDiagnosticLines: (() -> [String])?
    var connectionManager: ConnectionManager = ConnectionManager.shared

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 50
        table.keyboardDismissMode = .onDrag
        return table
    }()

    private var dpiPreviewCell: DpiPreviewCell?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func setupUI() {
        title = "Projection Settings"
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width: 640, height: 740)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }

    // MARK: - Helper Presentation

    private func configurePopover(for controller: UIViewController, sourceView: UIView) {
        if let popover = controller.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return SettingsSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = SettingsSection(rawValue: section) else { return 0 }
        switch sec {
        case .activeSession:
            return connectionManager.state == .running ? 2 : 0
        case .displayLayout:
            return 6
        case .videoAudio:
            return 5
        case .smartSensors:
            return 2
        case .connectionAutomation:
            return 2
        case .diagnosticsBackup:
            return 5
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return SettingsSection(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sec = SettingsSection(rawValue: section) else { return nil }
        switch sec {
        case .displayLayout:
            return "Adjust DPI to scale Android Auto UI elements. Virtual width ≥ 800 dp enables Coolwalk split-screen cards. Touch, resolution and margins adapt dynamically."
        case .videoAudio:
            return "Hardware decoding and microphone routing preferences. Vehicle identity remains permanent Car (CAR 1) for seamless multi-device coexistence."
        case .connectionAutomation:
            return "Auto Reconnect retries failed or interrupted wireless connections silently."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sec = SettingsSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch sec {
        case .activeSession:
            return makeActiveSessionCell(for: indexPath.row)
        case .displayLayout:
            return makeDisplayLayoutCell(for: indexPath.row)
        case .videoAudio:
            return makeVideoAudioCell(for: indexPath.row)
        case .smartSensors:
            return makeSmartSensorsCell(for: indexPath.row)
        case .connectionAutomation:
            return makeConnectionAutomationCell(for: indexPath.row)
        case .diagnosticsBackup:
            return makeDiagnosticsBackupCell(for: indexPath.row)
        }
    }

    // MARK: - Cell Builders

    private func makeActiveSessionCell(for row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if row == 0 {
            cell.textLabel?.text = "Connected Device"
            let device = connectionManager.connectedDevice
            cell.detailTextLabel?.text = "\(device?.displayName ?? "Phone") (\(device?.ip ?? ""):\(device?.port ?? 5277))"
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.textLabel?.text = "Disconnect Android Auto"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            cell.textLabel?.textAlignment = .center
        }
        return cell
    }

    private func makeDisplayLayoutCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = DpiPreviewCell()
            cell.configure(with: HeadUnitScreenConfig.shared)
            cell.onDpiChanged = { [weak self] impact in
                self?.onSettingsChanged?(impact)
            }
            self.dpiPreviewCell = cell
            return cell

        case 1:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Resolution"
            let currentRes = ProjectionSettings.resolution
            cell.detailTextLabel?.text = currentRes.title
            cell.accessoryType = .disclosureIndicator
            return cell

        case 2:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Frame Rate"
            let seg = UISegmentedControl(items: ["60 FPS", "30 FPS"])
            seg.selectedSegmentIndex = (ProjectionSettings.fpsLimit == .fps60) ? 0 : 1
            seg.addAction(UIAction { [weak self] _ in
                let selected: ProjectionFpsLimit = (seg.selectedSegmentIndex == 0) ? .fps60 : .fps30
                ProjectionSettings.fpsLimit = selected
                if self?.connectionManager.state == .running {
                    self?.onSettingsChanged?(.requiresReconnect)
                } else {
                    self?.onSettingsChanged?(.uiOnly)
                }
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 3:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Display Fit Mode"
            let seg = UISegmentedControl(items: ["Fill", "Fit", "Stretch"])
            switch ProjectionSettings.videoFitMode {
            case .fillMargin: seg.selectedSegmentIndex = 0
            case .contain, .fill, .cover: seg.selectedSegmentIndex = 1
            case .stretch: seg.selectedSegmentIndex = 2
            }
            seg.addAction(UIAction { [weak self] _ in
                let modes: [VideoFitMode] = [.fillMargin, .contain, .stretch]
                let mode = modes[seg.selectedSegmentIndex]
                ProjectionSettings.videoFitMode = mode
                HeadUnitScreenConfig.shared.videoFitMode = mode
                HeadUnitScreenConfig.shared.recalculate()
                HeadUnitScreenConfig.shared.checkAndNotifyMarginDivergence()
                self?.dpiPreviewCell?.configure(with: HeadUnitScreenConfig.shared)
                self?.onSettingsChanged?(.geometryChanged)
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 4:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Screen Orientation"
            let seg = UISegmentedControl(items: ["Landscape", "Portrait", "Auto"])
            switch ProjectionSettings.orientation {
            case .landscape: seg.selectedSegmentIndex = 0
            case .portrait: seg.selectedSegmentIndex = 1
            case .system: seg.selectedSegmentIndex = 2
            }
            seg.addAction(UIAction { [weak self] _ in
                let orientations: [ProjectionOrientation] = [.landscape, .portrait, .system]
                let opt = orientations[seg.selectedSegmentIndex]
                ProjectionSettings.orientation = opt
                self?.onSettingsChanged?(.geometryChanged)
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 5:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Driving Position"
            let seg = UISegmentedControl(items: ["LHD (Left)", "RHD (Right)"])
            seg.selectedSegmentIndex = (ProjectionSettings.driverPosition == .right) ? 1 : 0
            seg.addAction(UIAction { [weak self] _ in
                let isRhd = (seg.selectedSegmentIndex == 1)
                ProjectionSettings.driverPosition = isRhd ? .right : .left
                self?.dpiPreviewCell?.updateRightHandDrive(isRhd)
                if self?.connectionManager.state == .running {
                    self?.onSettingsChanged?(.requiresReconnect)
                } else {
                    self?.onSettingsChanged?(.uiOnly)
                }
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        default:
            return UITableViewCell()
        }
    }

    private func makeVideoAudioCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Video Codec"
            let seg = UISegmentedControl(items: ["H.264", "HEVC"])
            switch ProjectionSettings.videoCodecPreference {
            case .h264: seg.selectedSegmentIndex = 0
            case .hevc: seg.selectedSegmentIndex = 1
            }
            seg.addAction(UIAction { [weak self] _ in
                let codecs: [VideoCodecPreference] = [.h264, .hevc]
                ProjectionSettings.videoCodecPreference = codecs[seg.selectedSegmentIndex]
                if self?.connectionManager.state == .running {
                    self?.onSettingsChanged?(.requiresReconnect)
                } else {
                    self?.onSettingsChanged?(.uiOnly)
                }
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 1:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Audio Codec"
            let seg = UISegmentedControl(items: ["AAC-LC", "PCM"])
            seg.selectedSegmentIndex = (ProjectionSettings.audioCodecPreference == .aac) ? 0 : 1
            seg.addAction(UIAction { [weak self] _ in
                let codecs: [AudioCodecPreference] = [.aac, .pcm]
                ProjectionSettings.audioCodecPreference = codecs[seg.selectedSegmentIndex]
                if self?.connectionManager.state == .running {
                    self?.onSettingsChanged?(.requiresReconnect)
                } else {
                    self?.onSettingsChanged?(.uiOnly)
                }
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 2:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Audio Output"
            let seg = UISegmentedControl(items: ["iPad", "Phone"])
            seg.selectedSegmentIndex = (ProjectionSettings.audioOutputTarget == .ipad) ? 0 : 1
            seg.addAction(UIAction { [weak self] _ in
                let targets: [AudioOutputTarget] = [.ipad, .phone]
                let target = targets[seg.selectedSegmentIndex]
                ProjectionSettings.audioOutputTarget = target
                if !target.isAudioSinkEnabled {
                    PCMAudioPlayer.shared.reset()
                }
                if self?.connectionManager.state == .running {
                    self?.onSettingsChanged?(.requiresReconnect)
                } else {
                    self?.onSettingsChanged?(.uiOnly)
                }
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 3:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Microphone Source"
            let seg = UISegmentedControl(items: ["Follow", "iPad", "Phone"])
            switch ProjectionSettings.microphoneSource {
            case .followAudioOutput: seg.selectedSegmentIndex = 0
            case .ipad: seg.selectedSegmentIndex = 1
            case .phone: seg.selectedSegmentIndex = 2
            }
            seg.addAction(UIAction { [weak self] _ in
                let sources: [MicrophoneSource] = [.followAudioOutput, .ipad, .phone]
                ProjectionSettings.microphoneSource = sources[seg.selectedSegmentIndex]
                self?.onSettingsChanged?(.uiOnly)
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 4:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Audio Stream Tester"
            cell.detailTextLabel?.text = "Test tones & ducking"
            cell.accessoryType = .disclosureIndicator
            return cell

        default:
            return UITableViewCell()
        }
    }

    private func makeSmartSensorsCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Night Mode"
            let seg = UISegmentedControl(items: ["Auto", "Day", "Night", "System"])
            switch ProjectionSettings.nightMode {
            case .auto: seg.selectedSegmentIndex = 0
            case .day: seg.selectedSegmentIndex = 1
            case .night: seg.selectedSegmentIndex = 2
            case .system: seg.selectedSegmentIndex = 3
            }
            seg.addAction(UIAction { [weak self] _ in
                let modes: [NightModeSetting] = [.auto, .day, .night, .system]
                ProjectionSettings.nightMode = modes[seg.selectedSegmentIndex]
                self?.onSettingsChanged?(.nightModeChanged)
            }, for: .valueChanged)
            cell.accessoryView = seg
            cell.selectionStyle = .none
            return cell

        case 1:
            if ProjectionSettings.supportsCellularIpad() {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "GPS Source"
                let seg = UISegmentedControl(items: ["Phone", "iPad"])
                seg.selectedSegmentIndex = (ProjectionSettings.gpsSource == .phone) ? 0 : 1
                seg.addAction(UIAction { [weak self] _ in
                    let isIpad = (seg.selectedSegmentIndex == 1)
                    ProjectionSettings.gpsSource = isIpad ? .ipad : .phone
                    if isIpad {
                        self?.connectionManager.requestLocationPermissionIfNeeded()
                    }
                    self?.onSettingsChanged?(.uiOnly)
                }, for: .valueChanged)
                cell.accessoryView = seg
                cell.selectionStyle = .none
                return cell
            } else {
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                cell.textLabel?.text = "GPS Source"
                cell.detailTextLabel?.text = "Phone Only (Wi-Fi iPad)"
                cell.selectionStyle = .none
                return cell
            }

        default:
            return UITableViewCell()
        }
    }

    private func makeConnectionAutomationCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Auto Reconnect"
            let toggle = UISwitch()
            toggle.isOn = ProjectionSettings.autoReconnect
            toggle.addAction(UIAction { _ in
                ProjectionSettings.autoReconnect = toggle.isOn
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            return cell

        case 1:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Auto Resume Playback"
            let toggle = UISwitch()
            toggle.isOn = ProjectionSettings.autoResumePlayback
            toggle.addAction(UIAction { _ in
                ProjectionSettings.autoResumePlayback = toggle.isOn
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            return cell

        default:
            return UITableViewCell()
        }
    }

    private func makeDiagnosticsBackupCell(for row: Int) -> UITableViewCell {
        switch row {
        case 0:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Performance HUD Overlay"
            let toggle = UISwitch()
            toggle.isOn = ProjectionSettings.showPerformanceOverlay
            toggle.addAction(UIAction { [weak self] _ in
                ProjectionSettings.showPerformanceOverlay = toggle.isOn
                self?.onSettingsChanged?(.uiOnly)
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            return cell

        case 1:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Live Diagnostics Report"
            cell.accessoryType = .disclosureIndicator
            return cell

        case 2:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Export / Share Session Logs"
            cell.accessoryType = .disclosureIndicator
            return cell

        case 3:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Backup / Restore Settings (JSON)"
            cell.accessoryType = .disclosureIndicator
            return cell

        case 4:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Reset All Settings to Defaults"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            return cell

        default:
            return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sec = SettingsSection(rawValue: indexPath.section) else { return }

        switch sec {
        case .activeSession:
            if indexPath.row == 0 {
                presentConnectionDetails()
            } else if indexPath.row == 1 {
                connectionManager.disconnect()
                dismiss(animated: true)
            }

        case .displayLayout:
            if indexPath.row == 1 {
                presentResolutionPicker(sourceView: tableView.cellForRow(at: indexPath) ?? tableView)
            }

        case .videoAudio:
            if indexPath.row == 4 {
                presentAudioStreamTester(sourceView: tableView.cellForRow(at: indexPath) ?? tableView)
            }

        case .diagnosticsBackup:
            switch indexPath.row {
            case 1:
                presentLiveDiagnostics()
            case 2:
                presentLogExportMenu(sourceView: tableView.cellForRow(at: indexPath) ?? tableView)
            case 3:
                presentBackupRestoreMenu(sourceView: tableView.cellForRow(at: indexPath) ?? tableView)
            case 4:
                presentResetDefaultsAlert()
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: - Modals & Action Sheets

    private func presentConnectionDetails() {
        let device = connectionManager.connectedDevice
        let details = [
            "State: \(connectionManager.state.description)",
            "Status: \(connectionManager.statusDetail)",
            "Device: \(device?.displayName ?? "Unknown")",
            "IP: \(device?.ip ?? "Unknown")",
            "Port: \(device?.port ?? 0)"
        ].joined(separator: "\n")

        let alert = UIAlertController(title: "Connection Details", message: details, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentResolutionPicker(sourceView: UIView) {
        let alert = UIAlertController(title: "Resolution", message: "Choose target projection resolution ladder", preferredStyle: .actionSheet)
        configurePopover(for: alert, sourceView: sourceView)

        let presets: [ResolutionPreset] = [.auto, .r1280x720, .r1920x1080, .r2560x1440, .r3840x2160]
        for preset in presets {
            let isCurrent = preset == ProjectionSettings.resolution
            let title = isCurrent ? "\(preset.title) (Current)" : preset.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.resolution = preset
                HeadUnitScreenConfig.shared.recalculate(requestedResolution: preset)
                self?.dpiPreviewCell?.configure(with: HeadUnitScreenConfig.shared)
                self?.tableView.reloadRows(at: [IndexPath(row: 1, section: SettingsSection.displayLayout.rawValue)], with: .fade)
                if self?.connectionManager.state == .running {
                    self?.onSettingsChanged?(.requiresReconnect)
                } else {
                    self?.onSettingsChanged?(.geometryChanged)
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentAudioStreamTester(sourceView: UIView) {
        let alert = UIAlertController(
            title: "Audio Stream Tester",
            message: "Generate synthetic 16-bit LE PCM tones to test playback channels and ducking.",
            preferredStyle: .actionSheet
        )
        configurePopover(for: alert, sourceView: sourceView)

        alert.addAction(UIAlertAction(title: "Play Media 440 Hz (1.0s)", style: .default) { _ in
            AudioStreamTester.shared.playMediaTestTone()
        })
        alert.addAction(UIAlertAction(title: "Play Guidance 587 Hz (1.0s)", style: .default) { _ in
            AudioStreamTester.shared.playGuidanceTestTone()
        })
        alert.addAction(UIAlertAction(title: "Play System 880 Hz (0.8s)", style: .default) { _ in
            AudioStreamTester.shared.playSystemTestTone()
        })
        alert.addAction(UIAlertAction(title: "Run Ducking Sequence Test", style: .default) { _ in
            AudioStreamTester.shared.playDuckingTestSequence()
        })
        alert.addAction(UIAlertAction(title: "Stop All Audio", style: .destructive) { _ in
            PCMAudioPlayer.shared.reset()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentLiveDiagnostics() {
        let lines = onProvideDiagnosticLines?() ?? connectionManager.diagnosticLines()
        let text = lines.joined(separator: "\n")
        let alert = UIAlertController(title: "Live Diagnostics", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Copy to Clipboard", style: .default) { _ in
            UIPasteboard.general.string = text
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    private func presentLogExportMenu(sourceView: UIView) {
        let alert = UIAlertController(title: "Export / Share Logs", message: "Session diagnostic logs & audit reports.", preferredStyle: .actionSheet)
        configurePopover(for: alert, sourceView: sourceView)

        alert.addAction(UIAlertAction(title: "Copy Log to Clipboard", style: .default) { _ in
            let text = LogExporter.exportToClipboardText()
            UIPasteboard.general.string = text
            AppLog.i("Diagnostic log copied to clipboard (\(text.utf8.count) bytes)", tag: "SettingsViewController")
        })
        alert.addAction(UIAlertAction(title: "Share Log File (.txt)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if let fileUrl = LogExporter.exportToTemporaryFile() {
                let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
                self.configurePopover(for: activityVC, sourceView: sourceView)
                self.present(activityVC, animated: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Clear In-Memory Logs", style: .destructive) { _ in
            AppLog.shared.clear()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentBackupRestoreMenu(sourceView: UIView) {
        let alert = UIAlertController(title: "Backup / Restore Settings", message: "Export settings to JSON or restore from clipboard.", preferredStyle: .actionSheet)
        configurePopover(for: alert, sourceView: sourceView)

        alert.addAction(UIAlertAction(title: "Copy Settings JSON to Clipboard", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let json = SettingsBackupManager.exportToJson()
            UIPasteboard.general.string = json
            let ok = UIAlertController(title: "Settings Exported", message: "JSON settings copied to clipboard.", preferredStyle: .alert)
            ok.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(ok, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Restore Settings from Clipboard", style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let json = UIPasteboard.general.string, !json.isEmpty else {
                let err = UIAlertController(title: "Restore Failed", message: "Clipboard does not contain JSON text.", preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(err, animated: true)
                return
            }

            do {
                try SettingsBackupManager.importFromJson(json)
                self.dpiPreviewCell?.configure(with: HeadUnitScreenConfig.shared)
                self.tableView.reloadData()
                self.onSettingsChanged?(.uiOnly)
                let ok = UIAlertController(title: "Settings Restored", message: "Preferences have been restored from clipboard.", preferredStyle: .alert)
                ok.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(ok, animated: true)
            } catch {
                let err = UIAlertController(title: "Restore Error", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(err, animated: true)
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentResetDefaultsAlert() {
        let alert = UIAlertController(
            title: "Reset All Settings",
            message: "Are you sure you want to reset all projection preferences to factory defaults? This action cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            SettingsBackupManager.resetToDefaults()
            self?.dpiPreviewCell?.configure(with: HeadUnitScreenConfig.shared)
            self?.tableView.reloadData()
            self?.onSettingsChanged?(.uiOnly)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - DpiPreviewCell

final class DpiPreviewCell: UITableViewCell {

    var onDpiChanged: ((SettingsViewController.ChangeImpact) -> Void)?

    private let previewView: DpiPreviewView = {
        let v = DpiPreviewView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 12
        v.clipsToBounds = true
        return v
    }()

    private let autoDpiLabel: UILabel = {
        let label = UILabel()
        label.text = "Auto DPI (Recommended)"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let autoDpiSwitch: UISwitch = {
        let s = UISwitch()
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let dpiValueLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        label.textAlignment = .center
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let dpiSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 100
        slider.maximumValue = 320
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    private let presetStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        selectionStyle = .none
        setupViews()
    }

    private func setupViews() {
        contentView.addSubview(previewView)
        contentView.addSubview(autoDpiLabel)
        contentView.addSubview(autoDpiSwitch)
        contentView.addSubview(dpiValueLabel)
        contentView.addSubview(dpiSlider)
        contentView.addSubview(presetStackView)

        let presets = [120, 160, 200, 240, 280]
        for p in presets {
            var config = UIButton.Configuration.tinted()
            config.title = "\(p)"
            config.cornerStyle = .capsule
            config.buttonSize = .mini
            let btn = UIButton(configuration: config)
            btn.addAction(UIAction { [weak self] _ in
                self?.applyDpi(val: p, isAuto: false)
            }, for: .touchUpInside)
            presetStackView.addArrangedSubview(btn)
        }

        autoDpiSwitch.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            if self.autoDpiSwitch.isOn {
                let rec = ProjectionSettings.recommendedDpiForCurrentDevice()
                self.applyDpi(val: rec, isAuto: true)
            } else {
                let val = Int((self.dpiSlider.value / 10.0).rounded()) * 10
                self.applyDpi(val: val, isAuto: false)
            }
        }, for: .valueChanged)

        dpiSlider.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let stepped = Int((self.dpiSlider.value / 10.0).rounded()) * 10
            self.dpiSlider.value = Float(stepped)
            self.applyDpi(val: stepped, isAuto: false)
        }, for: .valueChanged)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            previewView.heightAnchor.constraint(equalToConstant: 200),

            autoDpiLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 14),
            autoDpiLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            autoDpiSwitch.centerYAnchor.constraint(equalTo: autoDpiLabel.centerYAnchor),
            autoDpiSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            dpiValueLabel.topAnchor.constraint(equalTo: autoDpiLabel.bottomAnchor, constant: 10),
            dpiValueLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dpiValueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            dpiSlider.topAnchor.constraint(equalTo: dpiValueLabel.bottomAnchor, constant: 10),
            dpiSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dpiSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            presetStackView.topAnchor.constraint(equalTo: dpiSlider.bottomAnchor, constant: 12),
            presetStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            presetStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            presetStackView.heightAnchor.constraint(equalToConstant: 32),
            presetStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    func configure(with screenConfig: HeadUnitScreenConfig) {
        previewView.dpi = ProjectionSettings.effectiveDpi
        previewView.panelWidthPx = screenConfig.screenWidthPx > 0 ? screenConfig.screenWidthPx : 1920
        previewView.panelHeightPx = screenConfig.screenHeightPx > 0 ? screenConfig.screenHeightPx : 1080
        previewView.codecWidthPx = screenConfig.negotiatedWidth > 0 ? screenConfig.negotiatedWidth : 1920
        previewView.codecHeightPx = screenConfig.negotiatedHeight > 0 ? screenConfig.negotiatedHeight : 1080
        previewView.activeWidthPx = screenConfig.activeWidthPx
        previewView.activeHeightPx = screenConfig.activeHeightPx
        previewView.marginWidthPx = screenConfig.widthMargin
        previewView.marginHeightPx = screenConfig.heightMargin
        previewView.isRightHandDrive = (ProjectionSettings.driverPosition == .right)
        previewView.fitMode = ProjectionSettings.videoFitMode

        autoDpiSwitch.isOn = ProjectionSettings.isAutoDpi
        dpiSlider.value = Float(ProjectionSettings.effectiveDpi)
        updateDpiLabel()
        previewView.setNeedsDisplay()
    }

    func updateRightHandDrive(_ isRhd: Bool) {
        previewView.isRightHandDrive = isRhd
        previewView.setNeedsDisplay()
    }

    private func applyDpi(val: Int, isAuto: Bool) {
        let clamped = min(max(val, 100), 320)
        dpiSlider.value = Float(clamped)
        previewView.dpi = clamped
        autoDpiSwitch.isOn = isAuto

        if isAuto {
            ProjectionSettings.resetDpiToDefault()
            HeadUnitScreenConfig.shared.customDpi = nil
        } else {
            ProjectionSettings.isAutoDpi = false
            ProjectionSettings.dpi = clamped
            HeadUnitScreenConfig.shared.customDpi = clamped
        }

        updateDpiLabel()
        previewView.setNeedsDisplay()
        onDpiChanged?(.uiOnly)
    }

    private func updateDpiLabel() {
        let prefix = ProjectionSettings.isAutoDpi ? "Auto " : "Custom "
        let splitText = previewView.isCoolwalkSplitScreen ? "Coolwalk Split" : "Single Fullscreen"
        dpiValueLabel.text = "\(prefix)(\(previewView.dpi) DPI) • \(previewView.virtualWidthDp)×\(previewView.virtualHeightDp) dp (\(splitText))"
    }
}

