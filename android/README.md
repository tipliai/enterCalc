# Android Placeholder

This directory reserves the native Android app layout for EnterCalc.

The Android app is intentionally not implemented yet. This scaffold exists so Android work can land alongside the current Apple-platform app targets without restructuring the repository later.

## Planned structure

- `android/build.gradle.kts` — root Gradle build placeholder
- `android/settings.gradle.kts` — module/include placeholder
- `android/app/` — native Android application module placeholder
- `android/app/src/main/java/com/tipliai/entercalc/` — Kotlin package root placeholder
- `android/app/src/main/res/` — Android resource root placeholder

## Shared resources strategy

Use existing shared assets as source inputs when Android implementation begins:

- Localization source: `apple/src/shared/Resources/*/Localizable.strings`
- Brand icon source: `apple/src/shared/Resources/EnterCalc.icon/Assets/EnterCalc-1024x1024.png`
- Product naming/tagline source: `README.md`

The goal is to keep user-facing copy and branding consistent across Apple and Android targets while still using native platform implementations.
