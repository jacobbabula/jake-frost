#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 5 "$root/Sources/FrostGift.swift" "$root/Sources/SharedGiftPost.swift" "$root/Tests/SharedPostProbe.swift" -o "$tmp/shared-probe"
"$tmp/shared-probe" "$@"
