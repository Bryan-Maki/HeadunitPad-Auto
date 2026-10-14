import UIKit

final class VideoOnlyViewController: UIViewController {
    private let videoRenderer = H264VideoRendererView()
    private var frameSubscriptionId: UUID?
    private var cursorSubscriptionId: UUID?
    private let cursorView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 9
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.borderWidth = 2
        view.isUserInteractionEnabled = false
        return view
    }()

    private let navigationHud = NavigationHudView()

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        let inputs = [
            UIKeyCommand.inputUpArrow,
            UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputLeftArrow,
            UIKeyCommand.inputRightArrow,
            UIKeyCommand.inputEscape,
            "\r",
            " ",
            "\u{8}",
            "\t"
        ]
        return inputs.map {
            UIKeyCommand(input: $0, modifierFlags: [], action: #selector(handleKeyCommand(_:)))
        }
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        guard let input = command.input,
              let aapCode = KeymapManager.shared.resolveAapKeyCode(for: input) else {
            return
        }
        KeymapManager.shared.handleKeyEvent(aapKeyCode: aapCode, isPress: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            KeymapManager.shared.handleKeyEvent(aapKeyCode: aapCode, isPress: false)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        becomeFirstResponder()

        videoRenderer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoRenderer)

        navigationHud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationHud)

        NSLayoutConstraint.activate([
            videoRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoRenderer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoRenderer.topAnchor.constraint(equalTo: view.topAnchor),
            videoRenderer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            navigationHud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            navigationHud.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            navigationHud.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])

        view.addSubview(cursorView)

        AapNavigation.shared.onNavigationUpdate = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.navigationHud.update(with: snapshot)
            }
        }

        frameSubscriptionId = VideoFrameBus.shared.subscribe { [weak self] frame in
            self?.videoRenderer.enqueueAnnexBFrame(frame)
        }

        cursorSubscriptionId = TrackpadInputBridge.shared.subscribeCursor { [weak self] cursorNorm in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let width = max(self.view.bounds.width, 1)
                let height = max(self.view.bounds.height, 1)
                self.cursorView.center = CGPoint(x: cursorNorm.x * width, y: cursorNorm.y * height)
            }
        }
    }

    deinit {
        if let frameSubscriptionId {
            VideoFrameBus.shared.unsubscribe(frameSubscriptionId)
        }
        if let cursorSubscriptionId {
            TrackpadInputBridge.shared.unsubscribeCursor(cursorSubscriptionId)
        }
    }
}
