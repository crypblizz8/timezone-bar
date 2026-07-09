#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/TimezoneBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-local.timezonebar}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"

cd "$ROOT_DIR"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}" \
    swift build -c release --cache-path "$ROOT_DIR/.build/swiftpm-cache"
BIN_DIR="$(CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}" \
    swift build -c release --cache-path "$ROOT_DIR/.build/swiftpm-cache" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/TimezoneBar" "$MACOS_DIR/TimezoneBar"
RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -type d -name 'TimezoneBar_*.bundle' -print -quit)"
if [ -n "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
else
  echo "error: resource bundle was not produced" >&2
  exit 1
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TimezoneBar</string>
  <key>CFBundleIdentifier</key>
  <string>__BUNDLE_IDENTIFIER__</string>
  <key>CFBundleName</key>
  <string>TimezoneBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__MARKETING_VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__BUILD_VERSION__</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_VERSION" "$CONTENTS_DIR/Info.plist"

echo "Built $APP_DIR"
