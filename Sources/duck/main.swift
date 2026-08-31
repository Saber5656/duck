import AppKit
import AVFoundation
import DuckCore
import ServiceManagement

final class DuckAppDelegate: NSObject, NSApplicationDelegate {
    private let settings: DuckSettingsStore
    private var statusItem: NSStatusItem?
    private var listeningItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var positionItems: [DuckPosition: NSMenuItem] = [:]
    private var sensitivityItems: [DuckSensitivity: NSMenuItem] = [:]
    private var audioSource: AudioLevelSource?
    private var vad = VoiceActivityDetector()
    private var overlay: DuckOverlayController?
    private var onboarding: DuckOnboardingController?
    private var microphonePermissionDenied = false
    private var isRequestingMicrophonePermission = false

    init(settings: DuckSettingsStore = DuckSettingsStore()) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        syncLaunchAtLoginSetting()
        configureOverlay()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.menu = buildMenu()

        refreshMicrophonePermissionState()
        refreshMenuState()

        let isExistingInstallation = settings.hasPersistedLegacySettings && !settings.hasCompletedOnboarding
        if isExistingInstallation {
            settings.hasCompletedOnboarding = true
        }

        if settings.hasCompletedOnboarding || isExistingInstallation {
            if settings.isListening, !startListening(showError: false) {
                settings.isListening = false
                overlay?.setListening(false)
                refreshMenuState()
            }
        } else {
            settings.isListening = false
            overlay?.setListening(false)
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioSource?.stop()
    }

    private func configureOverlay() {
        do {
            overlay = try DuckOverlayController.fromMainBundle(
                position: settings.position,
                listening: settings.isListening
            )
            overlay?.show()
        } catch {
            overlay = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let listening = NSMenuItem(
            title: "Listening",
            action: #selector(toggleListening(_:)),
            keyEquivalent: ""
        )
        listening.target = self
        menu.addItem(listening)
        listeningItem = listening

        let nod = NSMenuItem(
            title: "Nod once",
            action: #selector(nodOnce(_:)),
            keyEquivalent: ""
        )
        nod.target = self
        menu.addItem(nod)

        menu.addItem(.separator())

        let positionMenu = NSMenu()
        for position in DuckPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(selectPosition(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = position.rawValue
            positionMenu.addItem(item)
            positionItems[position] = item
        }
        let positionRoot = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionRoot.submenu = positionMenu
        menu.addItem(positionRoot)

        let sensitivityMenu = NSMenu()
        for sensitivity in DuckSensitivity.allCases {
            let item = NSMenuItem(
                title: sensitivity.displayName,
                action: #selector(selectSensitivity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = sensitivity.rawValue
            sensitivityMenu.addItem(item)
            sensitivityItems[sensitivity] = item
        }
        let sensitivityRoot = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        sensitivityRoot.submenu = sensitivityMenu
        menu.addItem(sensitivityRoot)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        let privacy = NSMenuItem(
            title: "Privacy & About...",
            action: #selector(showPrivacyAndAbout(_:)),
            keyEquivalent: ""
        )
        privacy.target = self
        menu.addItem(privacy)

        let microphoneSettings = NSMenuItem(
            title: "Open Microphone Settings",
            action: #selector(openMicrophoneSettings(_:)),
            keyEquivalent: ""
        )
        microphoneSettings.target = self
        menu.addItem(microphoneSettings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleListening(_ sender: NSMenuItem) {
        guard onboarding == nil else { return }

        if settings.isListening {
            settings.isListening = false
            audioSource?.stop()
            overlay?.setListening(false)
        } else if startListening(showError: true) {
            settings.isListening = true
            overlay?.setListening(true)
        }
        refreshMenuState()
    }

    @objc private func nodOnce(_ sender: NSMenuItem) {
        overlay?.nodOnce()
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let position = DuckPosition(rawValue: rawValue)
        else {
            return
        }

        settings.position = position
        overlay?.position = position
        refreshMenuState()
    }

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let sensitivity = DuckSensitivity(rawValue: rawValue)
        else {
            return
        }

        settings.sensitivity = sensitivity
        vad = VoiceActivityDetector(sensitivity: sensitivity)
        refreshMenuState()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            settings.launchAtLogin.toggle()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login could not be updated"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        refreshMenuState()
    }

    @objc private func showPrivacyAndAbout(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "duck"
        alert.informativeText = """
        duck reads microphone buffers only long enough to reduce each one to a single loudness value.
        The buffer is discarded immediately. No recording, speech recognition, or network access is used.

        The orange microphone indicator is expected while Listening is on. Turn Listening off here to release the microphone.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openMicrophoneSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func refreshMenuState() {
        listeningItem?.isEnabled = onboarding == nil
        listeningItem?.state = settings.isListening ? .on : .off
        launchAtLoginItem?.state = settings.launchAtLogin ? .on : .off

        for (position, item) in positionItems {
            item.state = settings.position == position ? .on : .off
        }

        for (sensitivity, item) in sensitivityItems {
            item.state = settings.sensitivity == sensitivity ? .on : .off
        }

        refreshStatusTitle()
    }

    private func syncLaunchAtLoginSetting() {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            settings.launchAtLogin = true
        case .notRegistered, .notFound:
            settings.launchAtLogin = false
        @unknown default:
            settings.launchAtLogin = false
        }
    }

    private func refreshStatusTitle() {
        if settings.isListening {
            statusItem?.button?.title = "duck"
            statusItem?.button?.toolTip = "duck is listening"
        } else if microphonePermissionDenied {
            statusItem?.button?.title = "duck ⚠"
            statusItem?.button?.toolTip = "Microphone permission is needed"
        } else {
            statusItem?.button?.title = "duck off"
            statusItem?.button?.toolTip = "duck is not listening"
        }
    }

    private func startListening(showError: Bool) -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            requestMicrophonePermission()
            return false
        case .denied, .restricted:
            microphonePermissionDenied = true
            if showError {
                let alert = NSAlert()
                alert.messageText = "Microphone permission is needed"
                alert.informativeText = "Allow duck in System Settings, then try Listening again."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    openMicrophoneSettings(alert)
                }
            }
            refreshStatusTitle()
            return false
        @unknown default:
            microphonePermissionDenied = true
            refreshStatusTitle()
            return false
        }

        if audioSource == nil {
            audioSource = AudioLevelSource(callbackQueue: .main) { [weak self] rms in
                self?.consume(rms: rms)
            }
        }

        guard let audioSource else { return false }
        do {
            try audioSource.start()
            vad = VoiceActivityDetector(sensitivity: settings.sensitivity)
            microphonePermissionDenied = false
            overlay?.setListening(true)
            return true
        } catch {
            if showError {
                let alert = NSAlert()
                alert.messageText = "Listening could not be started"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return false
        }
    }

    private func requestMicrophonePermission() {
        guard !isRequestingMicrophonePermission else { return }
        isRequestingMicrophonePermission = true

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRequestingMicrophonePermission = false

                if granted, self.startListening(showError: true) {
                    self.settings.isListening = true
                    self.overlay?.setListening(true)
                } else {
                    self.settings.isListening = false
                    self.microphonePermissionDenied = !granted
                    self.audioSource?.stop()
                    self.overlay?.setListening(false)
                }

                self.refreshMenuState()
            }
        }
    }

    private func refreshMicrophonePermissionState() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermissionDenied = false
        case .denied, .restricted:
            microphonePermissionDenied = true
        case .notDetermined:
            microphonePermissionDenied = false
        @unknown default:
            microphonePermissionDenied = true
        }
    }

    private func consume(rms: Float) {
        let time = ProcessInfo.processInfo.systemUptime
        for event in vad.observe(rms: rms, at: time) {
            overlay?.handle(event)
        }
    }

    private func showOnboarding() {
        let controller = DuckOnboardingController(
            onDemoNod: { [weak self] in
                self?.overlay?.nodOnce()
            },
            onGranted: { [weak self] in
                self?.handleOnboardingGranted()
            },
            onDenied: { [weak self] in
                self?.handleOnboardingDenied()
            }
        )
        onboarding = controller
        refreshMenuState()
        controller.showWindow(nil)
    }

    private func handleOnboardingGranted() {
        settings.hasCompletedOnboarding = true
        if startListening(showError: true) {
            settings.isListening = true
            overlay?.setListening(true)
        } else {
            settings.isListening = false
            overlay?.setListening(false)
        }
        onboarding = nil
        refreshMenuState()
    }

    private func handleOnboardingDenied() {
        settings.hasCompletedOnboarding = true
        settings.isListening = false
        microphonePermissionDenied = true
        audioSource?.stop()
        overlay?.setListening(false)
        onboarding = nil
        refreshMenuState()
    }
}

let app = NSApplication.shared
let delegate = DuckAppDelegate()
app.delegate = delegate
app.run()
