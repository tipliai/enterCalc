# EnterCalc AI Instructions

## Project summary
- This project is a native calculator app with active Apple-platform targets and a placeholder native Android target scaffold.
- Branding tagline: "EnterCalc: Your Calculation Crunching Companion".
- The repo is organized as a Swift Package, with shared calculator logic in `apple/src/shared/` and Apple app targets in `apple/src/`.
- Prefer fixing behavior in the shared module first. Only add platform-specific code when the behavior is truly UI- or OS-specific.

## Open source expectations
- Treat the repo as a public open source project: prefer clear naming, contributor-friendly structure, and changes that are easy for new maintainers to trace.
- Preserve readable history. Keep changes focused, avoid unnecessary file moves, and do not introduce gratuitous refactors unless they solve a real maintenance problem.
- Update docs when behavior, structure, build steps, or contributor workflow changes.
- Treat issue creation as public by default. When the user asks to create a "todo" in this repo, create an actual GitHub issue in `tipliai/enterCalc` and apply the closest matching existing labels.
- Call out testing gaps honestly. If an area is only manually verified, say so.
- Prefer portable build and tooling choices that other contributors can run without private infrastructure.
- Do not add local-machine assumptions, personal paths, credentials, signing assets, or generated binaries to the repo.

## Repository shape preference
- Keep the repository structure clean and approachable for a Swift/macOS/iOS calculator app.
- Similar does not mean one-to-one. Preserve the spirit of a recognizable calculator codebase: shared logic grouped together, platform-specific shells separated cleanly, resources localized centrally, and tooling/docs easy to find.
- When adding new folders or moving major files, prefer names and boundaries that fit an approachable open source calculator codebase.
- Avoid scattering platform-specific logic into the shared layer just to mirror the upstream repo. Structural familiarity matters, but clean Swift target boundaries matter more.

## Target map
- `apple/Package.swift`: source of truth for targets, platforms, and resource loading.
- `apple/src/shared/`: shared module `EnterCalcCore`. This is where calculator logic, theme definitions, localization helpers, resources, and shared utilities belong.
- `apple/src/macOS/`: the richer desktop app. This target contains the main calculator window, keyboard handling, history panel, memory overlay, settings sheet integration, and macOS window behavior.
- `apple/src/iOS/`: a leaner SwiftUI app target with the shared view model and a simplified keypad UI.
- `android/`: placeholder native Android project structure for future implementation.
- `tools/`: internal repository helper scripts.
- `apple/tests/`: currently mostly used for log capture. Test coverage appears light, so be explicit about anything that is manually verified versus untested.
- `docs/`: documentation and future supporting notes.

## Important files
- `apple/src/shared/CalculatorViewModel.swift`: primary calculator brain. Owns input state, pending operators, repeated equals behavior, history entries, memory value, display strings, and error handling. Most calculator behavior changes should start here.
- `apple/src/shared/Theme.swift`: shared palette definitions for light and dark appearance.
- `apple/src/shared/Localization.swift`: runtime localization lookup. String keys live in `apple/src/shared/Resources/*/Localizable.strings`.
- `apple/src/shared/DebugLog.swift`: opt-in debug logging controlled by `ENTERCALC_DEBUG_LOGS=1`.
- `apple/src/macOS/CalculatorWindowView.swift`: main macOS calculator UI and interaction surface. This is the largest platform file and owns history visibility, memory overlay placement, settings, and window sizing behavior.
- `apple/src/macOS/KeyCaptureView.swift`: macOS keyboard event capture glue.
- `apple/src/macOS/EnterCalcMacApp.swift`: macOS app entry point.
- `apple/src/iOS/EnterCalcIOSApp.swift`: iOS app entry point and simplified keypad layout.
- `android/README.md`: source of truth for Android scaffold boundaries and shared-resource expectations.

## Architecture guidance
- Keep calculation rules and display-state transitions in the shared view model, not in button handlers.
- Keep platform UIs thin. Buttons should call view-model methods rather than re-implementing calculator rules.
- Prefer shared abstractions over `#if canImport(...)` branches spread across unrelated files.
- When changing strings visible to users, update localization resources for all existing languages when practical. At minimum, preserve existing keys and call out any untranslated additions.
- Keep visual tokens centralized in `Theme.swift` instead of adding one-off color literals throughout views.
- If a new feature needs both shared logic and platform integration, keep the layering obvious so the relationship is easy to follow for open source contributors.
- For Android-prep changes, prioritize reusable user-facing resources (copy, localization source text, icons) without forcing cross-platform UI abstractions prematurely.

## macOS vs iOS expectations
- The macOS app is the feature-complete desktop experience. It includes keyboard support, window management, history, memory overlay behavior, settings, and more nuanced layout logic.
- The iOS app currently exposes a simpler calculator interface backed by the same `CalculatorViewModel`.
- If a feature exists only on macOS today, do not assume it should automatically be added to iOS. Make that decision deliberately.

## Common task routing
- Calculator math bug or display bug: start in `apple/src/shared/CalculatorViewModel.swift`.
- Theme or colors: start in `apple/src/shared/Theme.swift`, then adjust platform views only if layout or component usage also changes.
- Localization or language switching: check `apple/src/shared/Localization.swift` and `apple/src/shared/Resources/`.
- macOS keyboard, window, history, or memory overlay behavior: check `apple/src/macOS/CalculatorWindowView.swift` and `apple/src/macOS/KeyCaptureView.swift`.
- iOS keypad layout or interaction: check `apple/src/iOS/EnterCalcIOSApp.swift`.
- Android scaffolding or Android-ready resource planning: check `android/README.md` and `android/app/src/main/`.
- Build or local run workflow: check `apple/Package.swift` and the shared Xcode schemes.

## Build and run
- Use Swift Package Manager commands for direct builds.
- Common commands:
	- `cd apple && swift test`
	- `open apple/xcode/EnterCalc.xcodeproj`
- Use Xcode for app builds, simulator runs, archives, and signing flows.

## Development rules for AI agents
- Do not commit generated app bundles, archives, or other build outputs.
- Do not add secrets, signing material, API keys, or provisioning profiles to the repo.
- Prefer minimal, local changes that match the existing SwiftUI and Swift Package style.
- Prefer structure and naming that keep the repo intelligible to open source contributors.
- If modifying behavior that affects both platforms, verify that the shared API still fits both call sites.
- When a repo behavior is unclear, inspect the existing shared view-model flow before introducing new state.
- If making a structural change, explain why it improves maintainability and why it still fits the repo's layout.
- If tests are absent for the area you changed, say so clearly and describe the manual verification path.
- For `gh` issue comments, PR comments, and PR bodies, use real multiline markdown (for example, heredoc or `--body-file`) and never send literal escaped `\n` sequences.

## Session shorthand
- Think of the repo as: shared calculator engine plus two thin app shells.
- Shared logic first, platform UI second.
- macOS is currently the more advanced target.
- Open source maintainability and contributor clarity are first-class requirements.
- Keep the repo coherent as a shared calculator engine plus platform shells without forcing a literal clone of any upstream project.
