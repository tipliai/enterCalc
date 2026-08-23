---
title: macOS QA Driver
permalink: /macos-qa/
---

# Driving the macOS app for QA

`scripts/macos/qa-driver.sh` builds the macOS app, sends it input, and reads back what is on screen. It exists so macOS behavior can be checked and bugs reproduced step by step without a person sitting in front of the window.

## Setup

The script reads the UI through the accessibility API, so the terminal running it needs **Accessibility** permission:

System Settings → Privacy & Security → Accessibility

It deliberately does *not* use screenshots, which would additionally require Screen Recording permission.

## Usage

```bash
scripts/macos/qa-driver.sh build
scripts/macos/qa-driver.sh launch

scripts/macos/qa-driver.sh type "12+5"
scripts/macos/qa-driver.sh enter
scripts/macos/qa-driver.sh state
```

`state` prints the operation line, the result, and the mode label:

```
1: 12 + 5 =
2: 17
3: Basic
```

Other commands: `tree` (dump the accessibility tree), `key escape|delete|tab`, `settings-open` / `settings-close`, `theme <name>`, `popup <label> <value>`, `log [n]`, `quit`. Run with no arguments for the full list.

## What it can and cannot see

It reports **text and structure**, not colors. A theme bug that changes only colors is invisible to it.

For anything the UI does not state in text, `launch` runs the app with `ENTERCALC_DEBUG_LOGS=1` and captures output, so `log` can show internal state the app chose to report — for example the resolved system appearance behind the `system` theme.

## Element naming

Settings popups expose their labels and can be addressed by name (`popup "App theme" Dark`). The calculator's own display and mode label are read positionally, because they are plain text rather than named controls.

Build output goes to `.qa-build/`, which is ignored by git.
