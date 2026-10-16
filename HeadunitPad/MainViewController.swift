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
        config.title = "Scan for Headunit Server (Port 5277)"
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

    private lazy var serverGuideContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.85)
        v.layer.cornerRadius = 14
        v.layer.borderWidth = 1.0
        v.layer.borderColor = UIColor.separator.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var serverGuideTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "How to Start Head Unit Server on Android"
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var serverGuideBodyLabel: UILabel = {
        let label = UILabel()
        label.text = """
        1. On your Android phone, open Settings → Connected devices → Connection preferences → Android Auto.
        2. Scroll to the bottom and tap "Version" 10 times to enable Developer Mode, then confirm with "OK".
        3. Tap the top-right "⋮" menu and select "Start head unit server".
        4. Turn on your phone's Personal Hotspot, connect this iPad to the hotspot Wi-Fi, then tap Direct Connect or Scan above.
        """
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
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

    // MARK: - Phase 6 HUD & Diagnostics Properties
    private let performanceOverlayView = PerformanceOverlayView()
    private var performanceTimer: Timer?
    private var orientationReconnectTimer: Timer?

    private let connectionIssueBannerView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
        v.layer.cornerRadius = 12
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.4).cgColor
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let connectionIssueTitleLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .systemOrange
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let connectionIssueAdviceLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var connectionIssueDismissButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Dismiss", for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(dismissConnectionIssueBanner), for: .touchUpInside)
        return b
    }()

    private var dismissedIssueEpochMs: Int64?
    private var bannerZeroHeightConstraint: NSLayoutConstraint?

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
                self.videoRenderer.setNeedsLayout()
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
            videoContainerView.bringSubviewToFront(performanceOverlayView)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let wasCodecPortrait = HeadUnitScreenConfig.shared.negotiatedHeight > HeadUnitScreenConfig.shared.negotiatedWidth
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
                if ProjectionSettings.orientation == .system && ((h > w) != wasCodecPortrait) {
                    HeadUnitScreenConfig.shared.clearCustomNegotiatedResolution()
                    HeadUnitScreenConfig.shared.clearAnnouncedMargins()
                    HeadUnitScreenConfig.shared.initScreen(
                        width: w,
                        height: h,
                        fitMode: ProjectionSettings.videoFitMode,
                        requestedResolution: ProjectionSettings.resolution
                    )
                } else {
                    _ = HeadUnitScreenConfig.shared.updateDimensions(width: w, height: h)
                }
            }
            self.syncVideoAndTouchGeometry()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            self.videoRenderer.applyGeometry()
            self.syncVideoAndTouchGeometry()
            let screen = self.view.window?.screen ?? UIScreen.main
            let nativeScale = screen.nativeScale
            let currentW = Int((self.view.bounds.width * nativeScale).rounded())
            let currentH = Int((self.view.bounds.height * nativeScale).rounded())
            let isNowPortrait = currentH > currentW
            if ProjectionSettings.orientation == .system && (isNowPortrait != wasCodecPortrait) {
                if self.connectionManager.state == .running || self.connectionManager.state == .handshaking {
                    self.orientationReconnectTimer?.invalidate()
                    self.orientationReconnectTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                        self?.connectionManager.reconnectForOrientationChange()
                    }
                }
            }
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
        videoContainerView.addSubview(performanceOverlayView)
        videoRenderer.translatesAutoresizingMaskIntoConstraints = false
        touchOverlayView.translatesAutoresizingMaskIntoConstraints = false
        performanceOverlayView.translatesAutoresizingMaskIntoConstraints = false

        directConnectContainer.addSubview(directIpLabel)
        directConnectContainer.addSubview(directIpTextField)
        directConnectContainer.addSubview(directConnectButton)

        homeContentView.addSubview(titleLabel)
        homeContentView.addSubview(subtitleLabel)
        homeContentView.addSubview(statusLabel)
        homeContentView.addSubview(directConnectContainer)
        homeContentView.addSubview(orDividerLabel)
        homeContentView.addSubview(connectButton)
        serverGuideContainer.addSubview(serverGuideTitleLabel)
        serverGuideContainer.addSubview(serverGuideBodyLabel)
        homeContentView.addSubview(serverGuideContainer)

        connectionIssueBannerView.addSubview(connectionIssueTitleLabel)
        connectionIssueBannerView.addSubview(connectionIssueAdviceLabel)
        connectionIssueBannerView.addSubview(connectionIssueDismissButton)
        homeContentView.addSubview(connectionIssueBannerView)

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

            performanceOverlayView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            performanceOverlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
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

            // Server Guide Container
            serverGuideContainer.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            serverGuideContainer.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20),
            serverGuideContainer.widthAnchor.constraint(equalToConstant: connectControlWidth),

            serverGuideTitleLabel.topAnchor.constraint(equalTo: serverGuideContainer.topAnchor, constant: 14),
            serverGuideTitleLabel.leadingAnchor.constraint(equalTo: serverGuideContainer.leadingAnchor, constant: 16),
            serverGuideTitleLabel.trailingAnchor.constraint(equalTo: serverGuideContainer.trailingAnchor, constant: -16),

            serverGuideBodyLabel.topAnchor.constraint(equalTo: serverGuideTitleLabel.bottomAnchor, constant: 8),
            serverGuideBodyLabel.leadingAnchor.constraint(equalTo: serverGuideContainer.leadingAnchor, constant: 16),
            serverGuideBodyLabel.trailingAnchor.constraint(equalTo: serverGuideContainer.trailingAnchor, constant: -16),
            serverGuideBodyLabel.bottomAnchor.constraint(equalTo: serverGuideContainer.bottomAnchor, constant: -14),

            // Connection Issue Banner View
            connectionIssueBannerView.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            connectionIssueBannerView.topAnchor.constraint(equalTo: serverGuideContainer.bottomAnchor, constant: 16),
            connectionIssueBannerView.widthAnchor.constraint(equalToConstant: connectControlWidth),

            connectionIssueTitleLabel.topAnchor.constraint(equalTo: connectionIssueBannerView.topAnchor, constant: 12),
            connectionIssueTitleLabel.leadingAnchor.constraint(equalTo: connectionIssueBannerView.leadingAnchor, constant: 14),
            connectionIssueTitleLabel.trailingAnchor.constraint(equalTo: connectionIssueDismissButton.leadingAnchor, constant: -8),

            connectionIssueDismissButton.centerYAnchor.constraint(equalTo: connectionIssueTitleLabel.centerYAnchor),
            connectionIssueDismissButton.trailingAnchor.constraint(equalTo: connectionIssueBannerView.trailingAnchor, constant: -14),

            connectionIssueAdviceLabel.topAnchor.constraint(equalTo: connectionIssueTitleLabel.bottomAnchor, constant: 6),
            connectionIssueAdviceLabel.leadingAnchor.constraint(equalTo: connectionIssueBannerView.leadingAnchor, constant: 14),
            connectionIssueAdviceLabel.trailingAnchor.constraint(equalTo: connectionIssueBannerView.trailingAnchor, constant: -14),
            connectionIssueAdviceLabel.bottomAnchor.constraint(equalTo: connectionIssueBannerView.bottomAnchor, constant: -12),

            // Disconnect Button
            disconnectButton.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            disconnectButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 36),
            disconnectButton.widthAnchor.constraint(equalToConstant: 200),
            disconnectButton.heightAnchor.constraint(equalToConstant: 48),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: homeContentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: connectionIssueBannerView.bottomAnchor, constant: 16),

            // Settings Button
            settingsButton.trailingAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            settingsButton.topAnchor.constraint(equalTo: homeContentView.safeAreaLayoutGuide.topAnchor, constant: 12),

            homeContentView.bottomAnchor.constraint(greaterThanOrEqualTo: activityIndicator.bottomAnchor, constant: 48)
        ])

        bannerZeroHeightConstraint = connectionIssueBannerView.heightAnchor.constraint(equalToConstant: 0)
        bannerZeroHeightConstraint?.isActive = true
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
            serverGuideContainer.isHidden = false
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
            serverGuideContainer.isHidden = true
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
            serverGuideContainer.isHidden = true
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
            serverGuideContainer.isHidden = true
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
            serverGuideContainer.isHidden = true
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
            ConnectionIssueStore.shared.clearAll()
            startVideoWatchdog()
            homeScrollView.isHidden = true
            videoContainerView.isHidden = false
            view.bringSubviewToFront(videoContainerView)
            serverGuideContainer.isHidden = true
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
            serverGuideContainer.isHidden = true
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
            let lower = message.lowercased()
            if lower.contains("5277") || lower.contains("refused") {
                ConnectionIssueStore.shared.raise(issue: .connectionRefused5277)
            } else if lower.contains("tls") || lower.contains("handshake") {
                ConnectionIssueStore.shared.raise(issue: .tlsHandshakeFailed)
            } else {
                ConnectionIssueStore.shared.raise(issue: .headunitServerNotAnswering)
            }
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            serverGuideContainer.isHidden = false
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

        updatePerformanceOverlayState()
        updateConnectionIssueBanner()
    }

    private func updateConnectButtonTitle() {
        var config = connectButton.configuration
        config?.title = "Scan for Headunit Server (Port 5277)"
        connectButton.configuration = config
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

        connectionManager.updateNightMode(userInterfaceStyle: traitCollection.userInterfaceStyle, force: false)

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
                connectionManager.updateNightMode(userInterfaceStyle: traitCollection.userInterfaceStyle, force: true)
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
        connectionManager.startDiscovery()
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
        let autoReconnect = ProjectionSettings.autoReconnect ? "On" : "Off"
        let codec = ProjectionSettings.videoCodecPreference.title
        let audioCodec = ProjectionSettings.audioCodecPreference.title
        let audioTarget = ProjectionSettings.audioOutputTarget.title

        let alert = UIAlertController(
            title: "Settings",
            message: "Changes apply on next connection.\nAuto reconnect: \(autoReconnect)\nVideo: \(codec)\nAudio Codec: \(audioCodec)\nAudio Output: \(audioTarget)\nOrientation: \(orientation)\nResolution: \(resolution)\nFPS: \(fps)\(fps != effectiveFps ? " (effective: \(effectiveFps))" : "")\nDPI: \(dpi)\(dpi != effectiveDpi ? " (effective: \(effectiveDpi))" : "")\nFit: \(ProjectionSettings.videoFitMode.title)\nPosition: \(ProjectionSettings.driverPosition == .left ? "LHD" : "RHD")\nGPS: \(gpsSource)",
            preferredStyle: .actionSheet
        )

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

        let hudTitle = ProjectionSettings.showPerformanceOverlay ? "Performance HUD: On" : "Performance HUD: Off"
        alert.addAction(UIAlertAction(title: hudTitle, style: .default) { [weak self] _ in
            ProjectionSettings.showPerformanceOverlay.toggle()
            self?.updatePerformanceOverlayState()
            self?.presentSettingsMenu()
        })

        alert.addAction(UIAlertAction(title: "Audio Stream Tester", style: .default) { [weak self] _ in
            self?.presentAudioStreamTesterMenu()
        })

        alert.addAction(UIAlertAction(title: "Export / Share Logs", style: .default) { [weak self] _ in
            self?.presentLogExportMenu()
        })

        alert.addAction(UIAlertAction(title: "Backup / Restore Settings", style: .default) { [weak self] _ in
            self?.presentSettingsBackupMenu()
        })

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

                let newIsPortrait = HeadUnitScreenConfig.shared.isPortraitDisplay
                if oldIsPortrait != newIsPortrait, (self.connectionManager.state == .running || self.connectionManager.state == .handshaking) {
                    self.connectionManager.screenConfig.clearCustomNegotiatedResolution()
                    self.connectionManager.screenConfig.initScreen(displayRealWidth: w, displayRealHeight: h, displayDpi: ProjectionSettings.effectiveDpi)
                    self.connectionManager.reconnectForOrientationChange()
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

    private func presentNightModeMenu() {
        let alert = UIAlertController(title: "Night Mode", message: nil, preferredStyle: .actionSheet)

        for option in NightModeSetting.allCases {
            let title = option == ProjectionSettings.nightMode ? "\(option.title) (Current)" : option.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                ProjectionSettings.nightMode = option
                self.connectionManager.updateNightMode(userInterfaceStyle: self.traitCollection.userInterfaceStyle, force: true)
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

    // MARK: - Phase 6 Helper Methods

    private func updatePerformanceOverlayState() {
        let shouldShow = ProjectionSettings.showPerformanceOverlay && connectionManager.state == .running
        performanceOverlayView.isHidden = !shouldShow
        if shouldShow {
            if performanceTimer == nil {
                performanceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.refreshPerformanceOverlay()
                }
            }
            refreshPerformanceOverlay()
        } else {
            performanceTimer?.invalidate()
            performanceTimer = nil
        }
    }

    private func refreshPerformanceOverlay() {
        guard !performanceOverlayView.isHidden else { return }
        let fps = videoRenderer.currentFps
        let mbps = connectionManager.currentRxMbps
        let lat = videoRenderer.decodeLatency
        let pcmMs = audioPlayer.mediaBufferDepthMs
        let kf = videoRenderer.keyframeRepairs
        let drop = videoRenderer.droppedFrames
        let resText = "\(videoRenderer.codecWidth)x\(videoRenderer.codecHeight)"

        let snapshot = PerformanceSnapshot(
            fps: fps,
            rxMbps: mbps,
            decodeMedianMs: lat.medianMs,
            decodeP95Ms: lat.p95Ms,
            audioBufferMs: pcmMs,
            keyframeRepairs: kf,
            droppedFrames: drop,
            resolutionText: resText
        )
        performanceOverlayView.update(snapshot: snapshot)
    }

    private func updateConnectionIssueBanner() {
        let standing = ConnectionIssueStore.shared.currentIssues()
        let isConnected = (connectionManager.state == .running)
        if let issue = ConnectionIssueBannerPolicy.bannerFor(
            standing: standing,
            sessionConnected: isConnected,
            dismissedAtEpochMs: dismissedIssueEpochMs
        ) {
            connectionIssueTitleLabel.text = issue.issue.title
            connectionIssueAdviceLabel.text = issue.issue.resolutionAdvice
            connectionIssueBannerView.isHidden = false
            bannerZeroHeightConstraint?.isActive = false
        } else {
            connectionIssueBannerView.isHidden = true
            bannerZeroHeightConstraint?.isActive = true
        }
    }

    @objc private func dismissConnectionIssueBanner() {
        if let current = ConnectionIssueStore.shared.currentIssues().first {
            dismissedIssueEpochMs = current.raisedAtEpochMs
        } else {
            dismissedIssueEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        }
        updateConnectionIssueBanner()
    }

    private func presentAudioStreamTesterMenu() {
        let alert = UIAlertController(
            title: "Audio Stream Tester",
            message: "Generate synthetic 16-bit LE PCM tones to test playback channels and ducking.",
            preferredStyle: .actionSheet
        )

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

        alert.addAction(UIAlertAction(title: "Stop All Audio", style: .destructive) { [weak self] _ in
            self?.audioPlayer.reset()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentLogExportMenu() {
        let alert = UIAlertController(
            title: "Export / Share Logs",
            message: "Session diagnostic logs & audit reports.",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Copy Log to Clipboard", style: .default) { _ in
            let text = LogExporter.exportToClipboardText()
            UIPasteboard.general.string = text
            AppLog.i("Diagnostic log copied to clipboard (\(text.utf8.count) bytes)", tag: "MainViewController")
        })

        alert.addAction(UIAlertAction(title: "Share Log File (.txt)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if let fileUrl = LogExporter.exportToTemporaryFile() {
                let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = self.settingsButton
                    popover.sourceRect = self.settingsButton.bounds
                }
                self.present(activityVC, animated: true)
            }
        })

        alert.addAction(UIAlertAction(title: "Clear In-Memory Logs", style: .destructive) { _ in
            AppLog.shared.clear()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func presentSettingsBackupMenu() {
        let alert = UIAlertController(
            title: "Backup / Restore Settings",
            message: "Export settings to JSON or restore from clipboard / default.",
            preferredStyle: .actionSheet
        )

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
                self.applyOrientationLock()
                self.syncVideoAndTouchGeometry()
                let ok = UIAlertController(title: "Settings Restored", message: "Preferences have been restored from clipboard.", preferredStyle: .alert)
                ok.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(ok, animated: true)
            } catch {
                let err = UIAlertController(title: "Restore Error", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(err, animated: true)
            }
        })

        alert.addAction(UIAlertAction(title: "Reset Settings to Default", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            SettingsBackupManager.resetToDefaults()
            self.applyOrientationLock()
            self.syncVideoAndTouchGeometry()
            let ok = UIAlertController(title: "Settings Reset", message: "All settings restored to factory defaults.", preferredStyle: .alert)
            ok.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(ok, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configurePopoverSource(for: alert)
        present(alert, animated: true)
    }

    private func configurePopoverSource(for alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusLabel.text = "Found: \(device.displayName), connecting..."
        }
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
