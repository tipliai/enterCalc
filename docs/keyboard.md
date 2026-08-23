---
title: Keyboard Actions
permalink: /keyboard/
---

# EnterCalc Keyboard Actions and Context Matrix

This document defines keyboard behavior currently implemented in EnterCalc for iOS and macOS.

Sources:
- iOS key routing: apple/src/iOS/EnterCalcIOSApp.swift
- macOS key routing: apple/src/macOS/CalculatorWindowView.swift

## Global Notes
- End is treated like Escape for calculator state in base/direct-edit contexts.
- Backspace and Forward Delete are intentionally treated the same for operand deletion in base/direct-edit contexts.

## Keyboard Matrix

| Key | Base | Direct edit | Rounding overlay | History overlay |
| --- | --- | --- | --- | --- |
| Insert | Enter direct edit; caret to trailing boundary | Already in direct edit; no extra action | Blocked while overlay is active | Blocked while overlay is active |
| Left Arrow | Move display caret left (activates direct edit if possible) | Move display caret left | Decrease rounding precision step | Suppressed |
| Right Arrow | Move display caret right (activates direct edit if possible) | Move display caret right | Increase rounding precision step | Suppressed |
| Down Arrow | Open rounding overlay | Open rounding overlay | No-op (consumed) | Suppressed |
| Up Arrow | No mapped action | No mapped action | Close rounding overlay | Suppressed |
| Shift + Up Arrow | Increase display size (20pt) | Increase display size | Increase display size | Increase display size |
| Shift + Down Arrow | Decrease display size (20pt) | Decrease display size | Decrease display size | Decrease display size |
| Shift + Left Arrow | iPad: go to the page on the **right** | Same | Same | Same |
| Shift + Right Arrow | iPad: go to the page on the **left** | Same | Same | Same |
| Escape | Clear all | Exit direct edit | Remove rounding and close overlay | Close overlay |
| End | Clear all | Exit direct edit | Close overlay | Close overlay |
| Backspace | Delete one char/digit via model backspace | Delete one char/digit before caret | Remove rounding and close overlay | Close overlay |
| Forward Delete | Delete one char/digit via model backspace | Delete one char/digit before caret | Remove rounding and close overlay | Clear history and close overlay |
| Return / Enter / Keypad Enter | Evaluate | Exit direct edit | Close overlay | Close overlay |
| Digits 0-9 | Input digit | Insert at display caret | Not handled here | Suppressed |
| Decimal . | Input decimal separator | Insert decimal at display caret | Not handled here | Suppressed |
| + - * / | Set operator | Set operator (exits direct edit in model flow) | Not handled here | Suppressed |
| % | Apply percent | Apply percent | Not handled here | Suppressed |
| ( and ) | Input parentheses | Input parentheses | Not handled here | Suppressed |
| = | Evaluate | Evaluate path applies; direct edit Enter key exits edit | Not handled here | Suppressed |
| Currency symbols ($, €, £, etc.) | Activate currency input mode with symbol | Same behavior at caret position | Not handled here | Suppressed |

### Currency Mode

The calculator is in currency mode exactly when a currency symbol is showing; there is no separate mode selection. Entering one — by typing a currency symbol as above, or with the on-screen currency key beside the mode label — switches the mode label from **Basic** to **Currency**.

The on-screen key toggles: pressing it once applies the symbol chosen in Settings, and pressing it again leaves currency mode and removes the symbol without changing the entered value. It clears whichever symbol is active, including one typed on a hardware keyboard that differs from the configured one, so it is always a reliable way back to Basic.

Which symbol the key applies is chosen in Settings. It defaults to the device region's currency (en-GB gives £, en-US gives $, de-DE gives €) until the user picks one.

### Platform Notes

- iOS and macOS use the same keyboard actions in all contexts.
- Insert key detection differs by platform implementation details:
	- iOS accepts HID usages `0x49` (Insert) and `0x75` (Help), plus function-character `U+F727`.
	- macOS accepts keyCode `114`, plus function-character `U+F727`.
- macOS additionally maps physical keypad keyCodes for digits/operators/decimal/evaluate. iOS receives these through hardware key events and characters.
- Control-modified keys are not handled by EnterCalc keyboard routing and return not-handled.

### Resizing the display (macOS)

The split between the display and the keypad can be dragged, which leaves it unreachable without a pointer. **Shift + Up/Down Arrow** moves it in 20-point steps, within the same limits the drag handle respects, and stops at either end rather than wrapping.

These are menu commands under **View → Increase / Decrease Display Size**, not just key bindings, so they are discoverable and reachable by VoiceOver. The menu owns the shortcut: the app's key monitor deliberately ignores Shift + Up/Down so a single press applies a single step, and so Shift + Down does not open the rounding overlay the way a bare Down Arrow does.

The step is not animated — it lands immediately, matching how dragging behaves.

### Switching pages (iPad)

**Shift + Left/Right Arrow** moves between calculator pages, as menu commands so they are discoverable and reachable by VoiceOver.

The direction looks inverted at first glance and is deliberate: the arrow points the way the *pages* move, matching the swipe. Dragging left brings the page on the right into view, so Shift + Left does the same. Requested this way in #83.

Shift + Left past the last page **opens a new page**, the same as swiping in that direction, so the shortcut is not a more limited way to get around than the gesture. Shift + Right stops at the first page rather than wrapping.

macOS has no equivalent because its pages are separate windows — see below.

### Navigating between windows (macOS)

Investigated for #83 and deliberately **not** implemented. macOS already cycles an app's windows with **Cmd + `** (a system shortcut, on by default), and every calculator window appears in the standard **Window** menu. Adding Shift + Left/Right on top would duplicate that, take two more key combinations away from the calculator, and mean teaching the local key monitor to ignore them — the same trap that made Shift + Down open the rounding overlay instead of resizing. The app's key monitor passes Cmd + ` straight through, so window cycling already works.

### Command Shortcuts

- Cmd + Backspace: clear all.
- Cmd + Forward Delete: clear all.
- Cmd + C: copy current result.
- Cmd + Shift + C: copy the current operation.
- Cmd + V: paste into calculator.
- Cmd + Z: undo.
- Cmd + Shift + Z: redo.
- Cmd + Y: redo.

## Overlay Priority Rules

- History overlay has highest keyboard suppression behavior for calculator input.
- Rounding overlay handles its own close/remove/adjust keys before base key routing.
- Insert only enters direct edit when no overlay is active.
