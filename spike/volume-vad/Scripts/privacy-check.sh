#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source_patterns=(
  "SFSpeechRecognizer"
  "AVAudioFile"
  "AVAudioRecorder"
  "AVCaptureAudioFileOutput"
  "URLSession"
  "import Network"
  "NWConnection"
  "socket\\("
)

for pattern in "${source_patterns[@]}"; do
  if rg -n "$pattern" Package.swift Sources App; then
    echo "privacy-check failed: forbidden source symbol matched '$pattern'" >&2
    exit 1
  fi
done

if rg -n "com\\.apple\\.security\\.network\\.(client|server)" App/*.entitlements; then
  echo "privacy-check failed: network entitlement present" >&2
  exit 1
fi

if ! plutil -extract NSMicrophoneUsageDescription raw App/Info.plist >/dev/null; then
  echo "privacy-check failed: NSMicrophoneUsageDescription missing" >&2
  exit 1
fi

echo "privacy-check passed"
