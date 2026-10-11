---
title: Accessibility
permalink: /accessibility/
---

# Accessibility Features

This page is a quick guide to accessibility features available in EnterCalc.

### Labels and control clarity

- Core controls in calculator, history, and settings are labeled for assistive technologies.
- Configurable function keys announce the *function* they currently carry — "Undo", "Square Root" — rather than the glyph drawn on them, so the label follows the key when it is reassigned.

### Reassigning a function key without a press-and-hold

- Function keys are changed by pressing and holding on iOS, or from the **Edit** item in a key's context menu on macOS (#131). Neither is easy for a VoiceOver user, and the Mac hint names the context menu rather than press-and-hold.
- The folded-down corner that marks a changeable key is decoration only and hidden from VoiceOver; the key's hint and its action carry the same information.
- Every configurable key therefore also offers a **Edit Action** action. Activating it opens the same chooser, whose options are ordinary buttons that commit on a single tap or click. The key currently assigned is marked as selected.
- On iOS the keys carry a hint describing the press-and-hold for anyone who can use it.

### Reduced Motion support

- EnterCalc respects OS Reduced Motion behavior on iOS and macOS.
- Non-essential motion is reduced, including shimmer/parallax-style effects and transition-heavy animation paths.

### Increased Contrast support

- EnterCalc respects OS Increase Contrast on both iOS and macOS.
- Increased contrast is applied across all themes: system, light, dark, and blue.
- Calculator surfaces and overlays use stronger foreground/background separation when enabled.

### Dark mode support

- EnterCalc supports both light mode and dark mode.
- By default, EnterCalc follows the device appearance setting (system theme).
- Users can still choose light, dark, or blue theme manually through in-app settings.

### Larger text support

- Dynamic Type and larger-text scaling are supported across major surfaces.
- This includes display text, action rows, history UI, and settings/about text.
- Shrink-to-fit behavior is retained where needed to preserve layout fit.
- The result and operation line grow to use the room the display has, including when you drag the keypad smaller.

### Text Size setting

- **Settings ▸ Text Size** follows the system text size by default (**Use System Size**).
- Turn it off to choose one of five sizes for EnterCalc only: Extra Small, Small, Default, Large, and Extra Large.
- The chosen size applies to Settings, history, and the panels the same way the system's larger text does, and makes the calculator's numbers larger or smaller. Key sizes stay the same at every setting.

## Platform Notes

### iOS

- Supports OS Reduced Motion, Increase Contrast, and larger text settings.
- Compact action labels and history/settings text scaling are enabled.

### macOS

- Supports OS Reduced Motion, Increase Contrast, and larger text behavior.
- Compact action labels and history/settings text scaling are enabled.

## Planned for 1.2.0

These VoiceOver improvements did not make 1.1.0 and are planned for 1.2.0 ([#145](https://github.com/tipliai/enterCalc/issues/145)):

- Meaningful readout of the expression and result, with changes announced.
- Overlays that keep VoiceOver focus inside them, read in a logical order, and close with the escape gesture.
- End-to-end VoiceOver validation of the calculator, overlays, and settings on iPhone, iPad, and Mac.

## Notes

- Accessibility behavior follows OS settings where supported.
- We continue to improve accessibility with each release.
