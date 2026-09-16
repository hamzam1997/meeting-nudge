#!/bin/bash
# Unit tests for the pure logic. Offline, no windows, no system services.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -o build/unittests \
  Sources/Schedule.swift Sources/JoinLink.swift Sources/Meeting.swift Tests/main.swift
./build/unittests
