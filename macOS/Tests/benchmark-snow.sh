#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
baseline="${1:-v3.3.0}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for file in DesktopEdges SnowWorld; do
  git -C "$repo" show "$baseline:macOS/Sources/$file.swift" > "$tmp/$file.swift"
done
for variant in baseline current; do
  src="$repo/macOS/Sources"
  if [[ "$variant" = baseline ]]; then src="$tmp"; fi
  files=("$src/DesktopEdges.swift" "$src/SnowWorld.swift")
  if [[ -f "$src/MacSceneMemory.swift" ]]; then files+=("$src/MacSceneMemory.swift" "$src/FrostGift.swift"); fi
  xcrun swiftc -swift-version 5 -O "${files[@]}" "$repo/macOS/Tests/SnowBenchmark.swift" -o "$tmp/$variant"
done
echo "Heavy snow with 24 ledges, median nanoseconds per active particle-step, five trials:"
echo "$baseline: $("$tmp/baseline")"
echo "current: $("$tmp/current")"
