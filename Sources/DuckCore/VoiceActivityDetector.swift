import Foundation

public enum SpeechEvent: Equatable {
    case speechStarted
    case speechEnded(duration: TimeInterval)
}

public enum VoiceActivityState: Equatable {
    case silence
    case speaking
}

public struct VADParameters: Equatable {
    public let thresholdOffsetDB: Float
    public let attackDuration: TimeInterval
    public let hangoverDuration: TimeInterval
    public let minLevelDBFS: Float
    public let initialNoiseFloorDBFS: Float
    public let noiseFloorTimeConstant: TimeInterval

    public init(
        sensitivity: DuckSensitivity = .medium,
        attackDuration: TimeInterval = 0.25,
        hangoverDuration: TimeInterval = 1.2,
        minLevelDBFS: Float = -80,
        initialNoiseFloorDBFS: Float = -60,
        noiseFloorTimeConstant: TimeInterval = 10
    ) {
        switch sensitivity {
        case .low:
            thresholdOffsetDB = 12
        case .medium:
            thresholdOffsetDB = 9
        case .high:
            thresholdOffsetDB = 6
        }
        self.attackDuration = Self.nonNegativeFinite(attackDuration, fallback: 0.25)
        self.hangoverDuration = Self.nonNegativeFinite(hangoverDuration, fallback: 1.2)

        let safeMinimum = Self.boundedDBFS(minLevelDBFS, fallback: -80)
        self.minLevelDBFS = safeMinimum

        let safeInitialNoiseFloor = Self.boundedDBFS(initialNoiseFloorDBFS, fallback: -60)
        self.initialNoiseFloorDBFS = max(safeMinimum, safeInitialNoiseFloor)
        self.noiseFloorTimeConstant = Self.nonNegativeFinite(
            noiseFloorTimeConstant,
            fallback: 10
        )
    }

    private static func nonNegativeFinite(
        _ value: TimeInterval,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard value.isFinite else { return fallback }
        return max(0, value)
    }

    private static func boundedDBFS(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(0, max(-80, value))
    }
}

public struct VoiceActivityDetector {
    public let parameters: VADParameters
    public private(set) var state: VoiceActivityState = .silence
    public private(set) var noiseFloorDBFS: Float

    private var lastObservationAt: TimeInterval?
    private var attackStartedAt: TimeInterval?
    private var silenceStartedAt: TimeInterval?
    private var speechStartedAt: TimeInterval?

    public init(parameters: VADParameters = VADParameters()) {
        self.parameters = parameters
        noiseFloorDBFS = parameters.initialNoiseFloorDBFS
    }

    public init(sensitivity: DuckSensitivity) {
        self.init(parameters: VADParameters(sensitivity: sensitivity))
    }

    public mutating func reset() {
        state = .silence
        noiseFloorDBFS = parameters.initialNoiseFloorDBFS
        lastObservationAt = nil
        attackStartedAt = nil
        silenceStartedAt = nil
        speechStartedAt = nil
    }

    public mutating func observe(rms: Float, at time: TimeInterval) -> [SpeechEvent] {
        guard time.isFinite else { return [] }
        if let lastObservationAt, time < lastObservationAt {
            return []
        }

        let levelDBFS = Self.dbFS(fromRMS: rms, floor: parameters.minLevelDBFS)
        let elapsed = elapsedSinceLastObservation(at: time)
        let thresholdDBFS = min(0, max(-80, noiseFloorDBFS + parameters.thresholdOffsetDB))

        switch state {
        case .silence:
            guard levelDBFS > thresholdDBFS else {
                attackStartedAt = nil
                updateNoiseFloor(toward: levelDBFS, elapsed: elapsed)
                return []
            }

            attackStartedAt = attackStartedAt ?? time
            guard let attackStartedAt,
                  Self.elapsed(from: attackStartedAt, to: time) >= parameters.attackDuration
            else {
                return []
            }

            state = .speaking
            self.attackStartedAt = nil
            speechStartedAt = time
            return [.speechStarted]

        case .speaking:
            guard levelDBFS < thresholdDBFS else {
                silenceStartedAt = nil
                return []
            }

            silenceStartedAt = silenceStartedAt ?? time
            guard let silenceStartedAt,
                  Self.elapsed(from: silenceStartedAt, to: time) >= parameters.hangoverDuration
            else {
                return []
            }

            state = .silence
            let start = speechStartedAt ?? time
            let duration = Self.elapsed(from: start, to: time)
            self.silenceStartedAt = nil
            speechStartedAt = nil
            updateNoiseFloor(toward: levelDBFS, elapsed: elapsed)
            return [.speechEnded(duration: duration)]
        }
    }

    public static func dbFS(fromRMS rms: Float, floor: Float = -80) -> Float {
        let safeFloor = min(0, max(-80, floor.isFinite ? floor : -80))
        guard rms.isFinite, rms > 0 else { return safeFloor }

        let level = 20 * log10(rms)
        guard level.isFinite else { return safeFloor }
        return min(0, max(safeFloor, level))
    }

    private mutating func elapsedSinceLastObservation(at time: TimeInterval) -> TimeInterval {
        defer { lastObservationAt = time }
        guard let lastObservationAt else { return 0 }
        return Self.elapsed(from: lastObservationAt, to: time)
    }

    private static func elapsed(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        let delta = end - start
        guard delta.isFinite else { return .greatestFiniteMagnitude }
        return max(0, delta)
    }

    private mutating func updateNoiseFloor(toward level: Float, elapsed: TimeInterval) {
        guard elapsed > 0, parameters.noiseFloorTimeConstant > 0 else { return }
        let alphaValue = 1 - exp(-elapsed / parameters.noiseFloorTimeConstant)
        guard alphaValue.isFinite else { return }
        let alpha = Float(min(1, max(0, alphaValue)))
        let candidate = noiseFloorDBFS + (level - noiseFloorDBFS) * alpha
        guard candidate.isFinite else { return }
        noiseFloorDBFS = min(0, max(parameters.minLevelDBFS, candidate))
    }
}
