import XCTest
@testable import DuckCore

final class DuckOverlayStateMachineTests: XCTestCase {
    func testListeningStartsIdleAndOffEntersSleep() {
        var machine = DuckOverlayStateMachine(listening: true)

        XCTAssertEqual(machine.state, .idle)
        machine.setListening(false, at: 1)

        XCTAssertEqual(machine.tick(at: 1), DuckOverlayFrame(state: .sleep, index: 0))
        XCTAssertEqual(machine.tick(at: 2), DuckOverlayFrame(state: .sleep, index: 1))
    }

    func testSpeechStartsNoddingAndShortPauseTiltsAfterTwoSeconds() {
        var machine = DuckOverlayStateMachine(listening: true)

        machine.handle(.speechStarted, at: 1)
        XCTAssertEqual(machine.tick(at: 1.25), DuckOverlayFrame(state: .nodding, index: 1))

        machine.handle(.speechEnded(duration: 3), at: 2)
        XCTAssertEqual(machine.tick(at: 3.99).state, .idle)
        XCTAssertEqual(machine.tick(at: 4).state, .tilt)
    }

    func testLongUtteranceGetsBigNodBeforeTiltAndThenReturnsIdle() {
        var machine = DuckOverlayStateMachine(listening: true)

        machine.handle(.speechStarted, at: 0)
        machine.handle(.speechEnded(duration: 20), at: 20)

        XCTAssertEqual(machine.tick(at: 22).state, .idle)
        XCTAssertEqual(machine.tick(at: 22.5), DuckOverlayFrame(state: .bigNod, index: 0))
        XCTAssertEqual(machine.tick(at: 22.66), DuckOverlayFrame(state: .bigNod, index: 1))
        XCTAssertEqual(machine.tick(at: 23.1).state, .idle)
    }

    func testSpeechStartInterruptsTiltAndManualNodWorksWhileSleeping() {
        var machine = DuckOverlayStateMachine(listening: true)

        machine.handle(.speechEnded(duration: 1), at: 0)
        XCTAssertEqual(machine.tick(at: 2).state, .tilt)
        machine.handle(.speechStarted, at: 2.1)
        XCTAssertEqual(machine.state, .nodding)

        machine.setListening(false, at: 3)
        machine.nodOnce(at: 4)
        XCTAssertEqual(machine.tick(at: 4).state, .nodding)
        XCTAssertEqual(machine.tick(at: 4.5).state, .sleep)
    }

    func testIdleBlinkUsesNestedBlinkSequenceAndRandomizedDelay() {
        var machine = DuckOverlayStateMachine(
            listening: true,
            now: 0,
            blinkDelayProvider: { 3 }
        )

        XCTAssertEqual(machine.tick(at: 2.99), DuckOverlayFrame(state: .idle, index: 0))
        XCTAssertEqual(
            machine.tick(at: 3),
            DuckOverlayFrame(state: .idle, index: 0, sequence: .blink)
        )
        XCTAssertEqual(
            machine.tick(at: 3.2),
            DuckOverlayFrame(state: .idle, index: 1, sequence: .blink)
        )
        XCTAssertEqual(machine.tick(at: 3.7), DuckOverlayFrame(state: .idle, index: 0))
    }

    func testTiltBlinkReturnsToHeldBaseFrame() {
        var machine = DuckOverlayStateMachine(
            listening: true,
            now: 0,
            blinkDelayProvider: { 3 }
        )

        machine.handle(.speechEnded(duration: 1), at: 0)
        XCTAssertEqual(machine.tick(at: 2).state, .tilt)
        XCTAssertEqual(
            machine.tick(at: 5),
            DuckOverlayFrame(state: .tilt, index: 0, sequence: .blink)
        )
        XCTAssertEqual(
            machine.tick(at: 5.2),
            DuckOverlayFrame(state: .tilt, index: 1, sequence: .blink)
        )
        XCTAssertEqual(machine.tick(at: 5.7), DuckOverlayFrame(state: .tilt, index: 0))
    }

    func testOutOfOrderTimeDoesNotRewindAnimation() {
        var machine = DuckOverlayStateMachine(listening: true)

        machine.handle(.speechStarted, at: 2)
        let current = machine.tick(at: 2.25)

        XCTAssertEqual(machine.tick(at: 1), current)
    }
}
