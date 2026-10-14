//
//  FloatingButtonWindow.swift
//  HeadunitPad
//
//  1:1 port of open-headunit FloatingButtonManager.kt & FloatingButtonService.kt
//  Provides a draggable, edge-snapping, auto-dimming floating control button for iPadOS.
//

import UIKit

public final class FloatingButtonView: UIView {

    public static let buttonSize: CGFloat = 54.0

    public var onTap: (() -> Void)?
    public var isConnected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    private let iconImageView = UIImageView()
    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        return UIVisualEffectView(effect: blur)
    }()

    private var idleTimer: Timer?
    private var baseAlpha: CGFloat = 0.85

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.clear
        layer.cornerRadius = FloatingButtonView.buttonSize / 2.0
        layer.masksToBounds = true
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor

        // Shadow for depth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 8.0
        layer.shadowOffset = CGSize(width: 0, height: 4)

        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white
        iconImageView.image = UIImage(systemName: "car.fill") ?? UIImage(systemName: "circle.grid.2x2.fill")
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 26),
            iconImageView.heightAnchor.constraint(equalToConstant: 26)
        ])

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        resetIdleTimer()
    }

    private func updateAppearance() {
        baseAlpha = FloatingButtonOpacityPolicy.targetAlpha(
            isConnectionStatusMode: true,
            isConnected: isConnected
        )
        wakeFromIdle()
    }

    public func wakeFromIdle() {
        idleTimer?.invalidate()
        UIView.animate(withDuration: 0.25) {
            self.alpha = self.baseAlpha
            self.transform = .identity
        }
        resetIdleTimer()
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: FloatingButtonOpacityPolicy.idleFadeTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.5) {
                self.alpha = FloatingButtonOpacityPolicy.idleAlpha(baseAlpha: self.baseAlpha)
            }
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        wakeFromIdle()
        // Haptic feedback
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        onTap?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        wakeFromIdle()

        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended || gesture.state == .cancelled {
            snapToNearestEdge()
        }
    }

    private func snapToNearestEdge() {
        guard let superview = superview else { return }
        let margin: CGFloat = 16.0
        let bounds = superview.bounds.inset(by: superview.safeAreaInsets)
        let halfWidth = FloatingButtonView.buttonSize / 2.0
        let halfHeight = FloatingButtonView.buttonSize / 2.0

        let leftDist = abs(center.x - bounds.minX)
        let rightDist = abs(bounds.maxX - center.x)

        let targetX: CGFloat = (leftDist < rightDist)
            ? bounds.minX + margin + halfWidth
            : bounds.maxX - margin - halfWidth

        let clampedY: CGFloat = min(
            max(center.y, bounds.minY + margin + halfHeight),
            bounds.maxY - margin - halfHeight
        )

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut,
            animations: {
                self.center = CGPoint(x: targetX, y: clampedY)
            },
            completion: { _ in
                self.resetIdleTimer()
            }
        )
    }

    deinit {
        idleTimer?.invalidate()
    }
}
