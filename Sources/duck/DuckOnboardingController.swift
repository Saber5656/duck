import AppKit
import AVFoundation

final class DuckOnboardingController: NSWindowController, NSWindowDelegate {
    private let onDemoNod: () -> Void
    private let onGranted: () -> Void
    private let onDenied: () -> Void
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let startButton = NSButton(title: "Start listening", target: nil, action: nil)
    private var didFinish = false
    private var demoTimer: Timer?

    init(
        onDemoNod: @escaping () -> Void,
        onGranted: @escaping () -> Void,
        onDenied: @escaping () -> Void
    ) {
        self.onDemoNod = onDemoNod
        self.onGranted = onGranted
        self.onDenied = onDenied

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to duck"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    deinit {
        demoTimer?.invalidate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        startDemo()
    }

    func windowWillClose(_ notification: Notification) {
        finish(granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    private func buildContent() {
        let title = NSTextField(labelWithString: "A quiet rubber duck for thinking out loud")
        title.font = .boldSystemFont(ofSize: 20)

        let explanation = NSTextField(wrappingLabelWithString: ""
            + "Watch duck nod for 10 seconds while you read: duck listens while you describe a bug, "
            + "then responds with a small nod. It never understands or answers.")

        let privacyHeading = NSTextField(labelWithString: "Privacy first")
        privacyHeading.font = .boldSystemFont(ofSize: 14)

        let privacy = NSTextField(wrappingLabelWithString: ""
            + "Only the loudness of each microphone buffer is used. The buffer is reduced to one number and "
            + "discarded immediately. There is no recording, speech recognition, or network access.")

        let indicator = NSTextField(wrappingLabelWithString: ""
            + "The macOS orange microphone dot is expected while Listening is on, and turning Listening off "
            + "releases the microphone and removes duck from Control Center.")

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true

        startButton.target = self
        startButton.action = #selector(startListening(_:))
        startButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, explanation, privacyHeading, privacy, indicator, statusLabel, startButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = window?.contentView else { return }
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            startButton.widthAnchor.constraint(equalToConstant: 140)
        ])
    }

    private func startDemo() {
        demoTimer?.invalidate()
        let endTime = Date().addingTimeInterval(10)
        onDemoNod()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard !self.didFinish, Date() < endTime else {
                timer.invalidate()
                self.demoTimer = nil
                return
            }
            self.onDemoNod()
        }
    }

    @objc private func startListening(_ sender: NSButton) {
        guard !didFinish else { return }
        startButton.isEnabled = false
        statusLabel.stringValue = "Checking microphone permission..."
        statusLabel.isHidden = false

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            finish(granted: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.finish(granted: granted)
                }
            }
        case .denied, .restricted:
            statusLabel.stringValue = "Microphone access is unavailable. You can enable it in System Settings."
            finish(granted: false)
        @unknown default:
            finish(granted: false)
        }
    }

    private func finish(granted: Bool) {
        guard !didFinish else { return }
        didFinish = true
        demoTimer?.invalidate()
        demoTimer = nil
        if !granted {
            onDenied()
        } else {
            onGranted()
        }
        close()
    }
}
