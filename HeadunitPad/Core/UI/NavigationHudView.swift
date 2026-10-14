//
//  NavigationHudView.swift
//  HeadunitPad
//
//  Semi-transparent HUD overlay displaying turn-by-turn navigation instructions,
//  distance to turn, and road name over the projected video.
//

import UIKit

public final class NavigationHudView: UIView {
    private let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let iconImageView = UIImageView()
    private let distanceLabel = UILabel()
    private let roadLabel = UILabel()
    private let stackView = UIStackView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = .clear
        layer.cornerRadius = 16
        layer.masksToBounds = true
        layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        layer.borderWidth = 1

        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurEffectView)
        NSLayoutConstraint.activate([
            blurEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurEffectView.topAnchor.constraint(equalTo: topAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 36),
            iconImageView.heightAnchor.constraint(equalToConstant: 36)
        ])

        distanceLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        distanceLabel.textColor = .white
        distanceLabel.textAlignment = .left

        roadLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        roadLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        roadLabel.textAlignment = .left
        roadLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [distanceLabel, roadLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        stackView.axis = .horizontal
        stackView.spacing = 14
        stackView.alignment = .center
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(textStack)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        alpha = 0
        isHidden = true
    }

    public func update(with snapshot: NavSnapshot) {
        guard snapshot.status == .active, !snapshot.road.isEmpty || snapshot.distanceMeters != nil else {
            UIView.animate(withDuration: 0.3) {
                self.alpha = 0
            } completion: { _ in
                self.isHidden = true
            }
            return
        }

        distanceLabel.text = snapshot.formattedDistance.isEmpty ? "Turn Ahead" : snapshot.formattedDistance
        roadLabel.text = snapshot.road.isEmpty ? "Follow Route" : snapshot.road

        if let iconData = snapshot.turnIconData, let image = UIImage(data: iconData) {
            iconImageView.image = image
        } else {
            iconImageView.image = defaultTurnIcon(for: snapshot)
        }

        if isHidden {
            isHidden = false
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        }
    }

    private func defaultTurnIcon(for snapshot: NavSnapshot) -> UIImage? {
        let isLeft = snapshot.turnSide == .left
        switch snapshot.nextTurn {
        case .uTurn:
            return UIImage(systemName: "arrow.uturn.left")
        case .sharpTurn:
            return UIImage(systemName: isLeft ? "arrow.turn.up.left" : "arrow.turn.up.right")
        case .slightTurn:
            return UIImage(systemName: isLeft ? "arrow.up.left" : "arrow.up.right")
        case .turn:
            return UIImage(systemName: isLeft ? "arrow.left" : "arrow.right")
        case .fork:
            return UIImage(systemName: "arrow.triangle.branch")
        case .roundaboutEnter, .roundaboutExit:
            return UIImage(systemName: "arrow.triangle.2.circlepath")
        default:
            return UIImage(systemName: "arrow.up")
        }
    }
}
