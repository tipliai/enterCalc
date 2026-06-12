#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/macos/build-installer-dmg.sh --app /path/to/EnterCalc.app [--out-dir dist/macOS] [--output /custom/path/EnterCalc-v1.0.0.dmg] [--volume-name "EnterCalc Installer"] [--background docs/images/dmg-background.png] [--manual-layout]

Description:
  Builds a drag-and-drop DMG that contains EnterCalc.app and an Applications symlink.
  Applies Finder window customization for a polished drag-to-install flow.

  With --manual-layout, the script pauses after mounting and staging so you can
  manually arrange icons/window/background in Finder. Press Enter in the terminal
  to continue and finalize the DMG.

Notes:
  - The .app should already be signed by Xcode using your Developer ID Application certificate.
  - This script does not require a Developer ID Installer certificate.
EOF
}

APP_PATH=""
OUT_DIR="dist/macOS"
OUTPUT_PATH=""
VOLUME_NAME="EnterCalc Installer"
BACKGROUND_PATH="docs/images/dmg-background.png"
MANUAL_LAYOUT=false

# Finder window origin.
WINDOW_LEFT=120
WINDOW_TOP=120

# Window size and icon coordinates are derived from the background image.
WINDOW_WIDTH=700
WINDOW_HEIGHT=420
ICON_SIZE=128
TEXT_SIZE=13
APP_ICON_X=180
APP_ICON_Y=190
APPS_ICON_X=520
APPS_ICON_Y=190

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
    --background)
      BACKGROUND_PATH="${2:?Missing value for --background}"
      shift 2
      ;;
    --manual-layout)
      MANUAL_LAYOUT=true
      shift
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

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "Background image not found: $BACKGROUND_PATH" >&2
  exit 1
fi

BG_DIMENSIONS="$(sips -g pixelWidth -g pixelHeight "$BACKGROUND_PATH" 2>/dev/null)"
BG_WIDTH="$(echo "$BG_DIMENSIONS" | awk '/pixelWidth:/ {print $2; exit}')"
BG_HEIGHT="$(echo "$BG_DIMENSIONS" | awk '/pixelHeight:/ {print $2; exit}')"

if [[ -n "$BG_WIDTH" && -n "$BG_HEIGHT" ]]; then
  WINDOW_WIDTH="$BG_WIDTH"
  WINDOW_HEIGHT="$BG_HEIGHT"
fi

# Position icons to stay centered and balanced for the chosen background size.
APP_ICON_X=$((WINDOW_WIDTH * 26 / 100))
APPS_ICON_X=$((WINDOW_WIDTH * 74 / 100))
APP_ICON_Y=$((WINDOW_HEIGHT * 43 / 100))
APPS_ICON_Y="$APP_ICON_Y"

if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
  echo "A mounted volume with this name already exists: /Volumes/$VOLUME_NAME" >&2
  echo "Please eject it first, then re-run." >&2
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

TMP_DIR="$(mktemp -d)"
RW_DMG="$TMP_DIR/${APP_NAME}-rw.dmg"
MOUNT_DIR=""
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Verifying app code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

APP_SIZE_KB="$(du -sk "$APP_PATH" | awk '{print $1}')"
DMG_SIZE_KB=$((APP_SIZE_KB + 180000))
if (( DMG_SIZE_KB < 250000 )); then
  DMG_SIZE_KB=250000
fi

echo "Creating temporary writable DMG..."
hdiutil create \
  -size "${DMG_SIZE_KB}k" \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  -layout SPUD \
  -type UDIF \
  -ov \
  "$RW_DMG" > /dev/null

echo "Mounting writable DMG..."
ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

if [[ -z "$DEVICE" ]]; then
  echo "Unable to detect mounted DMG device." >&2
  exit 1
fi

if [[ ! -d "$MOUNT_DIR" ]]; then
  echo "Unable to detect mounted DMG path: $MOUNT_DIR" >&2
  exit 1
fi

echo "Preparing DMG contents..."
ditto "$APP_PATH" "$MOUNT_DIR/$APP_NAME.app"

echo "Verifying staged app code signature..."
codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/$APP_NAME.app"

ln -s /Applications "$MOUNT_DIR/Applications"

mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_PATH" "$MOUNT_DIR/.background/background.png"

# Keep packaging folders out of normal Finder view.
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
if command -v xcrun >/dev/null 2>&1; then
  xcrun SetFile -a V "$MOUNT_DIR/.background" >/dev/null 2>&1 || true
  xcrun SetFile -a V "$MOUNT_DIR/.background/background.png" >/dev/null 2>&1 || true
fi
if [[ -d "$MOUNT_DIR/.fseventsd" ]]; then
  rm -rf "$MOUNT_DIR/.fseventsd"
fi

echo "Applying Finder window layout..."
if [[ "$MANUAL_LAYOUT" == true ]]; then
  echo "Manual layout mode enabled."
  echo "1) Arrange icons and window in Finder for '/Volumes/$VOLUME_NAME'."
  echo "2) When done, return here and press Enter to continue."
  open "$MOUNT_DIR"
  read -r -p "Press Enter after manual layout is complete... "

  # Ensure the background assignment is persisted even after manual adjustments.
  if ! osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set viewOptions to the icon view options of container window
    set background picture of viewOptions to file ".background:background.png"
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
  then
    echo "Warning: Could not reapply background in manual layout mode." >&2
  fi
else
if ! osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    try
      set sidebar width of container window to 0
    end try
    set the bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WINDOW_WIDTH)), $((WINDOW_TOP + WINDOW_HEIGHT))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set text size of viewOptions to $TEXT_SIZE
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to true
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $APP_ICON_Y}
    set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}
    try
      set position of item ".background" of container window to {-240, -240}
    end try
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF
then
  echo "Warning: Finder layout customization failed. Continuing with default Finder layout." >&2
fi
fi

sync

echo "Detaching writable DMG..."
hdiutil detach "$DEVICE" -quiet
DEVICE=""

echo "Converting to compressed DMG..."
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$OUTPUT_DMG" > /dev/null

echo "DMG created: $OUTPUT_DMG"
