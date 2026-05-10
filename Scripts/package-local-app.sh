#!/bin/zsh
set -euo pipefail

CONFIGURATION="release"
SKIP_BUILD="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="QuotaBar"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
if [[ "$SKIP_BUILD" != "true" ]]; then
  swift build --product "$APP_NAME" --configuration "$CONFIGURATION"
fi

BIN_DIR="$ROOT_DIR/.build/$CONFIGURATION"
if [[ ! -x "$BIN_DIR/$APP_NAME" ]]; then
  HOST_TRIPLE="$(swift -print-target-info | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["triple"])')"
  BIN_DIR="$ROOT_DIR/.build/$HOST_TRIPLE/$CONFIGURATION"
fi
EXECUTABLE="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Built executable not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>QuotaBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.quotabar.local</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>QuotaBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 QuotaBar.</string>
</dict>
</plist>
PLIST

cat > "$RESOURCES_DIR/AppIcon.placeholder.txt" <<'TEXT'
QuotaBar v2 local app icon placeholder.
Replace this file with AppIcon.icns when a final icon is available.
TEXT

echo "Created $APP_DIR"
