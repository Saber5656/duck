import AVFoundation
import Foundation

enum MicrophonePermission {
    private static let requestTimeout: TimeInterval = 30

    static func requestAccess() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            let deadline = Date().addingTimeInterval(Self.requestTimeout)

            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                granted = allowed
                semaphore.signal()
            }

            while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
                guard Date() < deadline else {
                    return false
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }

            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
