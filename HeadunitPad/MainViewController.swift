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

    private let connectionManager = ConnectionManager()
    private let videoRenderer = H264VideoRendererView()
    private let audioPlayer = PCMAudioPlayer()
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

    private lazy var floatingDisconnectButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark.circle.fill")
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.4)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(floatingDisconnectButtonTapped), for: .touchUpInside)
        return button
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
        setupUI()
        setupConstraints()
        connectionManager.delegate = self

        // Awake iOS 14+ Local Network permission dialog on launch
        Discovery.triggerLocalNetworkPermission()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        videoRenderer.onFrameDisplayed = { [weak self] in
            guard let self else { return }
            self.hasReceivedFirstVideoFrame = true
            self.lastVideoFrameTs = Date().timeIntervalSince1970
        }
        TrackpadInputBridge.shared.setTouchSender { [weak self] pointers, action, actionIndex in
            self?.connectionManager.sendTouchEvent(pointers: pointers, action: action, actionIndex: actionIndex)
        }
        HeadUnitScreenConfig.shared.onMarginsDivergedDetailed = { [weak self] left, top, right, bottom in
            self?.connectionManager.sendUpdateUiConfigRequest(left: left, top: top, right: right, bottom: bottom)
        }
        updateUIForConnectionState(.disconnected)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let screen = view.window?.screen ?? UIScreen.main
        let screenBounds = screen.bounds
        let nativeScale = screen.nativeScale
        let landW = Int((max(screenBounds.width, screenBounds.height) * nativeScale).rounded())
        let landH = Int((min(screenBounds.width, screenBounds.height) * nativeScale).rounded())
        if landW > 0 && landH > 0 {
            _ = HeadUnitScreenConfig.shared.updateDimensions(width: landW, height: landH)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            let screen = self.view.window?.screen ?? UIScreen.main
            let nativeScale = screen.nativeScale
            let landW = Int((max(size.width, size.height) * nativeScale).rounded())
            let landH = Int((min(size.width, size.height) * nativeScale).rounded())
            _ = HeadUnitScreenConfig.shared.updateDimensions(width: landW, height: landH)
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyOrientationLock()
    }

    override var shouldAutorotate: Bool {
        return false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch ProjectionSettings.orientation {
        case .landscape:
            return .landscape
        case .portrait:
            return .portrait
        }
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        switch ProjectionSettings.orientation {
        case .landscape:
            return .landscapeRight
        case .portrait:
            return .portrait
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
            let orientation: UIInterfaceOrientation = ProjectionSettings.orientation == .portrait ? .portrait : .landscapeRight
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
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
        videoContainerView.addSubview(floatingDisconnectButton)
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
        homeContentView.addSubview(activityIndicator)
        homeContentView.addSubview(settingsButton)
        homeContentView.addSubview(disconnectButton)

        homeScrollView.addSubview(homeContentView)

        view.addSubview(videoContainerView)
        view.addSubview(homeScrollView)

        NSLayoutConstraint.activate([
            videoRenderer.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            videoRenderer.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            videoRenderer.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            videoRenderer.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            touchOverlayView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            touchOverlayView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            touchOverlayView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            touchOverlayView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            floatingDisconnectButton.topAnchor.constraint(equalTo: videoContainerView.safeAreaLayoutGuide.topAnchor, constant: 12),
            floatingDisconnectButton.leadingAnchor.constraint(equalTo: videoContainerView.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            floatingDisconnectButton.widthAnchor.constraint(equalToConstant: 44),
            floatingDisconnectButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        touchOverlayView.onTouch = { [weak self] pointers, action, actionIndex in
            guard let self = self else { return }
            var mappedPointers: [(id: Int, x: Int, y: Int)] = []
            for pointer in pointers {
                let mapped = self.mapTouchPointToAa(pointer.point)
                mappedPointers.append((id: pointer.id, x: mapped.x, y: mapped.y))
            }

            if action == .DOWN || action == .UP || action == .POINTER_DOWN || action == .POINTER_UP || action == .CANCEL {
                print("MainViewController: Touch action=\(action) pointers=\(mappedPointers.count) actionIndex=\(actionIndex)")
            }

            self.connectionManager.sendTouchEvent(pointers: mappedPointers, action: action, actionIndex: actionIndex)
        }

        let twoFingerDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerDoubleTap))
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.numberOfTapsRequired = 2
        touchOverlayView.addGestureRecognizer(twoFingerDoubleTap)

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
            directConnectContainer.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 28),
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
            directConnectButton.bottomAnchor.constraint(equalTo: directConnectContainer.bottomAnchor, constant: -14),
            directConnectButton.heightAnchor.constraint(equalToConstant: 44),

            // Or Divider
            orDividerLabel.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            orDividerLabel.topAnchor.constraint(equalTo: directConnectContainer.bottomAnchor, constant: 16),

            // Auto-Scan Button
            connectButton.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            connectButton.topAnchor.constraint(equalTo: orDividerLabel.bottomAnchor, constant: 16),
            connectButton.widthAnchor.constraint(equalToConstant: connectControlWidth),
            connectButton.heightAnchor.constraint(equalToConstant: 48),

            // Disconnect Button
            disconnectButton.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            disconnectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 36),
            disconnectButton.widthAnchor.constraint(equalToConstant: 200),
            disconnectButton.heightAnchor.constraint(equalToConstant: 48),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20),

            // Settings Button
            settingsButton.trailingAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            settingsButton.topAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.topAnchor, constant: 12),

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
            videoContainerView.bringSubviewToFront(touchOverlayView)
            videoContainerView.bringSubviewToFront(floatingDisconnectButton)
            activityIndicator.stopAnimating()
            videoRenderer.applyGeometry()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .disconnecting:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
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

        let now = Date().timeIntervalSince1970
        if !hasReceivedFirstVideoFrame {
            if now - runningSinceTs > 3.0, now - lastVideoRecoveryTs > 1.5 {
                lastVideoRecoveryTs = now
                print("MainViewController: Video watchdog requesting first-frame recovery")
                connectionManager.requestVideoRecovery()
            }
            return
        }

        if now - lastVideoFrameTs > 6.0, now - lastVideoRecoveryTs > 2.0 {
            lastVideoRecoveryTs = now
            print("MainViewController: Video watchdog detected frame stall, requesting recovery")
            connectionManager.requestVideoRecovery()
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

        let alert = UIAlertController(
            title: "Settings",
            message: "Changes apply on next connection.\nMode: \(connectionMode)\nAuto reconnect: \(autoReconnect)\nVideo: \(codec)\nAudio: \(audioCodec)\nOrientation: \(orientation)\nResolution: \(resolution)\nFPS: \(fps)\(fps != effectiveFps ? " (effective: \(effectiveFps))" : "")\nDPI: \(dpi)\(dpi != effectiveDpi ? " (effective: \(effectiveDpi))" : "")\nFit: \(ProjectionSettings.videoFitMode.title)\nPosition: \(ProjectionSettings.driverPosition == .left ? "LHD" : "RHD")\nGPS: \(gpsSource)",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Connection Mode", style: .default) { [weak self] _ in
            self?.presentConnectionModeMenu()
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

        alert.addAction(UIAlertAction(title: "Display Fit Mode: \(ProjectionSettings.videoFitMode.title)", style: .default) { [weak self] _ in
            self?.presentFitModeMenu()
        })

        alert.addAction(UIAlertAction(title: "Driving Position: \(ProjectionSettings.driverPosition == .left ? "LHD (Left)" : "RHD (Right)")", style: .default) { [weak self] _ in
            self?.presentDrivingPositionMenu()
        })

        alert.addAction(UIAlertAction(title: "Coolwalk Split-Screen & DPI Preview", style: .default) { [weak self] _ in
            self?.presentDpiPreviewModal()
        })

        alert.addAction(UIAlertAction(title: "Orientation", style: .default) { [weak self] _ in
            self?.presentOrientationMenu()
        })

        alert.addAction(UIAlertAction(title: "Resolution: \(ProjectionSettings.videoResolution.title(for: ProjectionSettings.orientation))", style: .default) { [weak self] _ in
            self?.presentResolutionMenu()
        })

        alert.addAction(UIAlertAction(title: "FPS: \(ProjectionSettings.fpsLimit.title)", style: .default) { [weak self] _ in
            self?.presentFpsMenu()
        })

        let dpiTitle = ProjectionSettings.isAutoDpi ? "DPI: Auto (\(ProjectionSettings.effectiveDpi))" : "DPI: \(ProjectionSettings.dpi)"
        alert.addAction(UIAlertAction(title: dpiTitle, style: .default) { [weak self] _ in
            self?.presentDpiMenu()
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

        for option in [ProjectionOrientation.landscape, .portrait] {
            let title = option == ProjectionSettings.orientation ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                ProjectionSettings.orientation = option
                self?.applyOrientationLock()
                self?.presentSettingsMenu()
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

    private func presentDpiMenu() {
        let alert = UIAlertController(
            title: "DPI",
            message: "Enter custom DPI (\(ProjectionSettings.minDpi)-\(ProjectionSettings.maxDpi)) or choose Auto Match iPad.",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.placeholder = "\(ProjectionSettings.recommendedDpiForCurrentDevice())"
            textField.text = "\(ProjectionSettings.effectiveDpi)"
        }

        alert.addAction(UIAlertAction(title: "Save Custom", style: .default) { [weak self, weak alert] _ in
            guard let raw = alert?.textFields?.first?.text,
                  let value = Int(raw) else {
                self?.presentSettingsMenu()
                return
            }

            ProjectionSettings.dpi = value
            self?.presentSettingsMenu()
        })

        let rec = ProjectionSettings.recommendedDpiForCurrentDevice()
        alert.addAction(UIAlertAction(title: "Auto Match iPad (\(rec))", style: .default) { [weak self] _ in
            ProjectionSettings.resetDpiToDefault()
            self?.presentSettingsMenu()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.presentSettingsMenu()
        })

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
        let initialPrefix = ProjectionSettings.isAutoDpi ? "Auto " : ""
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

        let updateDpiBlock: (Int, Bool) -> Void = { [weak slider, weak previewView, weak dpiLabel] val, isAuto in
            guard let slider, let previewView, let dpiLabel else { return }
            let clamped = min(max(val, ProjectionSettings.minDpi), ProjectionSettings.maxDpi)
            slider.value = Float(clamped)
            previewView.dpi = clamped
            let prefix = isAuto ? "Auto " : ""
            dpiLabel.text = "DPI: \(prefix)(\(clamped))  (\(previewView.virtualWidthDp)×\(previewView.virtualHeightDp) dp)"
            if isAuto {
                ProjectionSettings.resetDpiToDefault()
            } else {
                ProjectionSettings.dpi = clamped
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
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
    }

    @objc private func floatingDisconnectButtonTapped() {
        promptDisconnectConfirmation()
    }

    @objc private func handleTwoFingerDoubleTap() {
        promptDisconnectConfirmation()
    }

    private func promptDisconnectConfirmation() {
        let alert = UIAlertController(
            title: "Disconnect",
            message: "Do you want to disconnect Android Auto?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { [weak self] _ in
            self?.connectionManager.disconnect()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func mapTouchPointToAa(_ point: CGPoint) -> (x: Int, y: Int) {
        let screenConfig = HeadUnitScreenConfig.shared
        let width = Float(max(touchOverlayView.bounds.width, 1))
        let height = Float(max(touchOverlayView.bounds.height, 1))

        let coord = TouchCoordinateMapper.map(
            rawX: Float(point.x),
            rawY: Float(point.y),
            inputSurfaceWidth: width,
            inputSurfaceHeight: height,
            negotiatedWidth: screenConfig.getNegotiatedWidth(),
            negotiatedHeight: screenConfig.getNegotiatedHeight(),
            marginWidth: Float(screenConfig.getWidthMargin()),
            marginHeight: Float(screenConfig.getHeightMargin()),
            fitMode: screenConfig.videoFitMode
        )
        return (coord.x, coord.y)
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
        VideoFrameBus.shared.publish(frame: data)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.videoRenderer.enqueueAnnexBFrame(data)
        }
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
