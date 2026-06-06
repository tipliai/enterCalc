---
title: Accessibility
permalink: /accessibility/
---

# Accessibility Features

This page is a quick guide to accessibility features available in EnterCalc

### Labels and control clarity

- Core controls in calculator, history, and settings are labeled for assistive technologies.

### Reduced Motion support

- EnterCalc respects OS Reduced Motion behavior.
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

## Platform Notes

### iOS

- Supports OS Reduced Motion, Increase Contrast, and larger text settings.
- Compact action labels and history/settings text scaling are enabled.

### macOS

- Supports OS Increase Contrast and larger text behavior.
- Compact action labels and history/settings text scaling are enabled.

## Coming Soon (v1.10)

- VoiceOver value-context improvements for expression/result readout.
- VoiceOver grouping and reading-order improvements across overlays.
- Additional end-to-end VoiceOver validation for calculator, overlays, and settings.

## Notes

- Accessibility behavior follows OS settings where supported.
- We continue to improve accessibility with each release.
