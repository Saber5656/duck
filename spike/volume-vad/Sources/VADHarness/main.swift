import Darwin
import Foundation
import VADCore

@main
struct VADHarness {
    static func main() {
        var failures: [String] = []

        run("ordinary speech produces start and end", failures: &failures) {
            var detector = VoiceActivityDetector()
            var events: [VADEvent] = []

            feed(&detector, dbFS: -60, from: 0.00, through: 0.50, step: 0.05, into: &events)
            feed(&detector, dbFS: -40, from: 0.55, through: 1.50, step: 0.05, into: &events)
            feed(&detector, dbFS: -60, from: 1.55, through: 2.90, step: 0.05, into: &events)

            guard events.count == 2 else {
                throw HarnessFailure("expected 2 events, got \(events.count)")
            }

            guard case .speechStarted = events[0] else {
                throw HarnessFailure("expected first event to be speechStarted")
            }

            guard case .speechEnded(_, let duration) = events[1], duration > 1.0 else {
                throw HarnessFailure("expected second event to be speechEnded with duration > 1.0")
            }
        }

        run("silence does not produce events", failures: &failures) {
            var detector = VoiceActivityDetector()
            var events: [VADEvent] = []

            feed(&detector, dbFS: -62, from: 0.00, through: 3.00, step: 0.05, into: &events)

            guard events.isEmpty else {
                throw HarnessFailure("expected no events, got \(events.count)")
            }

            guard detector.state == .silence else {
                throw HarnessFailure("expected silence state")
            }
        }

        run("short bursts do not pass attack gate", failures: &failures) {
            var detector = VoiceActivityDetector()
            var events: [VADEvent] = []

            feed(&detector, dbFS: -60, from: 0.00, through: 0.50, step: 0.05, into: &events)
            feed(&detector, dbFS: -38, from: 0.55, through: 0.65, step: 0.05, into: &events)
            feed(&detector, dbFS: -60, from: 0.70, through: 1.20, step: 0.05, into: &events)
            feed(&detector, dbFS: -38, from: 1.25, through: 1.35, step: 0.05, into: &events)
            feed(&detector, dbFS: -60, from: 1.40, through: 2.00, step: 0.05, into: &events)

            guard events.isEmpty else {
                throw HarnessFailure("expected no events, got \(events.count)")
            }

            guard detector.state == .silence else {
                throw HarnessFailure("expected silence state")
            }
        }

        run("attack and hangover use elapsed time across observation cadence", failures: &failures) {
            let parameters = VADParameters(
                attackDuration: 0.25,
                hangoverDuration: 0.50
            )
            var detector = VoiceActivityDetector(parameters: parameters)
            var events: [VADEvent] = []

            events += detector.observe(rms: rms(fromDBFS: -60), at: 0.00)
            events += detector.observe(rms: rms(fromDBFS: -40), at: 1.00)
            events += detector.observe(rms: rms(fromDBFS: -40), at: 1.10)
            events += detector.observe(rms: rms(fromDBFS: -40), at: 1.24)
            guard events.isEmpty else {
                throw HarnessFailure("attack emitted before 250 ms")
            }

            events += detector.observe(rms: rms(fromDBFS: -40), at: 1.25)
            guard events.count == 1, case .speechStarted(let start) = events[0] else {
                throw HarnessFailure("expected speechStarted at the attack boundary")
            }
            try assertEqual(start, 1.00, accuracy: 0.000_001)

            events += detector.observe(rms: rms(fromDBFS: -60), at: 1.50)
            events += detector.observe(rms: rms(fromDBFS: -60), at: 1.99)
            guard events.count == 1 else {
                throw HarnessFailure("hangover ended before 500 ms")
            }

            events += detector.observe(rms: rms(fromDBFS: -60), at: 2.00)
            guard events.count == 2, case .speechEnded(let end, _) = events[1] else {
                throw HarnessFailure("expected speechEnded at the hangover boundary")
            }
            try assertEqual(end, 2.00, accuracy: 0.000_001)
        }

        run("adaptive noise floor tracks quiet input without triggering speech", failures: &failures) {
            let parameters = VADParameters(noiseFloorTimeConstant: 1.0)
            var detector = VoiceActivityDetector(parameters: parameters)

            _ = detector.observe(rms: rms(fromDBFS: -55), at: 0.0)
            _ = detector.observe(rms: rms(fromDBFS: -55), at: 1.0)
            _ = detector.observe(rms: rms(fromDBFS: -55), at: 2.0)
            _ = detector.observe(rms: rms(fromDBFS: -55), at: 3.0)

            guard detector.noiseFloorDBFS > -60, detector.noiseFloorDBFS < -54 else {
                throw HarnessFailure("noise floor did not adapt toward quiet input")
            }

            let noiseEvents = detector.observe(rms: rms(fromDBFS: -47), at: 3.1)
            guard noiseEvents.isEmpty, detector.state == .silence else {
                throw HarnessFailure("adapted quiet input triggered speech")
            }
        }

        run("RMS reduction preserves strided samples", failures: &failures) {
            let samples: [Float] = [1.0, 99.0, 9.0, 3.0, 99.0, 9.0]
            let reduced = samples.withUnsafeBufferPointer {
                AudioLevelRMS.rootMeanSquare(
                    samples: $0,
                    frameCount: 2,
                    frameStride: 3
                )
            }

            guard let reduced else {
                throw HarnessFailure("RMS reducer rejected valid strided input")
            }
            try assertEqual(reduced, sqrt(5.0), accuracy: 0.000_001)
        }

        run("RMS converts to dBFS with floor", failures: &failures) {
            try assertEqual(VoiceActivityDetector.dbFS(fromRMS: 0), -80, accuracy: 0.001)
            try assertEqual(VoiceActivityDetector.dbFS(fromRMS: -1), -80, accuracy: 0.001)
            try assertEqual(VoiceActivityDetector.dbFS(fromRMS: 0.1), -20, accuracy: 0.001)
        }

        if failures.isEmpty {
            print("VADHarness passed")
        } else {
            failures.forEach { print("VADHarness failed: \($0)") }
            exit(EXIT_FAILURE)
        }
    }

    private static func run(
        _ name: String,
        failures: inout [String],
        body: () throws -> Void
    ) {
        do {
            try body()
            print("pass: \(name)")
        } catch {
            failures.append("\(name): \(error)")
        }
    }

    private static func assertEqual(_ actual: Float, _ expected: Float, accuracy: Float) throws {
        guard abs(actual - expected) <= accuracy else {
            throw HarnessFailure("expected \(expected), got \(actual)")
        }
    }

    private static func assertEqual(
        _ actual: TimeInterval,
        _ expected: TimeInterval,
        accuracy: TimeInterval
    ) throws {
        guard abs(actual - expected) <= accuracy else {
            throw HarnessFailure("expected \(expected), got \(actual)")
        }
    }
}

private struct HarnessFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func feed(
    _ detector: inout VoiceActivityDetector,
    dbFS: Float,
    from start: TimeInterval,
    through end: TimeInterval,
    step: TimeInterval,
    into events: inout [VADEvent]
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
