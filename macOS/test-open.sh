#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
: "${1:?Pass the path to the installed Jake Frost.app}"
: "${2:?Pass the Mac-authored .fpgift from CodecProbe}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 5 "$root/Sources/FrostGift.swift" "$root/Sources/SharedGiftPost.swift" "$root/Tests/LaunchServicesProbe.swift" -o "$tmp/test-open"
"$tmp/test-open" "$1" "${3:-$root/Tests/Fixtures/windows-tree.fpgift}" "$2" "$tmp/mailbox"
