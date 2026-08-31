import AVFoundation
import Darwin
import Foundation
import VADCore

@main
struct DuckVADSpike {
    static func main() {
        let options = RunOptions(arguments: CommandLine.arguments)

        guard MicrophonePermission.requestAccess() else {
            print("permission=unavailable")
            print("status=stopped")
            exit(EXIT_FAILURE)
        }

        var detector = VoiceActivityDetector(parameters: options.vadParameters)
        let source = AudioLevelSource(bufferSize: options.bufferSize) { rms, timestamp in
            for event in detector.observe(rms: rms, at: timestamp) {
                switch event {
                case .speechStarted:
                    print("event=speechStarted")
                case .speechEnded(_, let utteranceDuration):
                    print(String(format: "event=speechEnded utteranceDuration=%.3f", utteranceDuration))
                }
            }
        }

        do {
            try source.start()
        } catch {
            print("engine=startFailed")
            print("error=\(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }

        print("permission=granted")
        print("engine=started")
        print("status=listening")

        RunLoop.main.run(until: Date().addingTimeInterval(options.duration))

        source.stop()
        print("engine=stopped")
        print("status=stopped")
    }
}

private struct RunOptions {
    private static let minimumBufferSize: AVAudioFrameCount = 256
    private static let maximumDuration: TimeInterval = 5 * 60
    private static let maximumBufferSize: AVAudioFrameCount = 65_536

    var duration: TimeInterval = 15
    var bufferSize: AVAudioFrameCount = 1_024
    var vadParameters = VADParameters()

    init(arguments: [String]) {
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--duration" where index + 1 < arguments.count:
                if let parsed = TimeInterval(arguments[index + 1]),
                   parsed.isFinite,
                   parsed > 0,
                   parsed <= Self.maximumDuration {
                    duration = parsed
                }
                index += 2
            case "--buffer-size" where index + 1 < arguments.count:
                if let parsed = UInt32(arguments[index + 1]),
                   parsed >= Self.minimumBufferSize,
                   parsed <= Self.maximumBufferSize {
                    bufferSize = AVAudioFrameCount(parsed)
                }
                index += 2
            default:
                index += 1
            }
        }
    }
}
