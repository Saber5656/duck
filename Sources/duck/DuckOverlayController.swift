import AppKit
import DuckCore
import Foundation

enum DuckOverlayError: LocalizedError {
    case resourceMissing(String)
    case invalidManifest(String)
    case imageLoadFailed(URL)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "Missing duck sprite resource: \(name)"
        case .invalidManifest(let message):
            return "Invalid duck sprite manifest: \(message)"
        case .imageLoadFailed(let url):
            return "Could not load duck sprite image at \(url.path)"
        }
    }
}

private struct SpriteSheetManifest: Decodable {
    let image: String
    let sheetSizePx: PixelSize
    let states: [String: SpriteState]
}

private struct PixelSize: Decodable {
    let width: Int
    let height: Int
}

private struct SpriteState: Decodable {
    let frames: [SpriteFrame]
    let blink: SpriteAnimation?
}

private struct SpriteAnimation: Decodable {
    let trigger: String
    let delayMs: DelayRange
    let loop: Bool
    let frames: [SpriteFrame]
    let returnTo: String
}

private struct DelayRange: Decodable {
    let min: Int
    let max: Int
}

private struct SpriteFrame: Decodable {
    let name: String
    let rect: [Int]
    let durationMs: Int
}

private final class DuckSpriteSheet {
    private let manifest: SpriteSheetManifest
    private let image: NSImage
    private var frameCache: [String: CGImage] = [:]

    init(manifestURL: URL, imageURL: URL) throws {
        let data = try Data(contentsOf: manifestURL)
        manifest = try JSONDecoder().decode(SpriteSheetManifest.self, from: data)
        guard manifest.sheetSizePx.width > 0, manifest.sheetSizePx.height > 0 else {
            throw DuckOverlayError.invalidManifest("sheet size must be positive")
        }
        for (stateName, state) in manifest.states {
            try Self.validate(frames: state.frames, stateName: stateName, sheetSize: manifest.sheetSizePx)
            if let blink = state.blink {
                guard blink.trigger == "random-delay", !blink.loop, blink.returnTo == stateName else {
                    throw DuckOverlayError.invalidManifest("invalid blink animation for state " + stateName)
                }
                guard blink.delayMs.min >= 0, blink.delayMs.min <= blink.delayMs.max else {
                    throw DuckOverlayError.invalidManifest("invalid blink delay for state " + stateName)
                }
                try Self.validate(frames: blink.frames, stateName: stateName + ".blink", sheetSize: manifest.sheetSizePx)
            }
        }
        guard let image = NSImage(contentsOf: imageURL) else {
            throw DuckOverlayError.imageLoadFailed(imageURL)
        }
        self.image = image
    }

    private static func validate(
        frames: [SpriteFrame],
        stateName: String,
        sheetSize: PixelSize
    ) throws {
        for frame in frames {
            guard frame.rect.count == 4 else {
                throw DuckOverlayError.invalidManifest("frame \(frame.name) has an invalid rect")
            }
            let x = frame.rect[0]
            let y = frame.rect[1]
            let width = frame.rect[2]
            let height = frame.rect[3]
            guard
                x >= 0,
                y >= 0,
                width > 0,
                height > 0,
                x + width <= sheetSize.width,
                y + height <= sheetSize.height,
                frame.durationMs > 0
            else {
                throw DuckOverlayError.invalidManifest(
                    "frame " + frame.name + " in " + stateName + " is outside the sheet"
                )
            }
        }
    }

    func image(for frame: DuckOverlayFrame) -> CGImage? {
        guard let state = manifest.states[frame.state.manifestKey] else {
            return nil
        }

        let frames: [SpriteFrame]
        switch frame.sequence {
        case .base:
            frames = state.frames
        case .blink:
            frames = state.blink?.frames ?? []
        }

        guard frames.indices.contains(frame.index)
        else {
            return nil
        }

        let sprite = frames[frame.index]
        if let cached = frameCache[sprite.name] {
            return cached
        }

        let x = sprite.rect[0]
        let y = sprite.rect[1]
        let width = sprite.rect[2]
        let height = sprite.rect[3]
        let sourceRect = NSRect(
            x: CGFloat(x),
            y: CGFloat(manifest.sheetSizePx.height - y - height),
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let targetSize = NSSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2)
        let target = NSImage(size: targetSize)
        target.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        target.unlockFocus()

        var proposedRect = NSRect(origin: .zero, size: targetSize)
        guard let rendered = target.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        frameCache[sprite.name] = rendered
        return rendered
    }
}

private extension DuckOverlayState {
    var manifestKey: String {
        switch self {
        case .idle:
            return "idle"
        case .nodding:
            return "nodding"
        case .tilt:
            return "tilt"
        case .bigNod:
            return "bigNod"
        case .sleep:
            return "sleep"
        }
    }
}

final class DuckOverlayController {
    private let spriteSheet: DuckSpriteSheet
    private let screenProvider: () -> NSScreen?
    private var machine: DuckOverlayStateMachine
    private let window: NSWindow
    private var timer: Timer?

    var position: DuckPosition {
        didSet {
            updateWindowPosition()
        }
    }

    fileprivate init(
        spriteSheet: DuckSpriteSheet,
        position: DuckPosition,
        listening: Bool,
        screenProvider: @escaping () -> NSScreen? = { NSScreen.screens.first }
    ) {
        self.spriteSheet = spriteSheet
        self.position = position
        self.screenProvider = screenProvider
        machine = DuckOverlayStateMachine(listening: listening, now: ProcessInfo.processInfo.systemUptime)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.contentsGravity = .resizeAspect
        window.contentView?.layer?.contentsScale = screenProvider()?.backingScaleFactor ?? 2
    }

    deinit {
        timer?.invalidate()
    }

    static func fromMainBundle(
        position: DuckPosition,
        listening: Bool
    ) throws -> DuckOverlayController {
        guard let manifestURL = Bundle.main.url(
            forResource: "duck",
            withExtension: "json",
            subdirectory: "Sprites"
        ) else {
            throw DuckOverlayError.resourceMissing("Sprites/duck.json")
        }
        guard let imageURL = Bundle.main.url(
            forResource: "duck",
            withExtension: "svg",
            subdirectory: "Sprites"
        ) else {
            throw DuckOverlayError.resourceMissing("Sprites/duck.svg")
        }
        let spriteSheet = try DuckSpriteSheet(manifestURL: manifestURL, imageURL: imageURL)
        return DuckOverlayController(
            spriteSheet: spriteSheet,
            position: position,
            listening: listening
        )
    }

    func show() {
        updateWindowPosition()
        refresh()
        window.orderFrontRegardless()
        scheduleTimer()
    }

    func setListening(_ listening: Bool) {
        machine.setListening(listening, at: ProcessInfo.processInfo.systemUptime)
        refresh()
        scheduleTimer()
    }

    func handle(_ event: SpeechEvent) {
        machine.handle(event, at: ProcessInfo.processInfo.systemUptime)
        refresh()
        scheduleTimer()
    }

    func nodOnce() {
        machine.nodOnce(at: ProcessInfo.processInfo.systemUptime)
        refresh()
        scheduleTimer()
    }

    private func refresh() {
        let frame = machine.tick(at: ProcessInfo.processInfo.systemUptime)
        window.contentView?.layer?.contents = spriteSheet.image(for: frame)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: machine.nextTickInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.refresh()
            self.scheduleTimer()
        }
    }

    private func updateWindowPosition() {
        guard let screen = screenProvider() else { return }
        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 16
        let origin: NSPoint

        switch position {
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - margin,
                y: visibleFrame.minY + margin
            )
        case .bottomLeft:
            origin = NSPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - margin,
                y: visibleFrame.maxY - size.height - margin
            )
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + margin,
                y: visibleFrame.maxY - size.height - margin
            )
        }

        window.setFrameOrigin(origin)
    }
}
