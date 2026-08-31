# duck
A rubber-duck debugging companion that listens and responds with gentle backchannels.

## Development

This repository currently contains the macOS menu-bar skeleton.
Audio input, sprites, onboarding, and release packaging are intentionally out of scope for this step.

Run the local checks on macOS:

```sh
scripts/privacy-guard.sh
scripts/build-macos-app.sh
```

If Xcode's XCTest module is available, run `swift test` for the settings persistence tests.

The app bundle is written to `.build/macos/duck.app`.
