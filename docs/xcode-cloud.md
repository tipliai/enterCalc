# Xcode Cloud Workflow Strategy

This repository currently uses three long-lived branches that match three Xcode Cloud workflows:

- `main` -> `Main`
- `validation` -> `Validation`
- `release` -> `Release`

Xcode Cloud workflow settings are not stored in git, so apply the workflow changes below in Xcode or App Store Connect after pushing this repository update.

Current promotion flow:

1. Create a working branch from `main` for feature development.
2. Open a pull request into `main` when the feature is ready for normal integration.
3. Open a pull request from `main` into `validation` when you want QA coverage and QA builds.
4. Open a pull request from `validation` into `release` when you want release builds and distribution-ready artifacts.

## Recommended Model

Use three workflows:

1. `Validation`
2. `Main`
3. `Release`

The committed host project at `apple/xcode/EnterCalc.xcodeproj` and the shared schemes `EnterCalc-iOS` and `EnterCalc-macOS` are the required Xcode Cloud inputs.

## Workflow 1: Validation

- Product: `com.tipliai.entercalc`
- Schemes: `EnterCalc-iOS`, `EnterCalc-macOS`
- Start condition: changes pushed to `validation`
- Actions: `Build`, `Test`, plus any QA-oriented archive or internal distribution steps you use for validation builds
- Archive: enable if your QA flow depends on installable artifacts
- Distribution: optional internal QA distribution

Purpose: treat `validation` as the QA branch. This branch is promoted from `main` after normal feature integration and is the place to generate QA-facing builds before release promotion.

## Workflow 2: Main

- Product: `com.tipliai.entercalc`
- Schemes: `EnterCalc-iOS`, `EnterCalc-macOS`
- Start condition: changes pushed to `main`
- Actions: `Build`, `Test`
- Archive: disabled
- Distribution: none

Purpose: confirm that `main` stays healthy as the primary integration branch for feature pull requests.

## Workflow 3: Release

- Product: `com.tipliai.entercalc`
- Schemes: `EnterCalc-iOS`, `EnterCalc-macOS`
- Start condition: changes pushed to `release`, or manual start if you prefer tighter control
- Actions: `Archive`
- Distribution: optional TestFlight or App Store distribution

Purpose: create release artifacts from the `release` branch after changes have already passed through `main` and `validation`.

Before starting this workflow:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `apple/xcode/EnterCalc.xcodeproj/project.pbxproj`.
2. Commit the project changes.

## App Store Preflight

Before the first App Store submission, confirm all of the following:

1. `MARKETING_VERSION` in `apple/xcode/EnterCalc.xcodeproj/project.pbxproj` matches the public version you intend to ship.
2. `CURRENT_PROJECT_VERSION` in `apple/xcode/EnterCalc.xcodeproj/project.pbxproj` has been incremented for the new upload.
3. `apple/xcode/EnterCalc.xcodeproj` has committed metadata and signing updates.
4. The macOS App ID for `com.tipliai.entercalc` has App Sandbox enabled and the project is using `apple/xcode/macOS/Support/EnterCalc.entitlements`.
5. App Store Connect has the matching app record and platform setup for the bundle identifier you are archiving.
6. The Xcode Cloud release workflow archives the shared `EnterCalc-macOS` and/or `EnterCalc-iOS` schemes with the Release configuration and production bundle identifier.

## Branch Strategy

- Use short-lived working branches for feature development.
- Merge working branches into `main` by pull request.
- Promote `main` into `validation` by pull request when you want QA builds and QA signoff.
- Promote `validation` into `release` by pull request when you want shipping candidates and release distribution.
- Keep `validation` as a QA stage after `main`, not as a gate before `main`.
- Keep `release` reserved for builds that are intended to ship or closely mirror what will ship.

## Current Cleanup

If any workflow names or branch triggers in Xcode Cloud do not match `Main`/`main`, `Validation`/`validation`, and `Release`/`release`, update them to match this matrix.

If the current `Validation` workflow is still configured like a pre-`main` CI branch, update its description and any archive or distribution settings so it clearly serves the QA stage between `main` and `release`.

Local validation for both platforms can also be done directly in Xcode with the shared schemes `EnterCalc-iOS` and `EnterCalc-macOS`.
