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

### Platform Notes

- iOS and macOS use the same keyboard actions in all contexts.
- Insert key detection differs by platform implementation details:
	- iOS accepts HID usages `0x49` (Insert) and `0x75` (Help), plus function-character `U+F727`.
	- macOS accepts keyCode `114`, plus function-character `U+F727`.
- macOS additionally maps physical keypad keyCodes for digits/operators/decimal/evaluate. iOS receives these through hardware key events and characters.
- Control-modified keys are not handled by EnterCalc keyboard routing and return not-handled.

### Command Shortcuts

- Cmd + Backspace: clear all.
- Cmd + Forward Delete: clear all.
- Cmd + C: copy current result.
- Cmd + V: paste into calculator.
- Cmd + Z: undo.
- Cmd + Shift + Z: redo.
- Cmd + Y: redo.

## Overlay Priority Rules

- History overlay has highest keyboard suppression behavior for calculator input.
- Rounding overlay handles its own close/remove/adjust keys before base key routing.
- Insert only enters direct edit when no overlay is active.
