#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TimezoneBar"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
ZIP_PATH="${ZIP_PATH:-$DIST_DIR/$APP_NAME-$MARKETING_VERSION.zip}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE="${NOTARIZE:-0}"

cd "$ROOT_DIR"

case "$NOTARIZE" in
  0 | 1) ;;
  *)
    echo "error: NOTARIZE must be 0 or 1" >&2
    exit 1
    ;;
esac

if [ "$NOTARIZE" = "1" ]; then
  if [ -z "$SIGNING_IDENTITY" ]; then
    echo "error: NOTARIZE=1 requires SIGNING_IDENTITY" >&2
    exit 1
  fi

  if [ -z "$NOTARY_PROFILE" ]; then
    echo "error: NOTARIZE=1 requires NOTARY_PROFILE" >&2
    exit 1
  fi
fi

"$ROOT_DIR/Scripts/make-app.sh"

if [ ! -d "$APP_DIR" ]; then
  echo "error: expected app bundle at $APP_DIR" >&2
  exit 1
fi

if [ -n "$SIGNING_IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
else
  echo "warning: SIGNING_IDENTITY is not set; creating an unsigned ZIP" >&2
fi

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [ "$NOTARIZE" = "1" ]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"

  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "Built $ZIP_PATH"
