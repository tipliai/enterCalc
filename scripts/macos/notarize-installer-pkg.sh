#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/macos/notarize-installer-pkg.sh --pkg /path/to/EnterCalc.pkg --profile NOTARY_PROFILE

Description:
  Submits a signed macOS installer package to Apple notarization, waits for completion,
  staples the ticket to the package, and validates the result.

Notes:
  - The profile must already exist in your keychain via:
      xcrun notarytool store-credentials <PROFILE> --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>
EOF
}

PKG_PATH=""
PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkg)
      PKG_PATH="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
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

if [[ -z "$PKG_PATH" || -z "$PROFILE" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! -f "$PKG_PATH" ]]; then
  echo "Package not found: $PKG_PATH" >&2
  exit 1
fi

echo "Submitting package for notarization and waiting for result..."
xcrun notarytool submit "$PKG_PATH" \
  --keychain-profile "$PROFILE" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$PKG_PATH"

echo "Validating notarized package..."
xcrun stapler validate "$PKG_PATH"

echo "Notarization complete: $PKG_PATH"
