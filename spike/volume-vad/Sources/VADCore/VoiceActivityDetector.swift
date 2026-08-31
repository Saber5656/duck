import Foundation

public enum VADState: Equatable {
    case silence
    case speaking
}

public enum VADEvent: Equatable {
    case speechStarted(at: TimeInterval)
    case speechEnded(at: TimeInterval, utteranceDuration: TimeInterval)
}

public struct VADParameters: Equatable {
    public var minLevelDBFS: Float
    public var initialNoiseFloorDBFS: Float
    public var thresholdOffsetDB: Float
    public var attackDuration: TimeInterval
    public var hangoverDuration: TimeInterval
    public var noiseFloorTimeConstant: TimeInterval

    public init(
        minLevelDBFS: Float = -80,
        initialNoiseFloorDBFS: Float = -60,
        thresholdOffsetDB: Float = 9,
        attackDuration: TimeInterval = 0.25,
        hangoverDuration: TimeInterval = 1.2,
        noiseFloorTimeConstant: TimeInterval = 10
    ) {
        self.minLevelDBFS = minLevelDBFS
        self.initialNoiseFloorDBFS = initialNoiseFloorDBFS
        self.thresholdOffsetDB = thresholdOffsetDB
        self.attackDuration = attackDuration
        self.hangoverDuration = hangoverDuration
        self.noiseFloorTimeConstant = noiseFloorTimeConstant
    }
}

public struct VoiceActivityDetector {
    public private(set) var state: VADState = .silence
    public private(set) var noiseFloorDBFS: Float

    public let parameters: VADParameters

    private var lastObservationTime: TimeInterval?
    private var attackStartedAt: TimeInterval?
    private var silenceStartedAt: TimeInterval?
    private var speechStartedAt: TimeInterval?

    public init(parameters: VADParameters = VADParameters()) {
        self.parameters = parameters
        self.noiseFloorDBFS = parameters.initialNoiseFloorDBFS
    }

    public mutating func observe(rms: Float, at time: TimeInterval) -> [VADEvent] {
        let levelDBFS = Self.dbFS(fromRMS: rms, floor: parameters.minLevelDBFS)
        let thresholdDBFS = noiseFloorDBFS + parameters.thresholdOffsetDB
        let isAboveThreshold = levelDBFS > thresholdDBFS
        let elapsed = elapsedSinceLastObservation(at: time)

        switch state {
        case .silence:
            if isAboveThreshold {
                if attackStartedAt == nil {
                    attackStartedAt = time
                }

                guard let attackStartedAt else {
                    return []
                }

                if time - attackStartedAt >= parameters.attackDuration {
                    state = .speaking
                    self.speechStartedAt = attackStartedAt
                    self.attackStartedAt = nil
                    self.silenceStartedAt = nil
                    return [.speechStarted(at: attackStartedAt)]
                }
            } else {
                attackStartedAt = nil
                updateNoiseFloor(toward: levelDBFS, elapsed: elapsed)
            }

        case .speaking:
            if isAboveThreshold {
                silenceStartedAt = nil
            } else {
                if silenceStartedAt == nil {
                    silenceStartedAt = time
                }

                guard let silenceStartedAt else {
                    return []
                }

                if time - silenceStartedAt >= parameters.hangoverDuration {
                    state = .silence
                    let startedAt = speechStartedAt ?? time
                    let duration = max(0, time - startedAt)
                    self.speechStartedAt = nil
                    self.silenceStartedAt = nil
                    updateNoiseFloor(toward: levelDBFS, elapsed: elapsed)
                    return [.speechEnded(at: time, utteranceDuration: duration)]
                }
            }
        }

        return []
    }

    public static func dbFS(fromRMS rms: Float, floor: Float = -80) -> Float {
        guard rms.isFinite, rms > 0 else {
            return floor
        }

        return max(floor, 20 * log10(rms))
    }

    private mutating func elapsedSinceLastObservation(at time: TimeInterval) -> TimeInterval {
        defer {
            lastObservationTime = time
        }

        guard let lastObservationTime else {
            return 0
        }

        return max(0, time - lastObservationTime)
    }

    private mutating func updateNoiseFloor(toward levelDBFS: Float, elapsed: TimeInterval) {
        guard elapsed > 0, parameters.noiseFloorTimeConstant > 0 else {
            return
        }

        let alpha = Float(1 - exp(-elapsed / parameters.noiseFloorTimeConstant))
        noiseFloorDBFS += (levelDBFS - noiseFloorDBFS) * alpha
        noiseFloorDBFS = max(parameters.minLevelDBFS, noiseFloorDBFS)
    }
}
