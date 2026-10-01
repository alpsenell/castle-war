#!/bin/sh
# Build for the simulator and (re)launch on the given simulator UDIDs.
cd "$(dirname "$0")"
xcodebuild -project KaleSavasi.xcodeproj -scheme KaleSavasi -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build -quiet build 2>&1 | grep -E "error|BUILD FAILED" | head -30
APP=build/Build/Products/Debug-iphonesimulator/KaleSavasi.app
for U in "$@"; do xcrun simctl terminate "$U" com.alpsenel.kalesavasi >/dev/null 2>&1; xcrun simctl install "$U" "$APP" && xcrun simctl launch "$U" com.alpsenel.kalesavasi; done
