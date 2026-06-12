---
title: macOS Installer & Notarization
permalink: /macos-installer/
---

# macOS Installer & Notarization (Local Flow)

This guide is for creating a downloadable macOS installer package for EnterCalc using a local Xcode archive.

## Release Format

For EnterCalc, the distribution format is a signed and notarized `.pkg` installer.

## One-Time Requirements

Before your first notarized release, ensure these are available in the Apple Developer account:

- `Developer ID Application` certificate (used to sign the app bundle)
- `Developer ID Installer` certificate (used to sign the `.pkg`)
- App-specific password for notarization

Install certificates locally in Keychain Access and confirm they appear in your login keychain.

## 1) Create a Release Archive in Xcode

1. Open the project in Xcode.
2. Select the `EnterCalc-macOS` target and `Release` configuration.
3. Archive the app (`Product` -> `Archive`).
4. In Organizer, use `Show in Finder` on the archive.

The archived app is usually at:

`<YourArchive>.xcarchive/Products/Applications/EnterCalc.app`

## 2) Build a Signed Installer Package

From the repository root:

```bash
scripts/macos/build-installer-pkg.sh \
  --app "/path/to/EnterCalc.xcarchive/Products/Applications/EnterCalc.app" \
  --installer-cert "Developer ID Installer: YOUR NAME (TEAMID)"
```

Output package location:

- `dist/EnterCalc-<version>-<build>-macOS.pkg`

## 3) Configure Notary Profile (One-Time)

Store notarization credentials in keychain:

```bash
xcrun notarytool store-credentials EnterCalcNotary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

This creates a reusable keychain profile named `EnterCalcNotary`.

Profile naming guidance:

- A notary profile is just a local alias in your keychain for Apple ID + Team ID + app-specific password.
- The profile name does not have to match the app name or company name.
- If you notarize multiple apps under one Apple Developer team, you can reuse one profile (for example, `tipliai-notary`).
- If you use multiple teams/accounts, create one profile per team to avoid mistakes.

## 4) Notarize and Staple the Installer

```bash
scripts/macos/notarize-installer-pkg.sh \
  --pkg "dist/EnterCalc-<version>-<build>-macOS.pkg" \
  --profile EnterCalcNotary
```

The script does all of the following:

- Submits the package to Apple notarization
- Waits for completion
- Staples the notarization ticket
- Validates the stapled package

## 5) Verify Before Distribution

Run final checks:

```bash
pkgutil --check-signature "dist/EnterCalc-<version>-<build>-macOS.pkg"
xcrun stapler validate "dist/EnterCalc-<version>-<build>-macOS.pkg"
```

## 6) Release Prep (Without Publishing Yet)

For issue #18 prep work, keep the final `.pkg` local for now and do not upload to a GitHub release yet.

Recommended prep artifacts to commit:

- Installer scripts in `scripts/macos/`
- This process documentation
- Release checklist updates

## Optional Future GitHub Actions Plan

If we automate later, a workflow can:

1. Build a signed macOS archive on `macos-latest`
2. Build the `.pkg`
3. Notarize with repository secrets
4. Upload notarized `.pkg` as a workflow artifact
5. Optionally attach it to a GitHub Release when ready

For now, local notarization remains the source of truth.
