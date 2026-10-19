#!/bin/bash
set -eu
cd "$(dirname "$0")"
CACHE_DIR="$(mktemp -d /private/tmp/G870-swift-cache.XXXXXX)"
trap '/bin/rm -rf "$CACHE_DIR"' EXIT
mkdir -p G870ControlCenter.app/Contents/MacOS
cp src/AppInfo.plist G870ControlCenter.app/Contents/Info.plist
xcrun swiftc -parse-as-library -O -target x86_64-apple-macos15.5 -module-cache-path "$CACHE_DIR" src/G870Monitor.swift src/CurveEditor.swift src/ModeProfile.swift -o G870ControlCenter.app/Contents/MacOS/G870Monitor
codesign --force --sign - G870ControlCenter.app
codesign --verify --verbose G870ControlCenter.app
