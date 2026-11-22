#!/bin/bash
# Run the existing Foundation-only codec tests on macOS without starting a simulator.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
package="$(mktemp -d "${TMPDIR:-/tmp}/pumpsync-host-tests.XXXXXX")"
trap 'rm -rf "$package"' EXIT
mkdir -p "$package/Sources/PumpSync" "$package/Tests/PumpSyncTests"
ln -s "$root/PumpSync/Sources/Networking/JSONCodec.swift" "$package/Sources/PumpSync/"
ln -s "$root/PumpSyncTests/JSONCodecDateTests.swift" "$package/Tests/PumpSyncTests/"
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PumpSyncHostTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PumpSync"),
        .testTarget(name: "PumpSyncTests", dependencies: ["PumpSync"])
    ]
)
SWIFT
swift test --package-path "$package" --jobs 2
