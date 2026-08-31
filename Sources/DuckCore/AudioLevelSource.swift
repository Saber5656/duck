import AVFoundation
import Foundation

public enum AudioLevelSourceState: Equatable {
    case stopped
    case listening
}

struct AudioLevelSourceLifecycle {
    private(set) var state: AudioLevelSourceState = .stopped

    mutating func start() -> Bool {
        guard state == .stopped else { return false }
        state = .listening
        return true
    }

    mutating func stop() -> Bool {
        guard state == .listening else { return false }
        state = .stopped
        return true
    }

    var shouldRestartAfterConfigurationChange: Bool {
        state == .listening
    }
}

enum AudioLevelRMS {
    static func rootMeanSquare(samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { rootMeanSquare(samples: $0) }
    }

    static func rootMeanSquare(samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }

        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    static func rootMeanSquare(buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard
            frameCount > 0,
            channelCount > 0,
            let channels = buffer.floatChannelData
        else {
            return 0
        }

        var sumOfSquares: Float = 0
        if buffer.format.isInterleaved {
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard let data = buffers.first?.mData else {
                return 0
            }

            let samples: UnsafeMutablePointer<Float> = data.assumingMemoryBound(to: Float.self)
            let frameStride = max(Int(buffer.stride), channelCount)
            for frame in 0..<frameCount {
                let frameStart = frame * frameStride
                for channel in 0..<channelCount {
                    let sample = samples[frameStart + channel]
                    sumOfSquares += sample * sample
                }
            }
        } else {
            let frameStride = max(Int(buffer.stride), 1)
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameCount {
                    let sample = samples[frame * frameStride]
                    sumOfSquares += sample * sample
                }
            }
        }

        return sqrt(sumOfSquares / Float(frameCount * channelCount))
    }
}

final class RMSDeliveryScheduler {
    typealias Handler = (Float) -> Void

    private let callbackQueue: DispatchQueue
    private let handler: Handler
    private let lock = NSLock()

    private var generation: UInt = 0
    private var isActive = false
    private var pendingRMS: Float?
    private var deliveryScheduled = false

    init(callbackQueue: DispatchQueue, handler: @escaping Handler) {
        self.callbackQueue = callbackQueue
        self.handler = handler
    }

    func start() {
        lock.lock()
        generation &+= 1
        isActive = true
        pendingRMS = nil
        deliveryScheduled = false
        lock.unlock()
    }

    func stop() {
        lock.lock()
        generation &+= 1
        isActive = false
        pendingRMS = nil
        deliveryScheduled = false
        lock.unlock()
    }

    func submit(_ rms: Float) {
        lock.lock()
        guard isActive else {
            lock.unlock()
            return
        }

        pendingRMS = rms
        guard !deliveryScheduled else {
            lock.unlock()
            return
        }

        deliveryScheduled = true
        let scheduledGeneration = generation
        lock.unlock()

        callbackQueue.async { [weak self] in
            self?.deliver(generation: scheduledGeneration)
        }
    }

    private func deliver(generation scheduledGeneration: UInt) {
        lock.lock()
        guard isActive, generation == scheduledGeneration else {
            lock.unlock()
            return
        }

        guard let rms = pendingRMS else {
            deliveryScheduled = false
            lock.unlock()
            return
        }
        pendingRMS = nil
        lock.unlock()

        handler(rms)

        lock.lock()
        guard isActive, generation == scheduledGeneration else {
            lock.unlock()
            return
        }

        guard pendingRMS != nil else {
            deliveryScheduled = false
            lock.unlock()
            return
        }
        lock.unlock()

        callbackQueue.async { [weak self] in
            self?.deliver(generation: scheduledGeneration)
        }
    }
}

public final class AudioLevelSource {
    public typealias RMSHandler = (Float) -> Void

    private let bufferSize: AVAudioFrameCount
    private let deliveryScheduler: RMSDeliveryScheduler
    private let lock = NSRecursiveLock()

    private var lifecycle = AudioLevelSourceLifecycle()
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?

    public var state: AudioLevelSourceState {
        lock.lock()
        defer { lock.unlock() }
        return lifecycle.state
    }

    public init(
        bufferSize: AVAudioFrameCount = 1_024,
        callbackQueue: DispatchQueue = .main,
        onRMS: @escaping RMSHandler
    ) {
        self.bufferSize = bufferSize
        self.deliveryScheduler = RMSDeliveryScheduler(
            callbackQueue: callbackQueue,
            handler: onRMS
        )
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard lifecycle.start() else { return }
        deliveryScheduler.start()
        do {
            try rebuildEngine()
            installConfigurationObserver()
        } catch {
            _ = lifecycle.stop()
            deliveryScheduler.stop()
            stopEngine()
            throw error
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        _ = lifecycle.stop()
        deliveryScheduler.stop()
        removeConfigurationObserver()
        stopEngine()
    }

    private func rebuildEngine() throws {
        stopEngine()

        let engine = AVAudioEngine()
        let input = engine.inputNode

        // PRIVACY: This tap is the only microphone buffer access path.
        input.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [deliveryScheduler] buffer, _ in
            // PRIVACY: Reduce the audio buffer to one RMS value inside the callback.
            let rms = AudioLevelRMS.rootMeanSquare(buffer: buffer)
            deliveryScheduler.submit(rms)
        }

        self.engine = engine
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopEngine()
            throw error
        }
    }

    private func stopEngine() {
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.stop()
        engine = nil
    }

    private func installConfigurationObserver() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func removeConfigurationObserver() {
        guard let configurationObserver else { return }
        NotificationCenter.default.removeObserver(configurationObserver)
        self.configurationObserver = nil
    }

    private func handleConfigurationChange() {
        lock.lock()
        defer { lock.unlock() }

        guard lifecycle.shouldRestartAfterConfigurationChange else { return }
        do {
            try rebuildEngine()
        } catch {
            _ = lifecycle.stop()
            deliveryScheduler.stop()
            removeConfigurationObserver()
            stopEngine()
        }
    }
}
