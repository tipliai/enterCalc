#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/macos/build-installer-dmg.sh --app /path/to/EnterCalc.app [--out-dir dist/macOS] [--output /custom/path/EnterCalc-v1.0.0.dmg] [--volume-name "EnterCalc Installer"]

Description:
  Builds a drag-and-drop DMG that contains EnterCalc.app and an Applications symlink.

Notes:
  - The .app should already be signed by Xcode using your Developer ID Application certificate.
  - This script does not require a Developer ID Installer certificate.
EOF
}

APP_PATH=""
OUT_DIR="dist/macOS"
OUTPUT_PATH=""
VOLUME_NAME="EnterCalc Installer"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:?Missing value for --app}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:?Missing value for --out-dir}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:?Missing value for --output}"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="${2:?Missing value for --volume-name}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  echo "Missing required argument: --app" >&2
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH" .app)"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found at: $INFO_PLIST" >&2
  exit 1
fi

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

if [[ -n "$OUTPUT_PATH" ]]; then
  OUTPUT_DMG="$OUTPUT_PATH"
else
  OUTPUT_DMG="$OUT_DIR/${APP_NAME}-v${SHORT_VERSION}.dmg"
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"

STAGING_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "Verifying app code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Preparing DMG staging layout..."
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"

echo "Verifying staged app code signature..."
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME.app"

ln -s /Applications "$STAGING_DIR/Applications"

echo "Building DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "DMG created: $OUTPUT_DMG"
