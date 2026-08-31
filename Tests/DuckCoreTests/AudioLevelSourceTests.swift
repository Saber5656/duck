import AVFoundation
import XCTest
@testable import DuckCore

final class AudioLevelSourceTests: XCTestCase {
    func testRootMeanSquareReturnsZeroForEmptyAndSilentSamples() {
        XCTAssertEqual(AudioLevelRMS.rootMeanSquare(samples: []), 0)
        XCTAssertEqual(AudioLevelRMS.rootMeanSquare(samples: [0, 0, 0]), 0)
    }

    func testRootMeanSquareUsesMeanSquareAcrossSamples() {
        XCTAssertEqual(
            AudioLevelRMS.rootMeanSquare(samples: [1, -1, 1, -1]),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            AudioLevelRMS.rootMeanSquare(samples: [3, 4]),
            sqrt(12.5),
            accuracy: 0.000_001
        )
    }

    func testRootMeanSquareUsesFrameStrideForInterleavedFloatBuffer() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: true
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2

        let audioBuffer = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)[0]
        let samples = audioBuffer.mData!.assumingMemoryBound(to: Float.self)
        samples[0] = 1
        samples[1] = 0
        samples[2] = 0
        samples[3] = 1

        XCTAssertEqual(
            AudioLevelRMS.rootMeanSquare(buffer: buffer),
            sqrt(0.5),
            accuracy: 0.000_001
        )
    }

    func testRootMeanSquareHandlesNonInterleavedFloatBuffer() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2

        let channels = buffer.floatChannelData!
        channels[0][0] = 1
        channels[0][1] = 0
        channels[1][0] = 0
        channels[1][1] = 1

        XCTAssertEqual(
            AudioLevelRMS.rootMeanSquare(buffer: buffer),
            sqrt(0.5),
            accuracy: 0.000_001
        )
    }

    func testLifecycleStartAndStopAreIdempotent() {
        var lifecycle = AudioLevelSourceLifecycle()

        XCTAssertEqual(lifecycle.state, .stopped)
        XCTAssertTrue(lifecycle.start())
        XCTAssertEqual(lifecycle.state, .listening)
        XCTAssertFalse(lifecycle.start())
        XCTAssertEqual(lifecycle.state, .listening)

        XCTAssertTrue(lifecycle.stop())
        XCTAssertEqual(lifecycle.state, .stopped)
        XCTAssertFalse(lifecycle.stop())
        XCTAssertEqual(lifecycle.state, .stopped)
    }

    func testLifecycleOnlyRestartsForConfigurationChangesWhileListening() {
        var lifecycle = AudioLevelSourceLifecycle()

        XCTAssertFalse(lifecycle.shouldRestartAfterConfigurationChange)

        XCTAssertTrue(lifecycle.start())
        XCTAssertTrue(lifecycle.shouldRestartAfterConfigurationChange)

        XCTAssertTrue(lifecycle.stop())
        XCTAssertFalse(lifecycle.shouldRestartAfterConfigurationChange)
    }

    func testSourceInitialStateAndStoppedStopDoNotNeedAudioHardware() {
        let source = AudioLevelSource { _ in
            XCTFail("No RMS should be emitted without starting the audio engine")
        }

        XCTAssertEqual(source.state, .stopped)
        source.stop()
        source.stop()
        XCTAssertEqual(source.state, .stopped)
    }

    func testRMSDeliverySchedulerCoalescesPendingValues() {
        let callbackQueue = DispatchQueue(label: "duck.audio-level-test")
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondDelivered = DispatchSemaphore(value: 0)
        let valuesLock = NSLock()
        var values: [Float] = []

        let scheduler = RMSDeliveryScheduler(callbackQueue: callbackQueue) { value in
            valuesLock.lock()
            values.append(value)
            let index = values.count
            valuesLock.unlock()

            if index == 1 {
                firstStarted.signal()
                _ = releaseFirst.wait(timeout: .now() + 1)
            } else if index == 2 {
                secondDelivered.signal()
            }
        }

        scheduler.start()
        scheduler.submit(1)
        XCTAssertEqual(firstStarted.wait(timeout: .now() + 1), .success)
        scheduler.submit(2)
        scheduler.submit(3)
        releaseFirst.signal()

        XCTAssertEqual(secondDelivered.wait(timeout: .now() + 1), .success)
        scheduler.stop()

        valuesLock.lock()
        let deliveredValues = values
        valuesLock.unlock()
        XCTAssertEqual(deliveredValues, [1, 3])
    }

    func testRMSDeliverySchedulerDropsQueuedValuesAfterStop() {
        let callbackQueue = DispatchQueue(label: "duck.audio-level-stop-test")
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondDelivered = DispatchSemaphore(value: 0)
        var deliveredValues: [Float] = []
        let valuesLock = NSLock()

        let scheduler = RMSDeliveryScheduler(callbackQueue: callbackQueue) { value in
            valuesLock.lock()
            deliveredValues.append(value)
            let index = deliveredValues.count
            valuesLock.unlock()

            if index == 1 {
                firstStarted.signal()
                _ = releaseFirst.wait(timeout: .now() + 1)
            } else if index == 2 {
                secondDelivered.signal()
            }
        }

        scheduler.start()
        scheduler.submit(1)
        XCTAssertEqual(firstStarted.wait(timeout: .now() + 1), .success)
        scheduler.submit(2)
        scheduler.stop()
        releaseFirst.signal()

        XCTAssertEqual(secondDelivered.wait(timeout: .now() + 0.2), .timedOut)
        valuesLock.lock()
        let valuesAfterStop = deliveredValues
        valuesLock.unlock()
        XCTAssertEqual(valuesAfterStop, [1])
    }
}
