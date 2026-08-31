import AVFoundation
import Foundation
import VADCore

final class AudioLevelSource {
    typealias LevelHandler = (_ rms: Float, _ timestamp: TimeInterval) -> Void

    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount
    private let levelSink: MainQueueLevelSink
    private var isRunning = false

    init(bufferSize: AVAudioFrameCount = 1_024, onLevel: @escaping LevelHandler) {
        self.bufferSize = bufferSize
        self.levelSink = MainQueueLevelSink(onLevel: onLevel)
    }

    func start() throws {
        guard !isRunning else {
            return
        }

        let inputNode = engine.inputNode

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self, let rms = Self.rms(from: buffer) else {
                return
            }

            let timestamp = ProcessInfo.processInfo.systemUptime

            // PRIVACY: The AVAudioPCMBuffer is reduced to one Float inside this callback.
            // The buffer is not retained, copied, written, logged, or transmitted.
            self.levelSink.submit(rms: rms, timestamp: timestamp)
        }

        engine.prepare()

        do {
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private static func rms(from buffer: AVAudioPCMBuffer) -> Float? {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameCount > 0,
              channelCount > 0,
              buffer.format.commonFormat == .pcmFormatFloat32 else {
            return nil
        }

        let frameStride = buffer.format.isInterleaved
            ? max(Int(buffer.stride), channelCount)
            : max(Int(buffer.stride), 1)
        var sumOfSquares: Float = 0
        if buffer.format.isInterleaved {
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard let data = buffers.first?.mData else {
                return nil
            }

            let samples = data.assumingMemoryBound(to: Float.self)
            let (lastFrameOffset, frameOffsetOverflow) = (frameCount - 1)
                .multipliedReportingOverflow(by: frameStride)
            let (sampleCount, sampleCountOverflow) = lastFrameOffset
                .addingReportingOverflow(channelCount)
            guard !frameOffsetOverflow,
                  !sampleCountOverflow,
                  let requiredBytes = byteCount(forSampleCount: sampleCount),
                  requiredBytes <= Int(buffers.first?.mDataByteSize ?? 0) else {
                return nil
            }

            for channel in 0..<channelCount {
                let channelSamples = UnsafeBufferPointer(
                    start: samples.advanced(by: channel),
                    count: sampleCount - channel
                )
                guard let rms = AudioLevelRMS.rootMeanSquare(
                    samples: channelSamples,
                    frameCount: frameCount,
                    frameStride: frameStride
                ) else {
                    return nil
                }
                sumOfSquares += rms * rms * Float(frameCount)
            }
        } else {
            guard let channels = buffer.floatChannelData else {
                return nil
            }

            let (lastFrameOffset, frameOffsetOverflow) = (frameCount - 1)
                .multipliedReportingOverflow(by: frameStride)
            let (sampleCount, sampleCountOverflow) = lastFrameOffset
                .addingReportingOverflow(1)
            guard !frameOffsetOverflow,
                  !sampleCountOverflow,
                  let requiredBytes = byteCount(forSampleCount: sampleCount) else {
                return nil
            }

            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard buffers.count >= channelCount else {
                return nil
            }

            for channel in 0..<channelCount {
                guard requiredBytes <= Int(buffers[channel].mDataByteSize) else {
                    return nil
                }

                let channelSamples = UnsafeBufferPointer(
                    start: channels[channel],
                    count: sampleCount
                )
                guard let rms = AudioLevelRMS.rootMeanSquare(
                    samples: channelSamples,
                    frameCount: frameCount,
                    frameStride: frameStride
                ) else {
                    return nil
                }
                sumOfSquares += rms * rms * Float(frameCount)
            }
        }

        return sqrt(sumOfSquares / Float(frameCount * channelCount))
    }

    private static func byteCount(forSampleCount sampleCount: Int) -> Int? {
        guard sampleCount > 0 else {
            return nil
        }

        let (byteCount, overflow) = sampleCount.multipliedReportingOverflow(
            by: MemoryLayout<Float>.stride
        )
        return overflow ? nil : byteCount
    }
}

private final class MainQueueLevelSink {
    private let lock = NSLock()
    private let onLevel: AudioLevelSource.LevelHandler
    private var pending: (rms: Float, timestamp: TimeInterval)?
    private var deliveryScheduled = false

    init(onLevel: @escaping AudioLevelSource.LevelHandler) {
        self.onLevel = onLevel
    }

    func submit(rms: Float, timestamp: TimeInterval) {
        lock.lock()
        pending = (rms, timestamp)

        guard !deliveryScheduled else {
            lock.unlock()
            return
        }

        deliveryScheduled = true
        lock.unlock()
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        DispatchQueue.main.async { [weak self] in
            self?.deliverLatest()
        }
    }

    private func deliverLatest() {
        lock.lock()
        guard let latest = pending else {
            deliveryScheduled = false
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()

        onLevel(latest.rms, latest.timestamp)

        lock.lock()
        let shouldScheduleNext = pending != nil
        if !shouldScheduleNext {
            deliveryScheduled = false
        }
        lock.unlock()

        if shouldScheduleNext {
            scheduleDelivery()
        }
    }
}
