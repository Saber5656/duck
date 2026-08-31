import XCTest
@testable import DuckCore

final class VoiceActivityDetectorTests: XCTestCase {
    func testSensitivityPresetsMatchDesignThresholds() {
        XCTAssertEqual(VADParameters(sensitivity: .low).thresholdOffsetDB, 12)
        XCTAssertEqual(VADParameters(sensitivity: .medium).thresholdOffsetDB, 9)
        XCTAssertEqual(VADParameters(sensitivity: .high).thresholdOffsetDB, 6)
    }

    func testSpeechRequiresContinuousAttackAndEmitsDurationOnHangover() {
        var detector = VoiceActivityDetector()
        var events: [SpeechEvent] = []

        feed(&detector, dbFS: -60, from: 0, through: 0.5, step: 0.05, into: &events)
        feed(&detector, dbFS: -40, from: 0.55, through: 1.5, step: 0.05, into: &events)
        feed(&detector, dbFS: -60, from: 1.55, through: 2.9, step: 0.05, into: &events)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .speechStarted)
        guard case .speechEnded(let duration) = events.last else {
            return XCTFail("expected speechEnded")
        }
        XCTAssertGreaterThan(duration, 1)
        XCTAssertEqual(detector.state, .silence)
    }

    func testSpeechDurationStartsAtSpeechStartedEventTime() {
        let parameters = VADParameters(attackDuration: 0.25, hangoverDuration: 0.25)
        var detector = VoiceActivityDetector(parameters: parameters)

        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -40), at: 0).isEmpty)
        XCTAssertEqual(
            detector.observe(rms: rms(fromDBFS: -40), at: 0.25),
            [.speechStarted]
        )
        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -60), at: 0.5).isEmpty)

        guard case .speechEnded(let duration) = detector.observe(
            rms: rms(fromDBFS: -60),
            at: 0.75
        ).first else {
            return XCTFail("expected speechEnded")
        }

        XCTAssertEqual(duration, 0.5, accuracy: 0.000_001)
    }

    func testTypingLikeBurstShorterThanAttackIsIgnored() {
        var detector = VoiceActivityDetector()
        var events: [SpeechEvent] = []

        feed(&detector, dbFS: -38, from: 0, through: 0.2, step: 0.05, into: &events)
        feed(&detector, dbFS: -60, from: 0.25, through: 2, step: 0.05, into: &events)

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(detector.state, .silence)
    }

    func testBreathWithinHangoverDoesNotEndSpeech() {
        var detector = VoiceActivityDetector()
        var events: [SpeechEvent] = []

        feed(&detector, dbFS: -40, from: 0, through: 0.3, step: 0.05, into: &events)
        feed(&detector, dbFS: -60, from: 0.35, through: 1.2, step: 0.05, into: &events)
        feed(&detector, dbFS: -40, from: 1.25, through: 1.5, step: 0.05, into: &events)
        feed(&detector, dbFS: -60, from: 1.55, through: 2.9, step: 0.05, into: &events)

        XCTAssertEqual(events.filter { $0 == .speechStarted }.count, 1)
        XCTAssertEqual(events.filter {
            if case .speechEnded = $0 { return true }
            return false
        }.count, 1)
    }

    func testNoiseFloorUpdatesInSilenceButFreezesWhileSpeaking() {
        var detector = VoiceActivityDetector()
        let initial = detector.noiseFloorDBFS

        _ = detector.observe(rms: rms(fromDBFS: -55), at: 0)
        _ = detector.observe(rms: rms(fromDBFS: -55), at: 1)
        XCTAssertGreaterThan(detector.noiseFloorDBFS, initial)

        var events: [SpeechEvent] = []
        feed(&detector, dbFS: -20, from: 1.05, through: 1.4, step: 0.05, into: &events)
        let frozen = detector.noiseFloorDBFS
        feed(&detector, dbFS: -30, from: 1.45, through: 2, step: 0.05, into: &events)
        XCTAssertEqual(detector.noiseFloorDBFS, frozen, accuracy: 0.000_001)
    }

    func testOutOfOrderObservationIsIgnored() {
        var detector = VoiceActivityDetector()
        _ = detector.observe(rms: rms(fromDBFS: -55), at: 1)
        let floor = detector.noiseFloorDBFS

        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -20), at: 0.5).isEmpty)
        XCTAssertEqual(detector.state, .silence)
        XCTAssertEqual(detector.noiseFloorDBFS, floor, accuracy: 0.000_001)
    }

    func testNonFiniteObservationTimesAreIgnoredWithoutPoisoningState() {
        var detector = VoiceActivityDetector()
        let initialFloor = detector.noiseFloorDBFS

        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -20), at: .nan).isEmpty)
        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -20), at: .infinity).isEmpty)
        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -20), at: -.infinity).isEmpty)
        XCTAssertEqual(detector.state, .silence)
        XCTAssertEqual(detector.noiseFloorDBFS, initialFloor)

        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -40), at: 0).isEmpty)
        XCTAssertEqual(
            detector.observe(rms: rms(fromDBFS: -40), at: 0.25),
            [.speechStarted]
        )
    }

    func testResetReturnsToInitialSilenceAndNoiseFloor() {
        var detector = VoiceActivityDetector(sensitivity: .high)
        _ = detector.observe(rms: rms(fromDBFS: -40), at: 0)
        _ = detector.observe(rms: rms(fromDBFS: -40), at: 0.3)
        detector.reset()

        XCTAssertEqual(detector.state, .silence)
        XCTAssertEqual(detector.noiseFloorDBFS, -60)
    }

    func testInitialNoiseFloorCannotFallBelowMinimumLevel() {
        let parameters = VADParameters(minLevelDBFS: -40, initialNoiseFloorDBFS: -80)
        var detector = VoiceActivityDetector(parameters: parameters)

        XCTAssertEqual(parameters.initialNoiseFloorDBFS, -40)
        XCTAssertEqual(detector.noiseFloorDBFS, -40)
        XCTAssertTrue(detector.observe(rms: 0, at: 0).isEmpty)
        XCTAssertEqual(detector.state, .silence)
    }

    func testNonFiniteParametersNormalizeToFiniteSafeDefaults() {
        let parameters = VADParameters(
            attackDuration: .nan,
            hangoverDuration: .infinity,
            minLevelDBFS: .nan,
            initialNoiseFloorDBFS: -.infinity,
            noiseFloorTimeConstant: -.infinity
        )

        XCTAssertEqual(parameters.attackDuration, 0.25)
        XCTAssertEqual(parameters.hangoverDuration, 1.2)
        XCTAssertEqual(parameters.minLevelDBFS, -80)
        XCTAssertEqual(parameters.initialNoiseFloorDBFS, -60)
        XCTAssertEqual(parameters.noiseFloorTimeConstant, 10)

        let positiveInfinityParameters = VADParameters(
            attackDuration: -.infinity,
            hangoverDuration: .nan,
            minLevelDBFS: .infinity,
            initialNoiseFloorDBFS: .infinity,
            noiseFloorTimeConstant: .nan
        )

        XCTAssertTrue(positiveInfinityParameters.attackDuration.isFinite)
        XCTAssertTrue(positiveInfinityParameters.hangoverDuration.isFinite)
        XCTAssertTrue(positiveInfinityParameters.minLevelDBFS.isFinite)
        XCTAssertTrue(positiveInfinityParameters.initialNoiseFloorDBFS.isFinite)
        XCTAssertTrue(positiveInfinityParameters.noiseFloorTimeConstant.isFinite)
        XCTAssertGreaterThanOrEqual(positiveInfinityParameters.attackDuration, 0)
        XCTAssertGreaterThanOrEqual(positiveInfinityParameters.hangoverDuration, 0)
        XCTAssertGreaterThanOrEqual(positiveInfinityParameters.noiseFloorTimeConstant, 0)
    }

    func testExtremeFiniteDBFSParametersAndRMSStayBounded() {
        let parameters = VADParameters(
            minLevelDBFS: -Float.greatestFiniteMagnitude,
            initialNoiseFloorDBFS: Float.greatestFiniteMagnitude
        )
        var detector = VoiceActivityDetector(parameters: parameters)

        XCTAssertEqual(parameters.minLevelDBFS, -80)
        XCTAssertEqual(parameters.initialNoiseFloorDBFS, 0)
        XCTAssertTrue(detector.observe(rms: .greatestFiniteMagnitude, at: 0).isEmpty)
        XCTAssertTrue(detector.noiseFloorDBFS.isFinite)
        XCTAssertTrue(detector.observe(rms: .leastNonzeroMagnitude, at: 1).isEmpty)
        XCTAssertTrue(detector.noiseFloorDBFS.isFinite)
        XCTAssertTrue(VoiceActivityDetector.dbFS(
            fromRMS: .greatestFiniteMagnitude,
            floor: .greatestFiniteMagnitude
        ).isFinite)
    }

    func testExactThresholdDoesNotStartHangover() {
        let parameters = VADParameters(attackDuration: 0, hangoverDuration: 0.25)
        var detector = VoiceActivityDetector(parameters: parameters)
        let thresholdRMS = rms(fromDBFS: -51)

        XCTAssertEqual(
            detector.observe(rms: rms(fromDBFS: -40), at: 0),
            [.speechStarted]
        )
        XCTAssertTrue(detector.observe(rms: thresholdRMS, at: 1).isEmpty)
        XCTAssertTrue(detector.observe(rms: thresholdRMS, at: 1.25).isEmpty)
        XCTAssertEqual(detector.state, .speaking)

        XCTAssertTrue(detector.observe(rms: rms(fromDBFS: -60), at: 2).isEmpty)
        guard case .speechEnded(let duration) = detector.observe(
            rms: rms(fromDBFS: -60),
            at: 2.25
        ).first else {
            return XCTFail("expected speechEnded")
        }
        XCTAssertEqual(duration, 2.25, accuracy: 0.000_001)
    }

    func testExtremeFiniteObservationTimesKeepDurationFinite() {
        let parameters = VADParameters(attackDuration: 0, hangoverDuration: 0)
        var detector = VoiceActivityDetector(parameters: parameters)
        let earliest = -TimeInterval.greatestFiniteMagnitude
        let latest = TimeInterval.greatestFiniteMagnitude

        XCTAssertEqual(
            detector.observe(rms: rms(fromDBFS: -40), at: earliest),
            [.speechStarted]
        )

        guard case .speechEnded(let duration) = detector.observe(
            rms: rms(fromDBFS: -60),
            at: latest
        ).first else {
            return XCTFail("expected speechEnded")
        }

        XCTAssertTrue(duration.isFinite)
        XCTAssertEqual(duration, TimeInterval.greatestFiniteMagnitude)
    }

    private func feed(
        _ detector: inout VoiceActivityDetector,
        dbFS: Float,
        from start: TimeInterval,
        through end: TimeInterval,
        step: TimeInterval,
        into events: inout [SpeechEvent]
    ) {
        var time = start
        while time <= end + 0.000_001 {
            events.append(contentsOf: detector.observe(rms: rms(fromDBFS: dbFS), at: time))
            time += step
        }
    }

    private func rms(fromDBFS dbFS: Float) -> Float {
        pow(10, dbFS / 20)
    }
}
