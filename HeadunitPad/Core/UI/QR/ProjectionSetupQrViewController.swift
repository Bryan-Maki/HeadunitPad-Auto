//
//  ProjectionSetupQrViewController.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ProjectionSetupQrDialog.kt for iPadOS.
//  Modal dialog presenting the Android Auto Wireless setup QR code and direct Wi-Fi credentials.
//

import UIKit

public final class ProjectionSetupQrViewController: UIViewController {
    private let contentUrl: String
    private let ip: String
    private let port: Int
    private let ssid: String

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Android Auto Wireless Pairing"
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let qrImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .white
        iv.layer.cornerRadius = 12
        iv.layer.masksToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var closeButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Done"
        config.cornerStyle = .capsule
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return btn
    }()

    public init(contentUrl: String, ip: String, port: Int, ssid: String = "Wi-Fi / Hotspot") {
        self.contentUrl = contentUrl
        self.ip = ip
        self.port = port
        self.ssid = ssid
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(qrImageView)
        containerView.addSubview(infoLabel)
        containerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 400),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            qrImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            qrImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 240),
            qrImageView.heightAnchor.constraint(equalToConstant: 240),

            infoLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            closeButton.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 20),
            closeButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 160),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24)
        ])

        renderQrCode()
        infoLabel.text = "Server IP: \(ip)\nPort: \(port)\nScan with your Android phone to pair wirelessly."
    }

    private func renderQrCode() {
        qrImageView.image = QrCodeGenerator.generateQrCode(content: contentUrl, size: 240)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
