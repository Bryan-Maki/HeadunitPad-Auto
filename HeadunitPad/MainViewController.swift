//
//  MainViewController.swift
//  HeadunitPad
//
//  Main screen with connection controls
//

import UIKit
import AVFoundation
import CoreLocation

class MainViewController: UIViewController {

    // MARK: - Properties

    private let connectionManager = ConnectionManager.shared
    private let videoRenderer = H264VideoRendererView()
    private let audioPlayer = PCMAudioPlayer.shared
    private var videoWatchdogTimer: Timer?
    private var runningSinceTs: TimeInterval = 0
    private var lastVideoFrameTs: TimeInterval = 0
    private var hasReceivedFirstVideoFrame = false
    private var lastVideoRecoveryTs: TimeInterval = 0

    // MARK: - UI Components

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "HeadunitPad"
        label.font = .systemFont(ofSize: 48, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let videoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let touchOverlayView: TouchInputView = {
        let view = TouchInputView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Android Auto for iPad"
        label.font = .systemFont(ofSize: 20, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()


    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Ready to connect"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var connectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Wireless: Scan for Devices"
        config.image = UIImage(systemName: "wifi")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.buttonSize = .large

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var settingsButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "gearshape.fill")
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.35)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var floatingSettingsButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "gearshape.fill")
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.85)
        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.cornerRadius = 22
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var wirelessSetupButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Wireless Setup (QR / Bluetooth Bind)"
        config.image = UIImage(systemName: "qrcode")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.buttonSize = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(wirelessSetupButtonTapped), for: .touchUpInside)
        return button
    }()

    private let homeScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private let homeContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let directConnectContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.85)
        view.layer.cornerRadius = 14
        view.layer.borderWidth = 1.0
        view.layer.borderColor = UIColor.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let directIpLabel: UILabel = {
        let label = UILabel()
        label.text = "Direct Connect (Phone Hotspot IP)"
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let directIpTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "192.168.43.1"
        textField.text = NetworkAddresses.currentHotspotGatewayIpv4()
        textField.textAlignment = .center
        textField.font = .monospacedDigitSystemFont(ofSize: 17, weight: .bold)
        textField.backgroundColor = .tertiarySystemBackground
        textField.layer.cornerRadius = 8
        textField.keyboardType = .numbersAndPunctuation
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private lazy var directConnectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Direct Connect to this IP"
        config.image = UIImage(systemName: "arrow.right.circle.fill")
        config.imagePadding = 6
        config.cornerStyle = .medium
        config.baseBackgroundColor = .systemBlue

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(directConnectButtonTapped), for: .touchUpInside)
        return button
    }()

    private let orDividerLabel: UILabel = {
        let label = UILabel()
        label.text = "— or —"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var disconnectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Disconnect"
        config.cornerStyle = .large
        config.buttonSize = .large
        config.baseBackgroundColor = .systemRed

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(disconnectButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        HeadUnitScreenConfig.shared.videoFitMode = ProjectionSettings.videoFitMode
        setupUI()
        setupConstraints()
        connectionManager.delegate = self

        // Awake iOS 14+ Local Network permission dialog on launch
        Discovery.triggerLocalNetworkPermission()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        homeScrollView.addGestureRecognizer(tap)

        videoRenderer.onFrameDisplayed = { [weak self] in
            guard let self else { return }
            self.hasReceivedFirstVideoFrame = true
            self.lastVideoFrameTs = Date().timeIntervalSince1970
        }
        videoRenderer.onVideoSizeResolved = { [weak self] size in
            guard let self = self else { return }
            let w = Int(size.width)
            let h = Int(size.height)
            if w > 0 && h > 0 {
                print("MainViewController: Video size resolved from SPS: \(w)x\(h)")
                self.connectionManager.screenConfig.negotiatedWidth = w
                self.connectionManager.screenConfig.negotiatedHeight = h
                self.connectionManager.screenConfig.recalculateMargins()
                self.syncVideoAndTouchGeometry()
            }
        }
        TrackpadInputBridge.shared.setTouchSender { pointers, action, actionIndex in
            ConnectionManager.shared.sendTouchEvent(pointers: pointers, action: action, actionIndex: actionIndex)
        }
        HeadUnitScreenConfig.shared.onMarginsDivergedDetailed = { [weak self] left, top, right, bottom in
            self?.connectionManager.sendUpdateUiConfigRequest(left: left, top: top, right: right, bottom: bottom)
        }
        updateUIForConnectionState(.disconnected)
        syncVideoAndTouchGeometry()
    }

    private func syncVideoAndTouchGeometry() {
        let cfg = connectionManager.screenConfig
        let wMargin = (cfg.announcedWidthMargin >= 0) ? cfg.announcedWidthMargin : cfg.getWidthMargin()
        let hMargin = (cfg.announcedHeightMargin >= 0) ? cfg.announcedHeightMargin : cfg.getHeightMargin()

        videoRenderer.codecWidth = cfg.negotiatedWidth
        videoRenderer.codecHeight = cfg.negotiatedHeight
        videoRenderer.widthMargin = wMargin
        videoRenderer.heightMargin = hMargin
        videoRenderer.fitMode = cfg.videoFitMode

        touchOverlayView.surfaceSize = touchOverlayView.bounds.size
        touchOverlayView.screenConfig = cfg
        touchOverlayView.videoFitMode = cfg.videoFitMode
        touchOverlayView.codecWidth = cfg.negotiatedWidth
        touchOverlayView.codecHeight = cfg.negotiatedHeight
        touchOverlayView.widthMargin = wMargin
        touchOverlayView.heightMargin = hMargin
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        touchOverlayView.frame = videoContainerView.bounds
        touchOverlayView.isUserInteractionEnabled = true
        let screen = view.window?.screen ?? UIScreen.main
        let nativeScale = screen.nativeScale
        let w: Int
        let h: Int
        switch ProjectionSettings.orientation {
        case .landscape:
            w = Int((max(view.bounds.width, view.bounds.height) * nativeScale).rounded())
            h = Int((min(view.bounds.width, view.bounds.height) * nativeScale).rounded())
        case .portrait:
            w = Int((min(view.bounds.width, view.bounds.height) * nativeScale).rounded())
            h = Int((max(view.bounds.width, view.bounds.height) * nativeScale).rounded())
        case .system:
            w = Int((view.bounds.width * nativeScale).rounded())
            h = Int((view.bounds.height * nativeScale).rounded())
        }
        if w > 0 && h > 0 {
            _ = HeadUnitScreenConfig.shared.updateDimensions(width: w, height: h)
        }
        syncVideoAndTouchGeometry()
        if !videoContainerView.isHidden {
            videoContainerView.bringSubviewToFront(touchOverlayView)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let oldIsPortrait = HeadUnitScreenConfig.shared.isPortraitDisplay
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            let screen = self.view.window?.screen ?? UIScreen.main
            let nativeScale = screen.nativeScale
            let w: Int
            let h: Int
            switch ProjectionSettings.orientation {
            case .landscape:
                w = Int((max(size.width, size.height) * nativeScale).rounded())
                h = Int((min(size.width, size.height) * nativeScale).rounded())
            case .portrait:
                w = Int((min(size.width, size.height) * nativeScale).rounded())
                h = Int((max(size.width, size.height) * nativeScale).rounded())
            case .system:
                w = Int((size.width * nativeScale).rounded())
                h = Int((size.height * nativeScale).rounded())
            }
            if w > 0 && h > 0 {
                _ = HeadUnitScreenConfig.shared.updateDimensions(width: w, height: h)
            }
            self.syncVideoAndTouchGeometry()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            self.videoRenderer.applyGeometry()
            self.syncVideoAndTouchGeometry()
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyOrientationLock()
    }

    override var shouldAutorotate: Bool {
        return ProjectionSettings.orientation == .system
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch ProjectionSettings.orientation {
        case .landscape:
            return .landscape
        case .portrait:
            return .portrait
        case .system:
            return .all
        }
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        switch ProjectionSettings.orientation {
        case .landscape:
            return .landscapeRight
        case .portrait:
            return .portrait
        case .system:
            return .unknown
        }
    }

    private func applyOrientationLock() {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        touchOverlayView.isMultipleTouchEnabled = true

        let targetMask = supportedInterfaceOrientations
        if #available(iOS 16.0, *) {
            guard let window = view.window, let scene = window.windowScene else { return }
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMask)
            scene.requestGeometryUpdate(prefs) { error in
                print("MainViewController: Failed to apply orientation lock: \(error)")
            }
        } else {
            let orientation: UIInterfaceOrientation
            switch ProjectionSettings.orientation {
            case .landscape: orientation = .landscapeRight
            case .portrait: orientation = .portrait
            case .system: orientation = .unknown
            }
            if orientation != .unknown {
                UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    private func requestMicrophonePermissionIfNeeded() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                print("MainViewController: Microphone permission granted=\(granted)")
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                print("MainViewController: Microphone permission granted=\(granted)")
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        videoRenderer.isUserInteractionEnabled = false
        touchOverlayView.isUserInteractionEnabled = true

        videoContainerView.addSubview(videoRenderer)
        videoContainerView.addSubview(touchOverlayView)
        videoRenderer.translatesAutoresizingMaskIntoConstraints = false
        touchOverlayView.translatesAutoresizingMaskIntoConstraints = false

        directConnectContainer.addSubview(directIpLabel)
        directConnectContainer.addSubview(directIpTextField)
        directConnectContainer.addSubview(directConnectButton)

        homeContentView.addSubview(titleLabel)
        homeContentView.addSubview(subtitleLabel)
        homeContentView.addSubview(statusLabel)
        homeContentView.addSubview(directConnectContainer)
        homeContentView.addSubview(orDividerLabel)
        homeContentView.addSubview(connectButton)
        homeContentView.addSubview(wirelessSetupButton)
        homeContentView.addSubview(activityIndicator)
        homeContentView.addSubview(settingsButton)
        homeContentView.addSubview(disconnectButton)

        homeScrollView.addSubview(homeContentView)

        view.addSubview(videoContainerView)
        view.addSubview(homeScrollView)
        view.addSubview(floatingSettingsButton)

        NSLayoutConstraint.activate([
            videoRenderer.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            videoRenderer.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            videoRenderer.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            videoRenderer.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            touchOverlayView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            touchOverlayView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            touchOverlayView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            touchOverlayView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),
        ])

        touchOverlayView.onTouch = { pointers, action, actionIndex in
            if action == .DOWN || action == .UP || action == .POINTER_DOWN || action == .POINTER_UP || action == .CANCEL {
                print("MainViewController: Touch action=\(action) pointers=\(pointers.count) actionIndex=\(actionIndex)")
            }

            ConnectionManager.shared.sendTouchEvent(pointers: pointers, action: action, actionIndex: actionIndex)
        }

        videoContainerView.isHidden = true
        homeScrollView.isHidden = false
    }

    private let connectControlWidth: CGFloat = 340

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            videoContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            videoContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            homeScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            homeScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            homeScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            homeScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            homeContentView.leadingAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.leadingAnchor),
            homeContentView.trailingAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.trailingAnchor),
            homeContentView.topAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.topAnchor),
            homeContentView.bottomAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.bottomAnchor),
            homeContentView.widthAnchor.constraint(equalTo: homeScrollView.frameLayoutGuide.widthAnchor),

            // Title
            titleLabel.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.topAnchor, constant: 48),

            // Subtitle
            subtitleLabel.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),

            // Status
            statusLabel.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),

            // Direct Connect Container
            directConnectContainer.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            directConnectContainer.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            directConnectContainer.widthAnchor.constraint(equalToConstant: connectControlWidth),

            directIpLabel.topAnchor.constraint(equalTo: directConnectContainer.topAnchor, constant: 14),
            directIpLabel.leadingAnchor.constraint(equalTo: directConnectContainer.leadingAnchor, constant: 16),
            directIpLabel.trailingAnchor.constraint(equalTo: directConnectContainer.trailingAnchor, constant: -16),

            directIpTextField.topAnchor.constraint(equalTo: directIpLabel.bottomAnchor, constant: 8),
            directIpTextField.leadingAnchor.constraint(equalTo: directConnectContainer.leadingAnchor, constant: 16),
            directIpTextField.trailingAnchor.constraint(equalTo: directConnectContainer.trailingAnchor, constant: -16),
            directIpTextField.heightAnchor.constraint(equalToConstant: 42),

            directConnectButton.topAnchor.constraint(equalTo: directIpTextField.bottomAnchor, constant: 12),
            directConnectButton.leadingAnchor.constraint(equalTo: directConnectContainer.leadingAnchor, constant: 16),
            directConnectButton.trailingAnchor.constraint(equalTo: directConnectContainer.trailingAnchor, constant: -16),
            directConnectButton.bottomAnchor.constraint(equalTo: directConnectContainer.bottomAnchor, constant: -16),
            directConnectButton.heightAnchor.constraint(equalToConstant: 44),

            // Or Divider
            orDividerLabel.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            orDividerLabel.topAnchor.constraint(equalTo: directConnectContainer.bottomAnchor, constant: 16),

            // Auto-Scan Button
            connectButton.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            connectButton.topAnchor.constraint(equalTo: orDividerLabel.bottomAnchor, constant: 16),
            connectButton.widthAnchor.constraint(equalToConstant: connectControlWidth),
            connectButton.heightAnchor.constraint(equalToConstant: 48),

            // Wireless Setup / QR Pairing Button
            wirelessSetupButton.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            wirelessSetupButton.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 12),
            wirelessSetupButton.widthAnchor.constraint(equalToConstant: connectControlWidth),
            wirelessSetupButton.heightAnchor.constraint(equalToConstant: 44),

            // Disconnect Button
            disconnectButton.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            disconnectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 36),
            disconnectButton.widthAnchor.constraint(equalToConstant: 200),
            disconnectButton.heightAnchor.constraint(equalToConstant: 48),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: wirelessSetupButton.bottomAnchor, constant: 16),

            // Settings Button
            settingsButton.trailingAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            settingsButton.topAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.topAnchor, constant: 12),

            // Floating Settings Button (During projection)
            floatingSettingsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            floatingSettingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            floatingSettingsButton.widthAnchor.constraint(equalToConstant: 44),
            floatingSettingsButton.heightAnchor.constraint(equalToConstant: 44),

            homeContentView.bottomAnchor.constraint(greaterThanOrEqualTo: activityIndicator.bottomAnchor, constant: 48)
        ])
    }

    override var prefersStatusBarHidden: Bool {
        return connectionManager.state == .running
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return connectionManager.state == .running
    }

    // MARK: - UI Updates

    private func updateUIForConnectionState(_ state: ConnectionState) {
        let currentIp = NetworkAddresses.stationIpv4() ?? "No Wi-Fi"
        switch state {
        case .disconnected:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = false
            wirelessSetupButton.isEnabled = true
            connectionManager.screenConfig.clearCustomNegotiatedResolution()
            videoRenderer.reset()
            audioPlayer.reset()
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = "iPad IP: \(currentIp) | Ready to connect"
            statusLabel.textColor = .tertiaryLabel
            directConnectContainer.isHidden = false
            orDividerLabel.isHidden = false
            connectButton.isHidden = false
            connectButton.isEnabled = true
            updateConnectButtonTitle()
            if directIpTextField.text?.isEmpty ?? true {
                directIpTextField.text = NetworkAddresses.currentHotspotGatewayIpv4()
            }
            disconnectButton.isHidden = true
            activityIndicator.stopAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .discovering:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = true
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = "iPad IP: \(currentIp) | Scanning for phone hotspot / headunit..."
            statusLabel.textColor = .secondaryLabel
            directConnectContainer.isHidden = true
            orDividerLabel.isHidden = true
            connectButton.isHidden = true
            disconnectButton.isHidden = true
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .waitingForWirelessHelper:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = true
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = connectionManager.statusDetail
            statusLabel.textColor = .secondaryLabel
            directConnectContainer.isHidden = true
            orDividerLabel.isHidden = true
            connectButton.isHidden = true
            disconnectButton.isHidden = false
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .connecting:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = true
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = "Connecting to \(connectionManager.connectedDevice?.displayName ?? "Phone")..."
            statusLabel.textColor = .secondaryLabel
            directConnectContainer.isHidden = true
            orDividerLabel.isHidden = true
            connectButton.isHidden = true
            disconnectButton.isHidden = true
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .handshaking:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = true
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = "Handshaking with Android Auto..."
            statusLabel.textColor = .systemBlue
            directConnectContainer.isHidden = true
            orDividerLabel.isHidden = true
            connectButton.isHidden = true
            disconnectButton.isHidden = false
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .running:
            startVideoWatchdog()
            homeScrollView.isHidden = true
            videoContainerView.isHidden = false
            view.bringSubviewToFront(videoContainerView)
            floatingSettingsButton.isHidden = false
            view.bringSubviewToFront(floatingSettingsButton)
            wirelessSetupButton.isHidden = true
            activityIndicator.stopAnimating()
            syncVideoAndTouchGeometry()
            videoRenderer.applyGeometry()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .disconnecting:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = true
            audioPlayer.reset()
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = "Disconnecting..."
            statusLabel.textColor = .secondaryLabel
            directConnectContainer.isHidden = true
            orDividerLabel.isHidden = true
            connectButton.isHidden = true
            disconnectButton.isHidden = true
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .error(let message):
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            floatingSettingsButton.isHidden = true
            wirelessSetupButton.isHidden = false
            wirelessSetupButton.isEnabled = true
            audioPlayer.reset()
            settingsButton.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            statusLabel.isHidden = false
            statusLabel.text = connectionManager.statusDetail.isEmpty ? message : connectionManager.statusDetail
            statusLabel.textColor = .systemRed
            directConnectContainer.isHidden = false
            orDividerLabel.isHidden = false
            connectButton.isHidden = false
            connectButton.isEnabled = true
            updateConnectButtonTitle()
            disconnectButton.isHidden = true
            activityIndicator.stopAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    private func updateConnectButtonTitle() {
        let title: String
        switch ProjectionSettings.connectionMode {
        case .nativeWpp:
            title = "Auto Scan (WPP & Hotspot)"
        case .hotspotServer:
            title = "Scan Headunit Server (Port 5277)"
        case .manualIp:
            title = "Direct Connect (Port 5277)"
        }
        connectButton.configuration?.title = title
    }

    private func startVideoWatchdog() {
        if videoWatchdogTimer != nil {
            return
        }

        runningSinceTs = Date().timeIntervalSince1970
        lastVideoFrameTs = 0
        hasReceivedFirstVideoFrame = false
        lastVideoRecoveryTs = 0

        videoWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkVideoWatchdog()
        }
    }

    private func stopVideoWatchdog() {
        videoWatchdogTimer?.invalidate()
        videoWatchdogTimer = nil
        runningSinceTs = 0
        lastVideoFrameTs = 0
        hasReceivedFirstVideoFrame = false
        lastVideoRecoveryTs = 0
    }

    private func checkVideoWatchdog() {
        guard connectionManager.state == .running else {
            return
        }

        connectionManager.updateNightMode(userInterfaceStyle: traitCollection.userInterfaceStyle)

        let now = Date().timeIntervalSince1970
        if !hasReceivedFirstVideoFrame {
            if now - runningSinceTs > 3.0, now - lastVideoRecoveryTs > 1.5 {
                lastVideoRecoveryTs = now
                print("MainViewController: Video watchdog requesting first-frame recovery")
                connectionManager.requestVideoRecovery()
            }
            return
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *) {
            if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
                connectionManager.updateNightMode(userInterfaceStyle: traitCollection.userInterfaceStyle)
            }
        }
    }

    // MARK: - Actions

    @objc private func directConnectButtonTapped() {
        view.endEditing(true)
        let rawIp = directIpTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetIp = (rawIp?.isEmpty == false) ? rawIp! : NetworkAddresses.currentHotspotGatewayIpv4()
        print("MainViewController: Direct connecting to \(targetIp):\(Discovery.headunitPort)")
        connectionManager.connect(to: targetIp, port: Discovery.headunitPort)
    }

    @objc private func connectButtonTapped() {
        view.endEditing(true)
        if ProjectionSettings.connectionMode == .manualIp {
            directConnectButtonTapped()
        } else {
            connectionManager.startDiscovery()
        }
    }

    @objc private func disconnectButtonTapped() {
        connectionManager.screenConfig.clearCustomNegotiatedResolution()
        videoRenderer.reset()
        connectionManager.disconnect()
    }

    @objc private func settingsButtonTapped() {
        presentSettingsMenu()
    }

    private func presentSettingsMenu() {
        let orientation = ProjectionSettings.orientation.title
        let resolution = ProjectionSettings.videoResolution.title(for: ProjectionSettings.orientation)
        let fps = ProjectionSettings.fpsLimit.title
        let effectiveFps = ProjectionSettings.effectiveFpsLimit.title
        let gpsSource = ProjectionSettings.gpsSource.title
        let dpi = ProjectionSettings.dpi
        let effectiveDpi = ProjectionSettings.effectiveDpi
        let connectionMode = ProjectionSettings.connectionMode.title
        let autoReconnect = ProjectionSettings.autoReconnect ? "On" : "Off"
        let codec = ProjectionSettings.videoCodecPreference.title
        let audioCodec = ProjectionSettings.audioCodecPreference.title
        let audioTarget = ProjectionSettings.audioOutputTarget.title

        let alert = UIAlertController(
            title: "Settings",
            message: "Changes apply on next connection.\nMode: \(connectionMode)\nAuto reconnect: \(autoReconnect)\nVideo: \(codec)\nAudio Codec: \(audioCodec)\nAudio Output: \(audioTarget)\nOrientation: \(orientation)\nResolution: \(resolution)\nFPS: \(fps)\(fps != effectiveFps ? " (effective: \(effectiveFps))" : "")\nDPI: \(dpi)\(dpi != effectiveDpi ? " (effective: \(effectiveDpi))" : "")\nFit: \(ProjectionSettings.videoFitMode.title)\nPosition: \(ProjectionSettings.driverPosition == .left ? "LHD" : "RHD")\nGPS: \(gpsSource)",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Connection Mode", style: .default) { [weak self] _ in
            self?.presentConnectionModeMenu()
        })

        alert.addAction(UIAlertAction(title: "Wireless Setup (QR / Bluetooth Bind)", style: .default) { [weak self] _ in
            self?.presentWirelessSetupModal()
        })

        let autoReconnectTitle = ProjectionSettings.autoReconnect ? "Auto Reconnect: On" : "Auto Reconnect: Off"
        alert.addAction(UIAlertAction(title: autoReconnectTitle, style: .default) { [weak self] _ in
            ProjectionSettings.autoReconnect.toggle()
            self?.updateConnectButtonTitle()
            self?.presentSettingsMenu()
        })

        alert.addAction(UIAlertAction(title: "Video Codec: \(codec)", style: .default) { [weak self] _ in
            self?.presentCodecMenu()
        })

        alert.addAction(UIAlertAction(title: "Audio Codec: \(audioCodec)", style: .default) { [weak self] _ in
            self?.presentAudioCodecMenu()
        })

        alert.addAction(UIAlertAction(title: "Audio Output: \(audioTarget)", style: .default) { [weak self] _ in
            self?.presentAudioOutputTargetMenu()
        })

        alert.addAction(UIAlertAction(title: "Display Fit Mode: \(ProjectionSettings.videoFitMode.title)", style: .default) { [weak self] _ in
            self?.presentFitModeMenu()
        })

        alert.addAction(UIAlertAction(title: "Driving Position: \(ProjectionSettings.driverPosition == .left ? "LHD (Left)" : "RHD (Right)")", style: .default) { [weak self] _ in
            self?.presentDrivingPositionMenu()
        })

        alert.addAction(UIAlertAction(title: "Orientation", style: .default) { [weak self] _ in
            self?.presentOrientationMenu()
        })

        alert.addAction(UIAlertAction(title: "Night Mode: \(ProjectionSettings.nightMode.title)", style: .default) { [weak self] _ in
            self?.presentNightModeMenu()
        })

        alert.addAction(UIAlertAction(title: "Resolution: \(ProjectionSettings.videoResolution.title(for: ProjectionSettings.orientation))", style: .default) { [weak self] _ in
            self?.presentResolutionMenu()
        })

        alert.addAction(UIAlertAction(title: "FPS: \(ProjectionSettings.fpsLimit.title)", style: .default) { [weak self] _ in
            self?.presentFpsMenu()
        })

        let dpiModeStr = ProjectionSettings.isAutoDpi ? "Auto (\(ProjectionSettings.effectiveDpi))" : "\(ProjectionSettings.dpi)"
        alert.addAction(UIAlertAction(title: "DPI (UI Scale): \(dpiModeStr)", style: .default) { [weak self] _ in
            self?.presentDpiPreviewModal()
        })

        let isCellular = ProjectionSettings.supportsCellularIpad()
        let currentGpsTitle = isCellular
            ? "GPS Source: \(ProjectionSettings.gpsSource.title)"
            : "GPS Source: Phone only (Wi-Fi iPad)"
        let gpsAction = UIAlertAction(title: currentGpsTitle, style: .default) { [weak self] _ in
            if isCellular {
                self?.presentGpsMenu()
            } else {
                let infoAlert = UIAlertController(
                    title: "GPS Source",
                    message: "This iPad does not have a cellular GPS hardware module. Android Auto will use your phone's GPS for precise navigation.",
                    preferredStyle: .alert
                )
                infoAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(infoAlert, animated: true)
            }
        }
        alert.addAction(gpsAction)

        alert.addAction(UIAlertAction(title: "Diagnostics", style: .default) { [weak self] _ in
            self?.presentDiagnostics()
        })

        if connectionManager.state == .running {
            alert.addAction(UIAlertAction(title: "Connection Details", style: .default) { [weak self] _ in
                self?.presentConnectionDetails()
            })
            alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { [weak self] _ in
                self?.connectionManager.disconnect()
            })
        }

        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentConnectionModeMenu() {
        let alert = UIAlertController(title: "Connection Mode", message: nil, preferredStyle: .actionSheet)

        for option in ProjectionConnectionMode.allCases {
            let title = option == ProjectionSettings.connectionMode ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.connectionMode = option
                self?.updateConnectButtonTitle()
                self?.updateUIForConnectionState(self?.connectionManager.state ?? .disconnected)
                self?.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentResolutionMenu() {
        let alert = UIAlertController(title: "Resolution", message: nil, preferredStyle: .actionSheet)

        let orientation = ProjectionSettings.orientation
        let options = ProjectionSettings.availableResolutions(for: orientation)

        for option in options {
            let optionTitle = option.title(for: orientation)
            let title = option == ProjectionSettings.videoResolution ? "\(optionTitle) (Current)" : optionTitle
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.videoResolution = option
                self?.connectionManager.screenConfig.clearCustomNegotiatedResolution()
                self?.connectionManager.screenConfig.recalculateMargins()
                self?.syncVideoAndTouchGeometry()
                self?.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentOrientationMenu() {
        let alert = UIAlertController(title: "Orientation", message: nil, preferredStyle: .actionSheet)

        for option in ProjectionOrientation.allCases {
            let title = option == ProjectionSettings.orientation ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                let oldIsPortrait = HeadUnitScreenConfig.shared.isPortraitDisplay
                ProjectionSettings.orientation = option
                self.applyOrientationLock()
                let screen = self.view.window?.screen ?? UIScreen.main
                let nativeScale = screen.nativeScale
                let w: Int
                let h: Int
                switch option {
                case .landscape:
                    w = Int((max(self.view.bounds.width, self.view.bounds.height) * nativeScale).rounded())
                    h = Int((min(self.view.bounds.width, self.view.bounds.height) * nativeScale).rounded())
                case .portrait:
                    w = Int((min(self.view.bounds.width, self.view.bounds.height) * nativeScale).rounded())
                    h = Int((max(self.view.bounds.width, self.view.bounds.height) * nativeScale).rounded())
                case .system:
                    w = Int((self.view.bounds.width * nativeScale).rounded())
                    h = Int((self.view.bounds.height * nativeScale).rounded())
                }
                _ = HeadUnitScreenConfig.shared.updateDimensions(width: w, height: h)
                self.videoRenderer.applyGeometry()
                self.syncVideoAndTouchGeometry()
                self.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentNightModeMenu() {
        let alert = UIAlertController(title: "Night Mode", message: nil, preferredStyle: .actionSheet)

        for option in NightModeSetting.allCases {
            let title = option == ProjectionSettings.nightMode ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                ProjectionSettings.nightMode = option
                self.connectionManager.updateNightMode(userInterfaceStyle: self.traitCollection.userInterfaceStyle)
                self.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentFpsMenu() {
        let alert = UIAlertController(title: "FPS", message: nil, preferredStyle: .actionSheet)

        for option in [ProjectionFpsLimit.fps30, .fps60] {
            let title = option == ProjectionSettings.fpsLimit ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.fpsLimit = option
                self?.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentCodecMenu() {
        let alert = UIAlertController(title: "Video Codec", message: "Hardware decoding preference", preferredStyle: .actionSheet)

        for option in VideoCodecPreference.allCases {
            let title = option == ProjectionSettings.videoCodecPreference ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.videoCodecPreference = option
                self?.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentAudioCodecMenu() {
        let alert = UIAlertController(title: "Audio Codec", message: "Audio decoding preference", preferredStyle: .actionSheet)

        for option in AudioCodecPreference.allCases {
            let title = option == ProjectionSettings.audioCodecPreference ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.audioCodecPreference = option
                self?.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentAudioOutputTargetMenu() {
        let alert = UIAlertController(
            title: "Audio Output Target",
            message: "Choose where Android Auto audio (music & navigation guidance) should play.\n\n• iPad: Play audio on iPad speakers or Bluetooth connected to iPad.\n• Phone: Phone original device keeps media/guidance audio (e.g. phone speakers or car Bluetooth connected to phone).",
            preferredStyle: .actionSheet
        )

        for target in AudioOutputTarget.allCases {
            let title = (target == ProjectionSettings.audioOutputTarget) ? "\(target.title) (Current)" : target.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                ProjectionSettings.audioOutputTarget = target
                if !target.isAudioSinkEnabled {
                    self.audioPlayer.reset()
                    NowPlayingCoordinator.shared.deactivate()
                }
                if self.connectionManager.state == .running {
                    self.connectionManager.reconnectForSettingsChange()
                }
                self.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }


    private func presentGpsMenu() {
        let alert = UIAlertController(title: "GPS Source", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: ProjectionGpsSource.phone == ProjectionSettings.gpsSource ? "Use Phone GPS (Current)" : "Use Phone GPS", style: .default) { [weak self] _ in
            ProjectionSettings.gpsSource = .phone
            self?.presentSettingsMenu()
        })

        let ipadActionTitle = ProjectionGpsSource.ipad == ProjectionSettings.gpsSource ? "Use iPad GPS (Current)" : "Use iPad GPS"
        let ipadAction = UIAlertAction(title: ipadActionTitle, style: .default) { [weak self] _ in
            ProjectionSettings.gpsSource = .ipad
            self?.connectionManager.requestLocationPermissionIfNeeded()
            self?.presentSettingsMenu()
        }
        ipadAction.isEnabled = ProjectionSettings.supportsCellularIpad()
        alert.addAction(ipadAction)

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentFitModeMenu() {
        let alert = UIAlertController(title: "Display Fit Mode", message: "Choose how Android Auto fits the iPad display.", preferredStyle: .actionSheet)

        let modes: [VideoFitMode] = [.fillMargin, .fit, .stretch]
        for mode in modes {
            let isCurrent = mode == ProjectionSettings.videoFitMode
            let title = isCurrent ? "\(mode.title) (Current)" : mode.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.videoFitMode = mode
                HeadUnitScreenConfig.shared.videoFitMode = mode
                HeadUnitScreenConfig.shared.recalculate()
                HeadUnitScreenConfig.shared.checkAndNotifyMarginDivergence()
                self?.presentSettingsMenu()
            })
        }

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })
        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentDrivingPositionMenu() {
        let alert = UIAlertController(title: "Driving Position", message: "Sets the position of the Coolwalk navigation rail.", preferredStyle: .actionSheet)

        let leftTitle = ProjectionSettings.driverPosition == .left ? "Left-Hand Drive (LHD) (Current)" : "Left-Hand Drive (LHD)"
        alert.addAction(UIAlertAction(title: leftTitle, style: .default) { [weak self] _ in
            ProjectionSettings.driverPosition = .left
            self?.presentSettingsMenu()
        })

        let rightTitle = ProjectionSettings.driverPosition == .right ? "Right-Hand Drive (RHD) (Current)" : "Right-Hand Drive (RHD)"
        alert.addAction(UIAlertAction(title: rightTitle, style: .default) { [weak self] _ in
            ProjectionSettings.driverPosition = .right
            self?.presentSettingsMenu()
        })

        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })
        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentDpiPreviewModal() {
        let previewVC = UIViewController()
        previewVC.view.backgroundColor = .systemBackground
        previewVC.title = "Coolwalk DPI Preview"

        let previewView = DpiPreviewView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.dpi = ProjectionSettings.effectiveDpi
        let screenConfig = HeadUnitScreenConfig.shared
        previewView.panelWidthPx = screenConfig.screenWidthPx
        previewView.panelHeightPx = screenConfig.screenHeightPx
        previewView.codecWidthPx = screenConfig.codecWidthPx
        previewView.codecHeightPx = screenConfig.codecHeightPx
        previewView.activeWidthPx = screenConfig.activeWidthPx
        previewView.activeHeightPx = screenConfig.activeHeightPx
        previewView.marginWidthPx = screenConfig.widthMargin
        previewView.marginHeightPx = screenConfig.heightMargin
        previewView.isRightHandDrive = ProjectionSettings.driverPosition == .right
        previewView.fitMode = ProjectionSettings.videoFitMode

        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = Float(ProjectionSettings.minDpi)
        slider.maximumValue = Float(ProjectionSettings.maxDpi)
        slider.value = Float(ProjectionSettings.effectiveDpi)

        let dpiLabel = UILabel()
        dpiLabel.translatesAutoresizingMaskIntoConstraints = false
        let initialPrefix = ProjectionSettings.isAutoDpi ? "Auto " : "Custom "
        dpiLabel.text = "DPI: \(initialPrefix)(\(ProjectionSettings.effectiveDpi))  (\(previewView.virtualWidthDp)×\(previewView.virtualHeightDp) dp)"
        dpiLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .bold)
        dpiLabel.textAlignment = .center

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Done", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)

        let presetStack = UIStackView()
        presetStack.axis = .horizontal
        presetStack.spacing = 8
        presetStack.distribution = .fillEqually
        presetStack.translatesAutoresizingMaskIntoConstraints = false

        let updateDpiBlock: (Int, Bool) -> Void = { [weak self, weak slider, weak previewView, weak dpiLabel] val, isAuto in
            guard let slider, let previewView, let dpiLabel else { return }
            let clamped = min(max(val, ProjectionSettings.minDpi), ProjectionSettings.maxDpi)
            slider.value = Float(clamped)
            previewView.dpi = clamped
            let prefix = isAuto ? "Auto " : "Custom "
            dpiLabel.text = "DPI: \(prefix)(\(clamped))  (\(previewView.virtualWidthDp)×\(previewView.virtualHeightDp) dp)"
            if isAuto {
                ProjectionSettings.resetDpiToDefault()
                self?.connectionManager.screenConfig.customDpi = nil
            } else {
                ProjectionSettings.isAutoDpi = false
                ProjectionSettings.dpi = clamped
                self?.connectionManager.screenConfig.customDpi = clamped
            }
            previewView.setNeedsDisplay()
        }

        var autoConfig = UIButton.Configuration.filled()
        autoConfig.title = "Auto (\(ProjectionSettings.recommendedDpiForCurrentDevice()))"
        autoConfig.cornerStyle = .capsule
        autoConfig.buttonSize = .mini
        let autoBtn = UIButton(configuration: autoConfig)
        autoBtn.addAction(UIAction { _ in
            let rec = ProjectionSettings.recommendedDpiForCurrentDevice()
            updateDpiBlock(rec, true)
        }, for: .touchUpInside)
        presetStack.addArrangedSubview(autoBtn)

        let presets = [120, 160, 200, 240, 280]
        for p in presets {
            var btnConfig = UIButton.Configuration.tinted()
            btnConfig.title = "\(p)"
            btnConfig.cornerStyle = .capsule
            btnConfig.buttonSize = .mini
            let btn = UIButton(configuration: btnConfig)
            btn.addAction(UIAction { _ in
                updateDpiBlock(p, false)
            }, for: .touchUpInside)
            presetStack.addArrangedSubview(btn)
        }

        previewVC.view.addSubview(previewView)
        previewVC.view.addSubview(dpiLabel)
        previewVC.view.addSubview(slider)
        previewVC.view.addSubview(presetStack)
        previewVC.view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: previewVC.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: previewVC.view.trailingAnchor, constant: -20),

            previewView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            previewView.leadingAnchor.constraint(equalTo: previewVC.view.leadingAnchor, constant: 20),
            previewView.trailingAnchor.constraint(equalTo: previewVC.view.trailingAnchor, constant: -20),
            previewView.heightAnchor.constraint(equalToConstant: 240),

            dpiLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 16),
            dpiLabel.centerXAnchor.constraint(equalTo: previewVC.view.centerXAnchor),

            slider.topAnchor.constraint(equalTo: dpiLabel.bottomAnchor, constant: 10),
            slider.leadingAnchor.constraint(equalTo: previewVC.view.leadingAnchor, constant: 36),
            slider.trailingAnchor.constraint(equalTo: previewVC.view.trailingAnchor, constant: -36),

            presetStack.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 12),
            presetStack.leadingAnchor.constraint(equalTo: previewVC.view.leadingAnchor, constant: 36),
            presetStack.trailingAnchor.constraint(equalTo: previewVC.view.trailingAnchor, constant: -36),
            presetStack.heightAnchor.constraint(equalToConstant: 32)
        ])

        slider.addAction(UIAction { [weak slider] _ in
            guard let slider else { return }
            updateDpiBlock(Int(slider.value), false)
        }, for: .valueChanged)

        closeButton.addAction(UIAction { [weak previewVC] _ in
            previewVC?.dismiss(animated: true)
        }, for: .touchUpInside)

        let nav = UINavigationController(rootViewController: previewVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func presentConnectionDetails() {
        let device = connectionManager.connectedDevice
        let details = [
            "State: \(connectionManager.state.description)",
            "Status: \(connectionManager.statusDetail)",
            "Device: \(device?.displayName ?? "Unknown")",
            "IP: \(device?.ip ?? "Unknown")",
            "Port: \(device?.port ?? 0)"
        ].joined(separator: "\n")

        let alert = UIAlertController(title: "Connection", message: details, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    private func presentDiagnostics() {
        let alert = UIAlertController(
            title: "Diagnostics",
            message: combinedDiagnosticLines().joined(separator: "\n"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        alert.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in
            UIPasteboard.general.string = self?.combinedDiagnosticLines().joined(separator: "\n")
        })
        present(alert, animated: true)
    }


    private func combinedDiagnosticLines() -> [String] {
        connectionManager.diagnosticLines()
            + [""]
            + videoRenderer.diagnosticLines()
    }

    private func configurePopoverSource(for alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            let src = (connectionManager.state == .running) ? floatingSettingsButton : settingsButton
            popover.sourceView = src
            popover.sourceRect = src.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
    }

    @objc private func wirelessSetupButtonTapped() {
        presentWirelessSetupModal()
    }

    private func presentWirelessSetupModal() {
        let setupVC = UIViewController()
        setupVC.title = "Wireless AA Setup & Pair"
        setupVC.view.backgroundColor = .systemBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        setupVC.view.addSubview(scrollView)

        let hintLabel = UILabel()
        hintLabel.text = "Scan this QR code with your Android phone's Camera or Google Lens to configure Android Auto wireless connection, or customize credentials below."
        hintLabel.font = .systemFont(ofSize: 14, weight: .regular)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let qrImageView = UIImageView()
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 12
        qrImageView.layer.masksToBounds = true
        qrImageView.layer.borderWidth = 1
        qrImageView.layer.borderColor = UIColor.separator.cgColor
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let ssidField = UITextField()
        ssidField.borderStyle = .roundedRect
        ssidField.placeholder = "Wi-Fi SSID (e.g. AndroidAuto-Hotspot)"
        ssidField.text = ProjectionSettings.wifiSsid.isEmpty ? (NetworkAddresses.currentWifiSsid() ?? "AndroidAuto-Headunit") : ProjectionSettings.wifiSsid

        let passField = UITextField()
        passField.borderStyle = .roundedRect
        passField.placeholder = "Wi-Fi Password / Passkey"
        passField.text = ProjectionSettings.wifiPasskey.isEmpty ? "12345678" : ProjectionSettings.wifiPasskey

        let bssidField = UITextField()
        bssidField.borderStyle = .roundedRect
        bssidField.placeholder = "BSSID (e.g. 02:00:00:00:00:00)"
        bssidField.text = ProjectionSettings.wifiBssid.isEmpty ? "02:00:00:00:00:00" : ProjectionSettings.wifiBssid

        let btMacField = UITextField()
        btMacField.borderStyle = .roundedRect
        btMacField.placeholder = "Bluetooth MAC (e.g. AA:BB:CC:DD:EE:FF)"
        btMacField.text = ProjectionSettings.bluetoothMac.isEmpty ? "AA:BB:CC:DD:EE:FF" : ProjectionSettings.bluetoothMac

        let currentIp = NetworkAddresses.stationIpv4() ?? "192.168.43.2"
        let ipLabel = UILabel()
        ipLabel.text = "iPad IP: \(currentIp)  |  WPP Port: 5299  |  AAP: 5288"
        ipLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        ipLabel.textColor = .secondaryLabel
        ipLabel.textAlignment = .center

        func updateQr() {
            let s = ssidField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let p = passField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let b = bssidField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bt = btMacField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let uri = ProjectionDeepLink.generateUri(
                ssid: s.isEmpty ? "AndroidAuto-Headunit" : s,
                passphrase: p.isEmpty ? "12345678" : p,
                ipAddress: currentIp,
                port: 5299,
                bssid: b.isEmpty ? "02:00:00:00:00:00" : b,
                bluetoothMac: bt.isEmpty ? "AA:BB:CC:DD:EE:FF" : bt
            )
            qrImageView.image = QrCodeGenerator.generateQrCode(content: uri, size: 240)
        }
        updateQr()

        [ssidField, passField, bssidField, btMacField].forEach { tf in
            tf.font = .systemFont(ofSize: 14)
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
            tf.addAction(UIAction { _ in updateQr() }, for: .editingChanged)
        }

        func makeRow(label: String, field: UITextField) -> UIView {
            let container = UIStackView()
            container.axis = .vertical
            container.spacing = 4
            let lbl = UILabel()
            lbl.text = label
            lbl.font = .systemFont(ofSize: 12, weight: .semibold)
            lbl.textColor = .secondaryLabel
            container.addArrangedSubview(lbl)
            container.addArrangedSubview(field)
            return container
        }

        stackView.addArrangedSubview(makeRow(label: "Wi-Fi SSID", field: ssidField))
        stackView.addArrangedSubview(makeRow(label: "Wi-Fi Password", field: passField))
        stackView.addArrangedSubview(makeRow(label: "Wi-Fi BSSID (MAC)", field: bssidField))
        stackView.addArrangedSubview(makeRow(label: "Bluetooth MAC", field: btMacField))
        stackView.addArrangedSubview(ipLabel)

        contentView.addSubview(hintLabel)
        contentView.addSubview(qrImageView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: setupVC.view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: setupVC.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: setupVC.view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: setupVC.view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            hintLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            qrImageView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 16),
            qrImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 220),
            qrImageView.heightAnchor.constraint(equalToConstant: 220),

            stackView.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        setupVC.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save & Done", style: .done, target: nil, action: nil)
        setupVC.navigationItem.rightBarButtonItem?.primaryAction = UIAction { [weak setupVC, weak ssidField, weak passField, weak bssidField, weak btMacField] _ in
            if let s = ssidField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                ProjectionSettings.wifiSsid = s
            }
            if let p = passField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                ProjectionSettings.wifiPasskey = p
            }
            if let b = bssidField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                ProjectionSettings.wifiBssid = b
            }
            if let bt = btMacField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                ProjectionSettings.bluetoothMac = bt
            }
            setupVC?.dismiss(animated: true)
        }

        let nav = UINavigationController(rootViewController: setupVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

}

// MARK: - ConnectionManagerDelegate

extension MainViewController: ConnectionManagerDelegate {
    func connectionManager(_ manager: ConnectionManager, didChangeState state: ConnectionState) {
        updateUIForConnectionState(state)
    }

    func connectionManager(_ manager: ConnectionManager, didUpdateStatus status: String) {
        switch manager.state {
        case .disconnected, .discovering, .waitingForWirelessHelper, .connecting, .handshaking, .disconnecting, .error:
            statusLabel.text = status
        case .running:
            break
        }
    }

    func connectionManager(_ manager: ConnectionManager, didDiscoverDevice device: DiscoveredDevice) {
        if manager.discoveredDevices.count == 1 {
            statusLabel.text = "Found: \(device.displayName)"
            statusLabel.textColor = .systemBlue
        }

        let alert = UIAlertController(title: "Device Found",
                                      message: "Would you like to connect to \(device.displayName)?",
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            self?.connectionManager.connect(to: device)
        })

        alert.addAction(UIAlertAction(title: "Continue Scanning", style: .cancel))

        present(alert, animated: true)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveVideoData data: Data) {
        videoRenderer.enqueueAnnexBFrame(data)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8) {
        audioPlayer.playPCM(data, on: channel)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool) {
        audioPlayer.playAudio(data, on: channel, isAac: isAac)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveAudioCodecConfig data: Data, on channel: UInt8) {
        audioPlayer.configureCodec(channel: channel, csd: data)
    }
}
