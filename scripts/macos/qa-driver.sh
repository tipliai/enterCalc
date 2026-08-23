#!/usr/bin/env bash

set -euo pipefail

# Drives the macOS app for QA: builds it, sends input, and reads back what is on
# screen. Useful for checking behavior without a person watching the window, and
# for reproducing bugs step by step.
#
# Reading is done through the accessibility API rather than screenshots, because
# screen capture needs Screen Recording permission while this only needs
# Accessibility. That also means it reports text and structure, not colors: a
# theme bug that changes only colors will not be visible here. Run the app with
# ENTERCALC_DEBUG_LOGS=1 (the `launch` command does) and read `log` for that.

usage() {
  cat <<'EOF'
Usage:
  scripts/macos/qa-driver.sh <command> [args]

Commands:
  build                 Build the Debug macOS app.
  launch                Launch it (quitting any running copy) with debug logging.
  quit                  Quit the app.

  state                 Print the operation line, result, and mode label.
  tree                  Dump the accessibility tree (for finding new elements).

  type <keys>           Send keystrokes, e.g. type "12+5".
  enter                 Press Return (evaluate).
  key <name>            Press a named key: escape, delete, tab.

  settings-open         Open the settings sheet.
  settings-close        Close it (Escape).
  theme <name>          Pick an App theme by its visible name, e.g. theme Dark.
  popup <label> <value> Pick any settings popup value by label.

  log [n]               Print the last n lines (default 40) of the debug log.

Notes:
  Requires Accessibility permission for the terminal running this script:
  System Settings > Privacy & Security > Accessibility.

Examples:
  scripts/macos/qa-driver.sh build && scripts/macos/qa-driver.sh launch
  scripts/macos/qa-driver.sh type "12+5" && scripts/macos/qa-driver.sh enter
  scripts/macos/qa-driver.sh state
EOF
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${ENTERCALC_QA_BUILD_DIR:-$REPO_ROOT/.qa-build}"
APP_PATH="$BUILD_DIR/Build/Products/Debug/EnterCalc.app"
LOG_PATH="$BUILD_DIR/entercalc-debug.log"
APP_PROCESS="EnterCalc"

require_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "No build at $APP_PATH — run: $0 build" >&2
    exit 1
  fi
}

# Wraps osascript so a missing Accessibility permission produces an actionable
# message instead of a bare -1743.
run_osa() {
  local script="$1"
  local output
  if ! output="$(osascript -e "$script" 2>&1)"; then
    if [[ "$output" == *"-1743"* || "$output" == *"not allowed assistive"* ]]; then
      echo "Accessibility permission is required." >&2
      echo "Grant it to your terminal in System Settings > Privacy & Security > Accessibility, then retry." >&2
      exit 3
    fi
    echo "$output" >&2
    exit 1
  fi
  printf '%s\n' "$output"
}

app_is_running() {
  pgrep -x "$APP_PROCESS" >/dev/null 2>&1
}

require_running() {
  if ! app_is_running; then
    echo "$APP_PROCESS is not running — run: $0 launch" >&2
    exit 1
  fi
}

activate_app() {
  run_osa 'tell application "System Events" to tell process "'"$APP_PROCESS"'" to set frontmost to true' >/dev/null
  sleep 0.3
}

cmd_build() {
  echo "Building Debug macOS app..."
  xcodebuild \
    -project "$REPO_ROOT/apple/xcode/EnterCalc.xcodeproj" \
    -scheme EnterCalc-macOS \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | grep -E "error:|warning: unable|BUILD" || true
  require_app
  echo "Built: $APP_PATH"
}

cmd_launch() {
  require_app
  cmd_quit >/dev/null 2>&1 || true
  sleep 1
  : > "$LOG_PATH"
  # Launched directly rather than via `open` so stdout can be captured.
  ENTERCALC_DEBUG_LOGS=1 "$APP_PATH/Contents/MacOS/EnterCalc" >>"$LOG_PATH" 2>&1 &
  sleep 3
  if ! app_is_running; then
    echo "App did not start. Log:" >&2
    cat "$LOG_PATH" >&2
    exit 1
  fi
  activate_app
  echo "Launched. Debug log: $LOG_PATH"
}

cmd_quit() {
  if app_is_running; then
    killall "$APP_PROCESS" 2>/dev/null || true
    echo "Quit $APP_PROCESS"
  else
    echo "$APP_PROCESS was not running"
  fi
}

# Static text order in the main window: 1 is the settings glyph label, then the
# operation line, the result, and the mode label. Read by index because the
# calculator's own controls do not expose accessibility titles.
cmd_state() {
  require_running
  run_osa '
tell application "System Events" to tell process "'"$APP_PROCESS"'"
  set out to {}
  repeat with i from 1 to 6
    try
      set end of out to (i as text) & ": " & (value of static text i of group 1 of window 1 as text)
    end try
  end repeat
  set AppleScript'"'"'s text item delimiters to linefeed
  return out as text
end tell'
}

cmd_tree() {
  require_running
  run_osa 'tell application "System Events" to tell process "'"$APP_PROCESS"'" to return entire contents of group 1 of window 1' \
    | tr ',' '\n' | sed 's/ of application process.*//'
}

cmd_type() {
  require_running
  local keys="${1:?type needs a string, e.g. type \"12+5\"}"
  activate_app
  run_osa 'tell application "System Events" to keystroke "'"$keys"'"' >/dev/null
  sleep 0.3
  echo "typed: $keys"
}

cmd_enter() {
  require_running
  activate_app
  run_osa 'tell application "System Events" to keystroke return' >/dev/null
  sleep 0.4
  echo "pressed: return"
}

cmd_key() {
  require_running
  local name="${1:?key needs a name: escape, delete, tab}"
  local code
  case "$name" in
    escape) code=53 ;;
    delete) code=51 ;;
    tab) code=48 ;;
    *) echo "Unknown key: $name (use escape, delete, tab)" >&2; exit 2 ;;
  esac
  activate_app
  run_osa 'tell application "System Events" to key code '"$code" >/dev/null
  sleep 0.3
  echo "pressed: $name"
}

cmd_settings_open() {
  require_running
  activate_app
  run_osa 'tell application "System Events" to tell process "'"$APP_PROCESS"'" to click menu button 1 of group 1 of window 1' >/dev/null
  sleep 0.8
  echo "settings opened"
}

cmd_settings_close() {
  cmd_key escape
}

# Settings popups do expose their labels, so they can be addressed by name.
cmd_popup() {
  require_running
  local label="${1:?popup needs a label}"
  local value="${2:?popup needs a value}"
  activate_app
  run_osa '
tell application "System Events" to tell process "'"$APP_PROCESS"'"
  set target to pop up button "'"$label"'" of scroll area 1 of group 1 of window 1
  click target
  delay 0.5
  click menu item "'"$value"'" of menu 1 of target
  delay 0.5
  return "set '"$label"' to '"$value"'"
end tell'
}

cmd_theme() {
  local value="${1:?theme needs a name, e.g. Dark}"
  cmd_popup "App theme" "$value"
}

cmd_log() {
  local lines="${1:-40}"
  if [[ ! -f "$LOG_PATH" ]]; then
    echo "No log yet at $LOG_PATH — run: $0 launch" >&2
    exit 1
  fi
  tail -n "$lines" "$LOG_PATH"
}

main() {
  local command="${1:-}"
  shift || true

  case "$command" in
    build) cmd_build ;;
    launch) cmd_launch ;;
    quit) cmd_quit ;;
    state) cmd_state ;;
    tree) cmd_tree ;;
    type) cmd_type "$@" ;;
    enter) cmd_enter ;;
    key) cmd_key "$@" ;;
    settings-open) cmd_settings_open ;;
    settings-close) cmd_settings_close ;;
    theme) cmd_theme "$@" ;;
    popup) cmd_popup "$@" ;;
    log) cmd_log "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "Unknown command: $command" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
