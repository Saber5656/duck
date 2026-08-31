import Foundation

public enum DuckOverlayState: Equatable {
    case idle
    case nodding
    case tilt
    case bigNod
    case sleep
}

public enum DuckOverlayFrameSequence: Equatable {
    case base
    case blink
}

public struct DuckOverlayFrame: Equatable {
    public let state: DuckOverlayState
    public let index: Int
    public let sequence: DuckOverlayFrameSequence

    public init(
        state: DuckOverlayState,
        index: Int,
        sequence: DuckOverlayFrameSequence = .base
    ) {
        self.state = state
        self.index = index
        self.sequence = sequence
    }
}

public struct DuckOverlayStateMachine {
    public let tiltDelay: TimeInterval
    public let longUtteranceDuration: TimeInterval
    public let bigNodDelay: TimeInterval

    public private(set) var state: DuckOverlayState
    public private(set) var frame: DuckOverlayFrame

    private var listening: Bool
    private var stateStartedAt: TimeInterval
    private var lastObservedAt: TimeInterval
    private var silenceStartedAt: TimeInterval?
    private var longUtterance = false
    private var manualNod = false
    private let blinkDelayProvider: () -> TimeInterval
    private var nextBlinkAt: TimeInterval?
    private var blinkStartedAt: TimeInterval?

    public init(
        listening: Bool = false,
        now: TimeInterval = 0,
        tiltDelay: TimeInterval = 2,
        longUtteranceDuration: TimeInterval = 20,
        bigNodDelay: TimeInterval = 2.5,
        blinkDelayProvider: @escaping () -> TimeInterval = { Double.random(in: 3...8) }
    ) {
        self.tiltDelay = max(0, tiltDelay)
        self.longUtteranceDuration = max(0, longUtteranceDuration)
        self.bigNodDelay = max(0, bigNodDelay)
        self.blinkDelayProvider = blinkDelayProvider
        self.listening = listening
        self.state = listening ? .idle : .sleep
        self.frame = DuckOverlayFrame(state: listening ? .idle : .sleep, index: 0)
        self.stateStartedAt = now
        self.lastObservedAt = now
        self.nextBlinkAt = listening
            ? now + Self.normalizedBlinkDelay(blinkDelayProvider())
            : nil
    }

    public mutating func setListening(_ listening: Bool, at time: TimeInterval) {
        let time = monotonicTime(time)
        guard self.listening != listening || state == .sleep else { return }

        self.listening = listening
        silenceStartedAt = nil
        longUtterance = false
        manualNod = false
        enter(listening ? .idle : .sleep, at: time)
    }

    public mutating func handle(_ event: SpeechEvent, at time: TimeInterval) {
        guard listening else { return }
        let time = monotonicTime(time)

        switch event {
        case .speechStarted:
            silenceStartedAt = nil
            longUtterance = false
            manualNod = false
            enter(.nodding, at: time)

        case .speechEnded(let duration):
            silenceStartedAt = time
            longUtterance = duration >= longUtteranceDuration
            manualNod = false
            enter(.idle, at: time)
        }
    }

    public mutating func nodOnce(at time: TimeInterval) {
        let time = monotonicTime(time)
        silenceStartedAt = nil
        longUtterance = false
        manualNod = true
        enter(.nodding, at: time)
    }

    @discardableResult
    public mutating func tick(at time: TimeInterval) -> DuckOverlayFrame {
        let time = monotonicTime(time)
        let elapsed = max(0, time - stateStartedAt)

        switch state {
        case .idle:
            if let silenceStartedAt {
                let silenceDuration = max(0, time - silenceStartedAt)
                if longUtterance, silenceDuration >= bigNodDelay {
                    enter(.bigNod, at: time)
                    return frame
                }
                if !longUtterance, silenceDuration >= tiltDelay {
                    enter(.tilt, at: time)
                    return frame
                }
            }
            frame = frameForBlinkingState(.idle, at: time)

        case .nodding:
            if manualNod, elapsed >= 0.5 {
                enter(listening ? .idle : .sleep, at: time)
                return frame
            }
            frame = DuckOverlayFrame(state: .nodding, index: Int(elapsed / 0.25) % 2)

        case .tilt:
            frame = frameForBlinkingState(.tilt, at: time)

        case .bigNod:
            let index = Int(elapsed / 0.15)
            if index >= 4 {
                longUtterance = false
                silenceStartedAt = nil
                enter(.idle, at: time)
                return frame
            }
            frame = DuckOverlayFrame(state: .bigNod, index: index)

        case .sleep:
            frame = DuckOverlayFrame(state: .sleep, index: min(1, Int(elapsed / 1.0)))
        }

        return frame
    }

    public var nextTickInterval: TimeInterval {
        switch state {
        case .idle, .tilt:
            if let blinkStartedAt {
                let elapsed = max(0, lastObservedAt - blinkStartedAt)
                if elapsed < 0.15 {
                    return max(0.01, 0.15 - elapsed)
                }
                if elapsed < 0.65 {
                    return max(0.01, 0.65 - elapsed)
                }
            }

            if let nextBlinkAt {
                return min(0.5, max(0.01, nextBlinkAt - lastObservedAt))
            }
            return 0.5

        case .nodding:
            return 0.25
        case .bigNod:
            return 0.15
        case .sleep:
            return 1
        }
    }

    private mutating func enter(_ state: DuckOverlayState, at time: TimeInterval) {
        self.state = state
        stateStartedAt = time
        frame = DuckOverlayFrame(state: state, index: 0)
        blinkStartedAt = nil
        switch state {
        case .idle, .tilt:
            nextBlinkAt = listening
                ? time + Self.normalizedBlinkDelay(blinkDelayProvider())
                : nil
        default:
            nextBlinkAt = nil
        }
    }

    private mutating func monotonicTime(_ time: TimeInterval) -> TimeInterval {
        let normalized = max(lastObservedAt, time)
        lastObservedAt = normalized
        return normalized
    }

    private mutating func frameForBlinkingState(
        _ state: DuckOverlayState,
        at time: TimeInterval
    ) -> DuckOverlayFrame {
        guard listening, let nextBlinkAt else {
            return DuckOverlayFrame(state: state, index: 0)
        }

        if blinkStartedAt == nil {
            guard time >= nextBlinkAt else {
                return DuckOverlayFrame(state: state, index: 0)
            }
            blinkStartedAt = nextBlinkAt
        }

        let elapsed = max(0, time - (blinkStartedAt ?? time))
        if elapsed < 0.15 {
            return DuckOverlayFrame(state: state, index: 0, sequence: .blink)
        }
        if elapsed < 0.65 {
            return DuckOverlayFrame(state: state, index: 1, sequence: .blink)
        }

        blinkStartedAt = nil
        self.nextBlinkAt = time + Self.normalizedBlinkDelay(blinkDelayProvider())
        return DuckOverlayFrame(state: state, index: 0)
    }

    private static func normalizedBlinkDelay(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite else { return 5 }
        return min(8, max(3, delay))
    }
}
