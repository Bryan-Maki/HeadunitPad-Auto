//
//  PerformanceOverlayView.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PerformanceOverlay.kt / DebugOverlayView.kt
//  Floating non-interactive HUD showing real-time projection performance.
//

import UIKit

public final class PerformanceOverlayView: UIView {
    private let hudLabel = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Critical: Must be 100% non-interactive touch passthrough
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerRadius = 8
        layer.masksToBounds = true

        hudLabel.translatesAutoresizingMaskIntoConstraints = false
        hudLabel.numberOfLines = 2
        hudLabel.textColor = .systemYellow
        hudLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        hudLabel.isUserInteractionEnabled = false
        addSubview(hudLabel)

        NSLayoutConstraint.activate([
            hudLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            hudLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            hudLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            hudLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
    }

    public func update(snapshot: PerformanceSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.hudLabel.text = PerformanceOverlayPolicy.formatHudText(snapshot)
        }
    }
}
