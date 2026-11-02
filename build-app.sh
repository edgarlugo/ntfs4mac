#!/usr/bin/env bash
# Builds ntfs4mac.app (universal: Apple Silicon + Intel) with only the Command Line Tools.
# Usage: ./build-app.sh            → build/ntfs4mac.app and build/ntfs4mac-app.zip
#        ./build-app.sh --install  → also copy it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ntfs4mac.app"
VERSION=$(sed -nE 's/^VERSION="(.*)"$/\1/p' ntfs4mac)

command -v swiftc >/dev/null || { echo "Command Line Tools missing. Run: xcode-select --install" >&2; exit 1; }

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (arm64 + x86_64)"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos13.0" \
    app/Sources/*.swift -o "build/ntfs4mac-$arch"
done
lipo -create -output "$APP/Contents/MacOS/ntfs4mac" build/ntfs4mac-arm64 build/ntfs4mac-x86_64
rm build/ntfs4mac-arm64 build/ntfs4mac-x86_64

echo "==> Assembling bundle"
sed -E "s|<string>1\.[0-9]+\.[0-9]+</string>|<string>$VERSION</string>|" app/Info.plist > "$APP/Contents/Info.plist"
install -m 755 ntfs4mac app/Resources/askpass "$APP/Contents/Resources/"
cp -R app/Resources/es.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/en.lproj"   # English strings are the keys themselves

echo "==> Drawing icon"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift app/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/icon-1024.png

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

# No extended attributes: other unzip tools would turn them into ._ files and break the signature.
rm -f build/ntfs4mac-app.zip
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP" build/ntfs4mac-app.zip
echo "✔ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/ntfs4mac.app
  ditto "$APP" /Applications/ntfs4mac.app
  echo "✔ Installed to /Applications/ntfs4mac.app"
fi
