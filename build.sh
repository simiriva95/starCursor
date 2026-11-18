#!/bin/sh
# Builds StarCursor.app (universal: Apple silicon + Intel) next to this script.
# Usage: ./build.sh && open StarCursor.app
set -e
cd "$(dirname "$0")"
APP=StarCursor.app
VERSION=1.0.1
TMP=$(mktemp -d)
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/*.swift -o "$TMP/StarCursor-$arch"
done
lipo -create "$TMP/StarCursor-arm64" "$TMP/StarCursor-x86_64" -output "$APP/Contents/MacOS/StarCursor"
rm -rf "$TMP"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>StarCursor</string>
  <key>CFBundleDisplayName</key><string>StarCursor</string>
  <key>CFBundleIdentifier</key><string>io.github.simiriva95.starcursor</string>
  <key>CFBundleExecutable</key><string>StarCursor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSAppleEventsUsageDescription</key><string>StarCursor uses AppleScript for the "Toggle mute" gesture.</string>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP"
