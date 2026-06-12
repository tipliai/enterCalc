#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/macos/notarize-distribution.sh --file /path/to/EnterCalc.dmg --profile NOTARY_PROFILE

Description:
  Submits a distribution artifact (DMG or PKG) for Apple notarization, waits for completion,
  staples the notarization ticket, and validates the result.

Notes:
  - The profile must already exist in your keychain via:
      xcrun notarytool store-credentials <PROFILE> --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>
EOF
}

FILE_PATH=""
PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      FILE_PATH="$2"
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

if [[ -z "$FILE_PATH" || -z "$PROFILE" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! -f "$FILE_PATH" ]]; then
  echo "File not found: $FILE_PATH" >&2
  exit 1
fi

echo "Submitting artifact for notarization and waiting for result..."
xcrun notarytool submit "$FILE_PATH" \
  --keychain-profile "$PROFILE" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$FILE_PATH"

echo "Validating notarized artifact..."
xcrun stapler validate "$FILE_PATH"

echo "Notarization complete: $FILE_PATH"
