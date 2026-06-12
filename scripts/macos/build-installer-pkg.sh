#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/macos/build-installer-pkg.sh --app /path/to/EnterCalc.app \
    --installer-cert "Developer ID Installer: Your Name (TEAMID)" \
    [--out-dir dist]

Description:
  Builds a signed macOS installer package (.pkg) from an already signed .app bundle.

Notes:
  - The .app should be signed by Xcode using your Developer ID Application certificate.
  - This script signs the installer using your Developer ID Installer certificate.
EOF
}

APP_PATH=""
INSTALLER_CERT=""
OUT_DIR="dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --installer-cert)
      INSTALLER_CERT="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
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

if [[ -z "$APP_PATH" || -z "$INSTALLER_CERT" ]]; then
  echo "Missing required arguments." >&2
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
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PKG_NAME="${APP_NAME}-${SHORT_VERSION}-${BUILD_VERSION}-macOS.pkg"

mkdir -p "$OUT_DIR"
OUTPUT_PKG="$OUT_DIR/$PKG_NAME"

echo "Verifying app code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Building signed installer package..."
pkgbuild \
  --component "$APP_PATH" \
  --install-location /Applications \
  --sign "$INSTALLER_CERT" \
  "$OUTPUT_PKG"

echo "Validating installer package signature..."
pkgutil --check-signature "$OUTPUT_PKG"

echo "Installer created: $OUTPUT_PKG"
