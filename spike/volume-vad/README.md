# Duck volume-only VAD spike

This is a throwaway macOS spike for the requested volume-only VAD path. It is intentionally kept under `spike/` and is not production app code.

## What It Demonstrates

- `NSMicrophoneUsageDescription` in `App/Info.plist`.
- `AVCaptureDevice.authorizationStatus(for: .audio)` and `AVCaptureDevice.requestAccess(for: .audio)`.
- `AVAudioEngine.inputNode.installTap(onBus:bufferSize:format:)`.
- `Accelerate` / `vDSP_measqv` reduction from each input buffer to one RMS `Float`.
- Time-based VAD classification with attack and hangover durations, independent of audio buffer count.
- App Sandbox entitlement with audio input only and no network client/server entitlement.

## Privacy Boundary

Audio buffers are used only inside `Sources/DuckVADSpike/AudioLevelSource.swift` in the tap callback. The callback reduces the buffer to one RMS `Float` and returns. The code does not retain, copy, write, log, or transmit audio buffers.

Successful output logs only permission/engine status and VAD transition events. It does not log RMS values, dBFS values, thresholds, or audio-derived sample sequences.

## Defaults

| Parameter | Default |
|---|---:|
| Tap buffer request | 1024 frames |
| CLI buffer size range | 256-65536 frames |
| dBFS floor | -80 dBFS |
| Initial noise floor | -60 dBFS |
| Threshold offset | +9 dB |
| Attack | 250 ms |
| Hangover | 1.2 s |
| Noise floor EMA time constant | 10 s |
| Manual run duration | 15 s |

## Local Checks

```sh
cd spike/volume-vad
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift run VADHarness
Scripts/privacy-check.sh
Scripts/build-app.sh
```

The build script creates and ad-hoc signs `.build/DuckVADSpike.app` with `com.apple.security.app-sandbox` and `com.apple.security.device.audio-input`. It intentionally does not add `com.apple.security.network.client` or `com.apple.security.network.server`.

## Manual Checks Requiring A Real macOS Microphone Session

No real microphone, TCC, or Control Center results are claimed by this spike. These checks still require an interactive macOS session:

1. Reset the spike's microphone permission state if needed:

   ```sh
   tccutil reset Microphone dev.duck.vadspike
   ```

2. Build the bundle:

   ```sh
   cd spike/volume-vad
   Scripts/build-app.sh
   ```

3. Run the bundled executable long enough to inspect TCC and Control Center:

   ```sh
   .build/DuckVADSpike.app/Contents/MacOS/DuckVADSpike --duration 60
   ```

4. Confirm the first run shows the system microphone permission prompt using the `NSMicrophoneUsageDescription` text from `App/Info.plist`.
5. Deny access and confirm the process exits without starting `AVAudioEngine`.
6. Re-enable microphone access for the bundle in System Settings > Privacy & Security > Microphone (or rerun the command after selecting Allow in the prompt), then confirm `engine=started` appears and ordinary speech can produce `event=speechStarted` and later `event=speechEnded`.
7. Confirm no RMS, dBFS, threshold, or buffer data appears in stdout/stderr.
8. While the process is running, open Control Center and confirm `DuckVADSpike` appears as a microphone user.
9. After the duration elapses and `engine=stopped` appears, confirm `DuckVADSpike` disappears from Control Center. If no other app is using the microphone, confirm the orange microphone indicator turns off.
10. Inspect entitlements on the built bundle:

    ```sh
    codesign -d --entitlements - .build/DuckVADSpike.app
    ```

    Confirm `com.apple.security.app-sandbox` and `com.apple.security.device.audio-input` are present, and network entitlements are absent.
