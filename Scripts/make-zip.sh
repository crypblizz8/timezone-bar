#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TimezoneBar"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
MARKETING_VERSION="${MARKETING_VERSION:-}"
ZIP_PATH="${ZIP_PATH:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE="${NOTARIZE:-0}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"

cd "$ROOT_DIR"

if [ -z "$MARKETING_VERSION" ]; then
  echo "error: MARKETING_VERSION is required, for example MARKETING_VERSION=0.2.0" >&2
  exit 1
fi

case "$NOTARIZE" in
  0 | 1) ;;
  *)
    echo "error: NOTARIZE must be 0 or 1" >&2
    exit 1
    ;;
esac

case "$ALLOW_UNSIGNED" in
  0 | 1) ;;
  *)
    echo "error: ALLOW_UNSIGNED must be 0 or 1" >&2
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

if [ -z "$SIGNING_IDENTITY" ] && [ "$ALLOW_UNSIGNED" != "1" ]; then
  echo "error: SIGNING_IDENTITY is required. Set ALLOW_UNSIGNED=1 only for a local unsigned ZIP." >&2
  exit 1
fi

if [ -z "$ZIP_PATH" ]; then
  if [ -z "$SIGNING_IDENTITY" ]; then
    ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-unsigned.zip"
  else
    ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.zip"
  fi
fi

"$ROOT_DIR/Scripts/make-app.sh"

if [ ! -d "$APP_DIR" ]; then
  echo "error: expected app bundle at $APP_DIR" >&2
  exit 1
fi

if [ -n "$SIGNING_IDENTITY" ]; then
  CODESIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
  if [ -n "$SIGNING_KEYCHAIN" ]; then
    CODESIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
  fi

  codesign "${CODESIGN_ARGS[@]}" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
else
  echo "warning: creating an unsigned ZIP for local testing" >&2
fi

mkdir -p "$DIST_DIR"

if [ "$NOTARIZE" = "1" ]; then
  UPLOAD_ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-notary-upload.zip"
  FINAL_ZIP_TMP="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.final.zip"
  trap 'rm -f "$UPLOAD_ZIP_PATH" "$FINAL_ZIP_TMP"' EXIT

  rm -f "$ZIP_PATH" "$UPLOAD_ZIP_PATH" "$FINAL_ZIP_TMP"
  ditto -c -k --keepParent "$APP_DIR" "$UPLOAD_ZIP_PATH"
  xcrun notarytool submit "$UPLOAD_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"

  ditto -c -k --keepParent "$APP_DIR" "$FINAL_ZIP_TMP"
  mv "$FINAL_ZIP_TMP" "$ZIP_PATH"
else
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "Built $ZIP_PATH"
