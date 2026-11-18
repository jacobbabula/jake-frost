#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
server=""
cleanup() {
    if [ -n "$server" ]; then kill "$server" 2>/dev/null || true; fi
    rm -rf "$tmp"
}
trap cleanup EXIT
node "$root/../relay/test-server.mjs" "$tmp/port" &
server=$!
for _ in {1..100}; do
    if [ -s "$tmp/port" ]; then break; fi
    sleep 0.1
done
test -s "$tmp/port"
xcrun swiftc -swift-version 5 "$root/Sources/FrostGift.swift" "$root/Sources/MacFriendEnvelope.swift" \
    "$root/Sources/MacOnlinePost.swift" "$root/Tests/OnlinePostProbe.swift" -o "$tmp/probe"
"$tmp/probe" "http://127.0.0.1:$(cat "$tmp/port")/api/post" \
    "$root/Tests/Fixtures/windows-online-v1.json" "${1:-$tmp/mac-online.json}"

