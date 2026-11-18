#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$root/dist}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/Jake Frost.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Info.plist" "$app/Contents/Info.plist"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx12.0" -sdk "$sdk" \
    -framework AppKit -framework CoreGraphics "$root"/Sources/*.swift -o "$tmp/JakeFrost-$arch"
done
xcrun lipo -create "$tmp/JakeFrost-arm64" "$tmp/JakeFrost-x86_64" -output "$app/Contents/MacOS/JakeFrost"
xcrun lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/JakeFrost"
xcrun swift "$root/tools/MakeIcon.swift" "$tmp/icon.png"
iconset="$tmp/JakeFrost.iconset"
mkdir "$iconset"
for px in 16 32 128 256 512; do
  /usr/bin/sips -z "$px" "$px" "$tmp/icon.png" --out "$iconset/icon_${px}x${px}.png" > /dev/null
  double=$((px * 2))
  /usr/bin/sips -z "$double" "$double" "$tmp/icon.png" --out "$iconset/icon_${px}x${px}@2x.png" > /dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/JakeFrost.icns"
/usr/bin/codesign --force --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --strict "$app"
"$app/Contents/MacOS/JakeFrost" --scene-self-test
"$app/Contents/MacOS/JakeFrost" --app-smoke-test
/usr/bin/ditto --norsrc "$app" "$out/Jake Frost.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$tmp/Jake-Frost-Mac.zip"
mv -f "$tmp/Jake-Frost-Mac.zip" "$out/Jake-Frost-Mac.zip"
