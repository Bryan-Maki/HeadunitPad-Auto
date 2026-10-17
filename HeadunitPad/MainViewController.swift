//
//  MainViewController.swift
//  HeadunitPad
//
//  Modern dual-column automotive dashboard receiver for iPadOS.
//  Hosts status pill, direct/auto connection cards, step-by-step Android setup guide,
//  interactive quick-spec tiles, native settings modal, and hardware-accelerated video/audio sinks.
//

import UIKit
import AVFoundation
import CoreLocation

final class MainViewController: UIViewController {

    // MARK: - Properties

    private let connectionManager = ConnectionManager.shared
    private let videoRenderer = H264VideoRendererView()
    private let audioPlayer = PCMAudioPlayer.shared
    private var videoWatchdogTimer: Timer?
    private var runningSinceTs: TimeInterval = 0
    private var lastVideoFrameTs: TimeInterval = 0
    private var hasReceivedFirstVideoFrame = false
    private var lastVideoRecoveryTs: TimeInterval = 0

    // MARK: - Video & Touch Projection Views

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

    private let performanceOverlayView = PerformanceOverlayView()
    private var performanceTimer: Timer?
    private var orientationReconnectTimer: Timer?

    // MARK: - Dashboard Layout Views

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

    // MARK: - Header Bar Components

    private let headerContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let appIconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.layer.cornerRadius = 10
        iv.clipsToBounds = true
        if let icon = UIImage(named: "AppIcon") {
            iv.image = icon
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
            iv.image = UIImage(systemName: "car.fill", withConfiguration: config)
            iv.tintColor = .systemBlue
            iv.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        }
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "HeadunitPad"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Wireless Android Auto Receiver"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusPillView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemBackground
        view.layer.cornerRadius = 16
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusDotView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGreen
        view.layer.cornerRadius = 4
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Ready to connect"
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var settingsButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Settings"
        config.image = UIImage(systemName: "slider.horizontal.3")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.baseBackgroundColor = UIColor.systemGray5
        config.baseForegroundColor = .label

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Connection Issue Banner

    private let connectionIssueBannerView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
        v.layer.cornerRadius = 14
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

    // MARK: - Responsive Dual-Column Grid

    private let dashboardGridStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.spacing = 20
        return stack
    }()

    // Left Column: Connection Hub Card
    private let connectionHubCard: UIView = {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.separator.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    private let hubTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Wireless Connection Hub"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let hubIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "wifi"))
        iv.tintColor = .systemBlue
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let directIpLabel: UILabel = {
        let label = UILabel()
        label.text = "Direct Connect (Phone Hotspot IP)"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let directIpTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "192.168.43.1"
        textField.text = NetworkAddresses.currentHotspotGatewayIpv4()
        textField.textAlignment = .center
        textField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        textField.backgroundColor = .tertiarySystemBackground
        textField.layer.cornerRadius = 10
        textField.keyboardType = .numbersAndPunctuation
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private lazy var resetGatewayIpButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.counterclockwise")
        config.buttonSize = .medium
        let button = UIButton(configuration: config)
        button.tintColor = .secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.directIpTextField.text = NetworkAddresses.currentHotspotGatewayIpv4()
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }, for: .touchUpInside)
        return button
    }()

    private lazy var directConnectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Direct Connect"
        config.image = UIImage(systemName: "arrow.right.circle.fill")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.buttonSize = .large
        config.baseBackgroundColor = .systemBlue

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(directConnectButtonTapped), for: .touchUpInside)
        return button
    }()

    private let orDividerLabel: UILabel = {
        let label = UILabel()
        label.text = "— OR AUTO-DISCOVER —"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var connectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Scan for Headunit Server (Port 5277)"
        config.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.buttonSize = .large
        config.baseBackgroundColor = .systemIndigo

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var disconnectButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Cancel / Disconnect"
        config.cornerStyle = .large
        config.buttonSize = .large
        config.baseBackgroundColor = .systemRed

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(disconnectButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    // Right Column: Android Server Guide Card
    private let serverGuideCard: UIView = {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.separator.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    private let guideTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Android Phone Setup Guide"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let guideIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "info.circle.fill"))
        iv.tintColor = .systemTeal
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let guideStepsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Quick Spec Tiles Container (Bottom)

    private let quickSpecsHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "CURRENT CONFIGURATION (TAP TO CONFIGURE)"
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let quickSpecsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var displayTile: QuickSpecTileView!
    private var layoutTile: QuickSpecTileView!
    private var codecsTile: QuickSpecTileView!
    private var audioTile: QuickSpecTileView!
    private var micTile: QuickSpecTileView!
    private var modeTile: QuickSpecTileView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        HeadUnitScreenConfig.shared.videoFitMode = ProjectionSettings.videoFitMode
        setupUI()
        setupConstraints()
        connectionManager.delegate = self

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
                AppLog.i("MainViewController: Video size resolved from SPS: \(w)x\(h)", tag: "MainViewController")
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
        refreshQuickSpecTiles()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyOrientationLock()
        refreshQuickSpecTiles()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        touchOverlayView.frame = videoContainerView.bounds
        touchOverlayView.isUserInteractionEnabled = true

        let isLandscape = view.bounds.width > view.bounds.height
        if dashboardGridStack.axis != (isLandscape ? .horizontal : .vertical) {
            dashboardGridStack.axis = isLandscape ? .horizontal : .vertical
            dashboardGridStack.distribution = isLandscape ? .fillEqually : .fill
        }

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

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            let scale = UIScreen.main.scale
            let w = Int(size.width * scale)
            let h = Int(size.height * scale)
            if w > 0 && h > 0 {
                _ = HeadUnitScreenConfig.shared.updateDimensions(width: w, height: h)
            }
            self.syncVideoAndTouchGeometry()
            self.videoRenderer.applyGeometry()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            let scale = UIScreen.main.scale
            let w = Int(self.view.bounds.width * scale)
            let h = Int(self.view.bounds.height * scale)
            if w > 0 && h > 0 {
                _ = HeadUnitScreenConfig.shared.updateDimensions(width: w, height: h)
            }
            self.syncVideoAndTouchGeometry()
            self.videoRenderer.applyGeometry()
        })
    }

    // MARK: - Autorotation

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
                AppLog.e("MainViewController: Failed to apply orientation lock: \(error)", tag: "MainViewController")
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

    // MARK: - Geometry & Video Synchronization

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

    // MARK: - Setup Views & Constraints

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

        touchOverlayView.onTouch = { [weak self] pointers, action, actionIndex in
            ConnectionManager.shared.sendTouchEvent(pointers: pointers, action: action, actionIndex: actionIndex)
        }

        // 1. Header Bar Subviews
        let appTitleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        appTitleStack.axis = .vertical
        appTitleStack.spacing = 2
        appTitleStack.translatesAutoresizingMaskIntoConstraints = false

        let appBrandStack = UIStackView(arrangedSubviews: [appIconImageView, appTitleStack])
        appBrandStack.axis = .horizontal
        appBrandStack.spacing = 12
        appBrandStack.alignment = .center
        appBrandStack.translatesAutoresizingMaskIntoConstraints = false

        statusPillView.addSubview(statusDotView)
        statusPillView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusDotView.leadingAnchor.constraint(equalTo: statusPillView.leadingAnchor, constant: 10),
            statusDotView.centerYAnchor.constraint(equalTo: statusPillView.centerYAnchor),
            statusDotView.widthAnchor.constraint(equalToConstant: 8),
            statusDotView.heightAnchor.constraint(equalToConstant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: statusDotView.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: statusPillView.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusPillView.centerYAnchor)
        ])

        let rightHeaderStack = UIStackView(arrangedSubviews: [statusPillView, settingsButton])
        rightHeaderStack.axis = .horizontal
        rightHeaderStack.spacing = 10
        rightHeaderStack.alignment = .center
        rightHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        headerContainerView.addSubview(appBrandStack)
        headerContainerView.addSubview(rightHeaderStack)

        // 2. Issue Banner Subviews
        connectionIssueBannerView.addSubview(connectionIssueTitleLabel)
        connectionIssueBannerView.addSubview(connectionIssueAdviceLabel)
        connectionIssueBannerView.addSubview(connectionIssueDismissButton)

        // 3. Left Card: Connection Hub Card
        let hubHeaderStack = UIStackView(arrangedSubviews: [hubIconView, hubTitleLabel])
        hubHeaderStack.axis = .horizontal
        hubHeaderStack.spacing = 8
        hubHeaderStack.alignment = .center
        hubHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        let ipInputContainer = UIStackView(arrangedSubviews: [directIpTextField, resetGatewayIpButton])
        ipInputContainer.axis = .horizontal
        ipInputContainer.spacing = 6
        ipInputContainer.alignment = .fill
        ipInputContainer.translatesAutoresizingMaskIntoConstraints = false

        let indicatorStack = UIStackView(arrangedSubviews: [activityIndicator, disconnectButton])
        indicatorStack.axis = .vertical
        indicatorStack.spacing = 10
        indicatorStack.alignment = .center
        indicatorStack.translatesAutoresizingMaskIntoConstraints = false

        let hubContentStack = UIStackView(arrangedSubviews: [
            hubHeaderStack,
            directIpLabel,
            ipInputContainer,
            directConnectButton,
            orDividerLabel,
            connectButton,
            indicatorStack
        ])
        hubContentStack.axis = .vertical
        hubContentStack.spacing = 12
        hubContentStack.alignment = .fill
        hubContentStack.translatesAutoresizingMaskIntoConstraints = false
        connectionHubCard.addSubview(hubContentStack)

        // 4. Right Card: Setup Guide Card
        let guideHeaderStack = UIStackView(arrangedSubviews: [guideIconView, guideTitleLabel])
        guideHeaderStack.axis = .horizontal
        guideHeaderStack.spacing = 8
        guideHeaderStack.alignment = .center
        guideHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        setupGuideSteps()

        let guideContentStack = UIStackView(arrangedSubviews: [guideHeaderStack, guideStepsStack])
        guideContentStack.axis = .vertical
        guideContentStack.spacing = 16
        guideContentStack.alignment = .fill
        guideContentStack.translatesAutoresizingMaskIntoConstraints = false
        serverGuideCard.addSubview(guideContentStack)

        // Add to dashboard grid
        dashboardGridStack.addArrangedSubview(connectionHubCard)
        dashboardGridStack.addArrangedSubview(serverGuideCard)

        // 5. Quick Spec Tiles
        setupQuickSpecTiles()

        // Assemble Content View
        homeContentView.addSubview(headerContainerView)
        homeContentView.addSubview(connectionIssueBannerView)
        homeContentView.addSubview(dashboardGridStack)
        homeContentView.addSubview(quickSpecsHeaderLabel)
        homeContentView.addSubview(quickSpecsStack)

        homeScrollView.addSubview(homeContentView)

        view.addSubview(videoContainerView)
        view.addSubview(homeScrollView)

        videoContainerView.isHidden = true
        homeScrollView.isHidden = false
    }

    private func setupGuideSteps() {
        let steps = [
            (icon: "gearshape.2.fill", tint: UIColor.systemIndigo, title: "1. Open Android Auto Settings", detail: "In phone Settings → Connected devices → Android Auto"),
            (icon: "checkmark.seal.fill", tint: UIColor.systemBlue, title: "2. Enable Developer Mode", detail: "Scroll down, tap 'Version' 10 times and confirm OK"),
            (icon: "play.tv.fill", tint: UIColor.systemGreen, title: "3. Start Head Unit Server", detail: "Tap top-right '⋮' menu in Android Auto & start server"),
            (icon: "personalhotspot", tint: UIColor.systemOrange, title: "4. Connect Hotspot & Launch", detail: "Connect iPad to phone hotspot Wi-Fi & tap Connect")
        ]

        for step in steps {
            let row = makeGuideStepRow(icon: step.icon, iconTint: step.tint, title: step.title, detail: step.detail)
            guideStepsStack.addArrangedSubview(row)
        }
    }

    private func makeGuideStepRow(icon: String, iconTint: UIColor, title: String, detail: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let badge = UIView()
        badge.backgroundColor = iconTint.withAlphaComponent(0.15)
        badge.layer.cornerRadius = 8
        badge.translatesAutoresizingMaskIntoConstraints = false

        let iv = UIImageView(image: UIImage(systemName: icon))
        iv.tintColor = iconTint
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(iv)

        let titleLbl = UILabel()
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLbl.textColor = .label
        titleLbl.translatesAutoresizingMaskIntoConstraints = false

        let detailLbl = UILabel()
        detailLbl.text = detail
        detailLbl.font = .systemFont(ofSize: 11, weight: .regular)
        detailLbl.textColor = .secondaryLabel
        detailLbl.numberOfLines = 2
        detailLbl.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLbl, detailLbl])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(badge)
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 32),
            badge.heightAnchor.constraint(equalToConstant: 32),

            iv.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 18),
            iv.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: container.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func setupQuickSpecTiles() {
        displayTile = QuickSpecTileView(icon: "display", title: "Display", tint: .systemBlue)
        layoutTile = QuickSpecTileView(icon: "aspectratio", title: "Layout & DPI", tint: .systemPurple)
        codecsTile = QuickSpecTileView(icon: "waveform.path.ecg", title: "Codecs", tint: .systemPink)
        audioTile = QuickSpecTileView(icon: "speaker.wave.2.fill", title: "Audio Output", tint: .systemGreen)
        micTile = QuickSpecTileView(icon: "mic.fill", title: "Microphone", tint: .systemTeal)
        modeTile = QuickSpecTileView(icon: "moon.stars.fill", title: "Smart Mode", tint: .systemOrange)

        let topRow = UIStackView(arrangedSubviews: [displayTile, layoutTile, codecsTile])
        topRow.axis = .horizontal
        topRow.spacing = 10
        topRow.distribution = .fillEqually

        let bottomRow = UIStackView(arrangedSubviews: [audioTile, micTile, modeTile])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 10
        bottomRow.distribution = .fillEqually

        quickSpecsStack.addArrangedSubview(topRow)
        quickSpecsStack.addArrangedSubview(bottomRow)

        [displayTile, layoutTile, codecsTile, audioTile, micTile, modeTile].forEach { tile in
            tile?.onTap = { [weak self] in
                self?.presentSettingsMenu()
            }
        }
    }

    private func setupConstraints() {
        let maxWidthConstraint = homeContentView.widthAnchor.constraint(lessThanOrEqualToConstant: 880)
        let widthConstraint = homeContentView.widthAnchor.constraint(equalTo: homeScrollView.frameLayoutGuide.widthAnchor, constant: -32)
        widthConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Video & Touch Fullscreen
            videoContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            videoContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

            // Scroll View
            homeScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            homeScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            homeScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            homeScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            homeContentView.leadingAnchor.constraint(greaterThanOrEqualTo: homeScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            homeContentView.trailingAnchor.constraint(lessThanOrEqualTo: homeScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            homeContentView.centerXAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.centerXAnchor),
            homeContentView.topAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.topAnchor, constant: 20),
            homeContentView.bottomAnchor.constraint(equalTo: homeScrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            maxWidthConstraint,
            widthConstraint,

            // Header Bar
            headerContainerView.topAnchor.constraint(equalTo: homeContentView.topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: homeContentView.leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: homeContentView.trailingAnchor),
            headerContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            appIconImageView.widthAnchor.constraint(equalToConstant: 44),
            appIconImageView.heightAnchor.constraint(equalToConstant: 44),
            statusPillView.heightAnchor.constraint(equalToConstant: 34),
            settingsButton.heightAnchor.constraint(equalToConstant: 34),

            // Header Bar alignment
            headerContainerView.subviews[0].leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerContainerView.subviews[0].centerYAnchor.constraint(equalTo: headerContainerView.centerYAnchor),
            headerContainerView.subviews[1].trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerContainerView.subviews[1].centerYAnchor.constraint(equalTo: headerContainerView.centerYAnchor),
            headerContainerView.subviews[0].trailingAnchor.constraint(lessThanOrEqualTo: headerContainerView.subviews[1].leadingAnchor, constant: -8),

            // Issue Banner
            connectionIssueBannerView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: 14),
            connectionIssueBannerView.leadingAnchor.constraint(equalTo: homeContentView.leadingAnchor),
            connectionIssueBannerView.trailingAnchor.constraint(equalTo: homeContentView.trailingAnchor),

            connectionIssueTitleLabel.topAnchor.constraint(equalTo: connectionIssueBannerView.topAnchor, constant: 12),
            connectionIssueTitleLabel.leadingAnchor.constraint(equalTo: connectionIssueBannerView.leadingAnchor, constant: 14),
            connectionIssueTitleLabel.trailingAnchor.constraint(equalTo: connectionIssueDismissButton.leadingAnchor, constant: -8),

            connectionIssueDismissButton.centerYAnchor.constraint(equalTo: connectionIssueTitleLabel.centerYAnchor),
            connectionIssueDismissButton.trailingAnchor.constraint(equalTo: connectionIssueBannerView.trailingAnchor, constant: -14),

            connectionIssueAdviceLabel.topAnchor.constraint(equalTo: connectionIssueTitleLabel.bottomAnchor, constant: 6),
            connectionIssueAdviceLabel.leadingAnchor.constraint(equalTo: connectionIssueBannerView.leadingAnchor, constant: 14),
            connectionIssueAdviceLabel.trailingAnchor.constraint(equalTo: connectionIssueBannerView.trailingAnchor, constant: -14),
            connectionIssueAdviceLabel.bottomAnchor.constraint(equalTo: connectionIssueBannerView.bottomAnchor, constant: -12),

            // Dashboard Grid Stack
            dashboardGridStack.topAnchor.constraint(equalTo: connectionIssueBannerView.bottomAnchor, constant: 16),
            dashboardGridStack.leadingAnchor.constraint(equalTo: homeContentView.leadingAnchor),
            dashboardGridStack.trailingAnchor.constraint(equalTo: homeContentView.trailingAnchor),

            // Left Card Hub Inner Padding
            connectionHubCard.subviews[0].topAnchor.constraint(equalTo: connectionHubCard.topAnchor, constant: 20),
            connectionHubCard.subviews[0].leadingAnchor.constraint(equalTo: connectionHubCard.leadingAnchor, constant: 20),
            connectionHubCard.subviews[0].trailingAnchor.constraint(equalTo: connectionHubCard.trailingAnchor, constant: -20),
            connectionHubCard.subviews[0].bottomAnchor.constraint(equalTo: connectionHubCard.bottomAnchor, constant: -20),

            directIpTextField.heightAnchor.constraint(equalToConstant: 44),
            resetGatewayIpButton.widthAnchor.constraint(equalToConstant: 44),
            directConnectButton.heightAnchor.constraint(equalToConstant: 46),
            connectButton.heightAnchor.constraint(equalToConstant: 48),
            disconnectButton.heightAnchor.constraint(equalToConstant: 44),
            disconnectButton.widthAnchor.constraint(equalToConstant: 220),

            // Right Card Guide Inner Padding
            serverGuideCard.subviews[0].topAnchor.constraint(equalTo: serverGuideCard.topAnchor, constant: 20),
            serverGuideCard.subviews[0].leadingAnchor.constraint(equalTo: serverGuideCard.leadingAnchor, constant: 20),
            serverGuideCard.subviews[0].trailingAnchor.constraint(equalTo: serverGuideCard.trailingAnchor, constant: -20),
            serverGuideCard.subviews[0].bottomAnchor.constraint(equalTo: serverGuideCard.bottomAnchor, constant: -20),

            // Quick Spec Tiles
            quickSpecsHeaderLabel.topAnchor.constraint(equalTo: dashboardGridStack.bottomAnchor, constant: 24),
            quickSpecsHeaderLabel.leadingAnchor.constraint(equalTo: homeContentView.leadingAnchor, constant: 4),
            quickSpecsHeaderLabel.trailingAnchor.constraint(equalTo: homeContentView.trailingAnchor),

            quickSpecsStack.topAnchor.constraint(equalTo: quickSpecsHeaderLabel.bottomAnchor, constant: 10),
            quickSpecsStack.leadingAnchor.constraint(equalTo: homeContentView.leadingAnchor),
            quickSpecsStack.trailingAnchor.constraint(equalTo: homeContentView.trailingAnchor),
            quickSpecsStack.bottomAnchor.constraint(equalTo: homeContentView.bottomAnchor, constant: -12)
        ])

        bannerZeroHeightConstraint = connectionIssueBannerView.heightAnchor.constraint(equalToConstant: 0)
        bannerZeroHeightConstraint?.isActive = true
    }

    // MARK: - Quick Spec Tiles Refresh

    func refreshQuickSpecTiles() {
        let res = ProjectionSettings.resolution.title
        let fps = ProjectionSettings.fpsLimit.title
        displayTile?.value = "\(res) • \(fps)"

        let fit = ProjectionSettings.videoFitMode.title
        let dpi = ProjectionSettings.isAutoDpi ? "Auto (\(ProjectionSettings.effectiveDpi))" : "\(ProjectionSettings.dpi) DPI"
        layoutTile?.value = "\(fit) • \(dpi)"

        let vCodec = ProjectionSettings.videoCodecPreference.title
        let aCodec = ProjectionSettings.audioCodecPreference.title
        codecsTile?.value = "\(vCodec) • \(aCodec)"

        let aOut = ProjectionSettings.audioOutputTarget.title
        audioTile?.value = "\(aOut)"

        let mic = ProjectionSettings.microphoneSource.title
        micTile?.value = "\(mic)"

        let night = ProjectionSettings.nightMode.title
        let rhd = (ProjectionSettings.driverPosition == .right) ? "RHD" : "LHD"
        modeTile?.value = "\(night) • \(rhd)"
    }

    // MARK: - UI Updates for Connection State

    private func updateUIForConnectionState(_ state: ConnectionState) {
        // Prevent screen dimming & sleeping during active projection
        UIApplication.shared.isIdleTimerDisabled = (state == .running)

        let currentIp = NetworkAddresses.stationIpv4() ?? "No Wi-Fi"
        switch state {
        case .disconnected:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            connectionManager.screenConfig.clearCustomNegotiatedResolution()
            videoRenderer.reset()
            audioPlayer.reset()
            settingsButton.isHidden = false
            statusDotView.backgroundColor = .systemGreen
            statusLabel.text = "iPad IP: \(currentIp) • Ready"
            statusLabel.textColor = .secondaryLabel
            connectButton.isEnabled = true
            directConnectButton.isEnabled = true
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
            statusDotView.backgroundColor = .systemIndigo
            statusLabel.text = "Scanning Port 5277..."
            statusLabel.textColor = .systemIndigo
            connectButton.isEnabled = false
            directConnectButton.isEnabled = false
            disconnectButton.isHidden = false
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .waitingForWirelessHelper:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            settingsButton.isHidden = false
            statusDotView.backgroundColor = .systemOrange
            statusLabel.text = connectionManager.statusDetail.isEmpty ? "Waiting for wireless..." : connectionManager.statusDetail
            statusLabel.textColor = .systemOrange
            connectButton.isEnabled = false
            directConnectButton.isEnabled = false
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
            statusDotView.backgroundColor = .systemBlue
            statusLabel.text = "Connecting to \(connectionManager.connectedDevice?.displayName ?? "Phone")..."
            statusLabel.textColor = .systemBlue
            connectButton.isEnabled = false
            directConnectButton.isEnabled = false
            disconnectButton.isHidden = false
            activityIndicator.startAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()

        case .handshaking:
            stopVideoWatchdog()
            videoContainerView.isHidden = true
            homeScrollView.isHidden = false
            view.bringSubviewToFront(homeScrollView)
            settingsButton.isHidden = false
            statusDotView.backgroundColor = .systemBlue
            statusLabel.text = "Handshaking..."
            statusLabel.textColor = .systemBlue
            connectButton.isEnabled = false
            directConnectButton.isEnabled = false
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
            activityIndicator.stopAnimating()
            disconnectButton.isHidden = true
            syncVideoAndTouchGeometry()
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
            statusDotView.backgroundColor = .systemGray
            statusLabel.text = "Disconnecting..."
            statusLabel.textColor = .secondaryLabel
            connectButton.isEnabled = false
            directConnectButton.isEnabled = false
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
            audioPlayer.reset()
            settingsButton.isHidden = false
            statusDotView.backgroundColor = .systemRed
            statusLabel.text = connectionManager.statusDetail.isEmpty ? message : connectionManager.statusDetail
            statusLabel.textColor = .systemRed
            connectButton.isEnabled = true
            directConnectButton.isEnabled = true
            disconnectButton.isHidden = true
            activityIndicator.stopAnimating()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }

        updatePerformanceOverlayState()
        updateConnectionIssueBanner()
        refreshQuickSpecTiles()
    }

    override var prefersStatusBarHidden: Bool {
        return connectionManager.state == .running
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return connectionManager.state == .running
    }

    // MARK: - Video Watchdog

    private func startVideoWatchdog() {
        if videoWatchdogTimer != nil { return }
        runningSinceTs = Date().timeIntervalSince1970
        lastVideoFrameTs = runningSinceTs
        hasReceivedFirstVideoFrame = false
        videoWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkVideoWatchdog()
        }
    }

    private func stopVideoWatchdog() {
        videoWatchdogTimer?.invalidate()
        videoWatchdogTimer = nil
        hasReceivedFirstVideoFrame = false
    }

    private func checkVideoWatchdog() {
        guard connectionManager.state == .running else { return }
        let now = Date().timeIntervalSince1970
        if !hasReceivedFirstVideoFrame {
            if (now - runningSinceTs) > 6.0 && (now - lastVideoRecoveryTs) > 3.0 {
                lastVideoRecoveryTs = now
                connectionManager.requestVideoRecovery()
            }
        } else if (now - lastVideoFrameTs) > 5.0 && (now - lastVideoRecoveryTs) > 3.0 {
            lastVideoRecoveryTs = now
            connectionManager.requestVideoRecovery()
        }
    }

    // MARK: - Actions

    @objc private func connectButtonTapped() {
        connectionManager.startDiscovery()
    }

    @objc private func directConnectButtonTapped() {
        guard let targetIp = directIpTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !targetIp.isEmpty else {
            return
        }
        connectionManager.connect(to: targetIp, port: Discovery.headunitPort)
    }

    @objc private func disconnectButtonTapped() {
        connectionManager.screenConfig.clearCustomNegotiatedResolution()
        connectionManager.disconnect()
    }

    @objc func settingsButtonTapped() {
        presentSettingsMenu()
    }

    func presentSettingsMenu() {
        let settingsVC = SettingsViewController()
        settingsVC.connectionManager = connectionManager
        settingsVC.onSettingsChanged = { [weak self] impact in
            guard let self = self else { return }
            self.refreshQuickSpecTiles()
            switch impact {
            case .uiOnly:
                self.updatePerformanceOverlayState()
            case .nightModeChanged:
                self.connectionManager.updateNightMode(userInterfaceStyle: self.traitCollection.userInterfaceStyle, force: true)
            case .geometryChanged:
                self.applyOrientationLock()
                self.syncVideoAndTouchGeometry()
                self.videoRenderer.applyGeometry()
            case .requiresReconnect:
                if self.connectionManager.state == .running {
                    self.connectionManager.reconnectForSettingsChange()
                }
            }
        }
        settingsVC.onProvideDiagnosticLines = { [weak self] in
            self?.combinedDiagnosticLines() ?? []
        }

        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = CGSize(width: 640, height: 740)
        present(nav, animated: true)
    }

    private func combinedDiagnosticLines() -> [String] {
        connectionManager.diagnosticLines()
            + [""]
            + videoRenderer.diagnosticLines()
    }

    // MARK: - Performance HUD & Banner

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
        let activeW = max(1, videoRenderer.codecWidth - videoRenderer.widthMargin)
        let activeH = max(1, videoRenderer.codecHeight - videoRenderer.heightMargin)
        let resText = (videoRenderer.widthMargin > 0 || videoRenderer.heightMargin > 0)
            ? "\(activeW)x\(activeH) (\(videoRenderer.codecWidth)x\(videoRenderer.codecHeight))"
            : "\(videoRenderer.codecWidth)x\(videoRenderer.codecHeight)"

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
}

// MARK: - ConnectionManagerDelegate

extension MainViewController: ConnectionManagerDelegate {
    func connectionManager(_ manager: ConnectionManager, didChangeState state: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUIForConnectionState(state)
        }
    }

    func connectionManager(_ manager: ConnectionManager, didUpdateStatus status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.connectionManager.state != .running {
                self.statusLabel.text = status
            }
        }
    }

    func connectionManager(_ manager: ConnectionManager, didDiscoverDevice device: DiscoveredDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionManager.connect(to: device, userInitiated: true)
        }
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveVideoData data: Data) {
        lastVideoFrameTs = Date().timeIntervalSince1970
        videoRenderer.feed(naluData: data)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8) {
        audioPlayer.write(pcmData: data, on: channel)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool) {
        audioPlayer.write(audioData: data, on: channel, isAac: isAac)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveAudioCodecConfig data: Data, on channel: UInt8) {
        audioPlayer.configureAacDecoder(with: data, on: channel)
    }
}

// MARK: - QuickSpecTileView

final class QuickSpecTileView: UIControl {

    var onTap: (() -> Void)?

    var value: String = "" {
        didSet {
            valueLabel.text = value
        }
    }

    private let iconBadgeView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let valueLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .bold)
        l.textColor = .label
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.8
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    init(icon: String, title: String, tint: UIColor) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        iconBadgeView.backgroundColor = tint.withAlphaComponent(0.15)
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = tint
        titleLabel.text = title

        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconBadgeView.addSubview(iconImageView)
        let textStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [iconBadgeView, textStack])
        rowStack.axis = .horizontal
        rowStack.spacing = 10
        rowStack.alignment = .center
        rowStack.isUserInteractionEnabled = false
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 58),

            iconBadgeView.widthAnchor.constraint(equalToConstant: 32),
            iconBadgeView.heightAnchor.constraint(equalToConstant: 32),

            iconImageView.centerXAnchor.constraint(equalTo: iconBadgeView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconBadgeView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])

        addTarget(self, action: #selector(tileTapped), for: .touchUpInside)
    }

    @objc private func tileTapped() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        onTap?()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.7 : 1.0
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }
}

