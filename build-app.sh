#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT_DIR="${1:-$ROOT/dist}"
APP="$OUTPUT_DIR/Codex Weekly.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift test
swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/CodexWeekly" "$CONTENTS/MacOS/CodexWeekly"
cp "$ROOT/README.md" "$CONTENTS/Resources/README.md"

# Build a complete multi-resolution macOS icon from the 1024px master.
ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size="${spec%% *}"
    name="${spec#* }"
    sips -z "$size" "$size" "$ROOT/Assets/AppIcon-1024-v2.png" \
        --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>Codex Weekly</string>
    <key>CFBundleExecutable</key><string>CodexWeekly</string>
    <key>CFBundleIdentifier</key><string>local.codex.weekly</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Codex Weekly</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.2</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Local utility for Codex quota display</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
rm -f "$OUTPUT_DIR/Codex-Weekly-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/Codex-Weekly-macOS.zip"

echo "Built: $APP"
echo "Archive: $OUTPUT_DIR/Codex-Weekly-macOS.zip"
