---
title: 1.1.0 QA Plan
permalink: /qa-1-1-0/
---

# EnterCalc 1.1.0 QA Plan

Manual checks for the 1.1.0 release. Each section names the PR it covers and says what was already verified automatically, so QA time goes to the things that genuinely need a person.

Automated coverage lives in [tests.md](tests.md). The macOS driver used for several of these checks is described in [macos-qa.md](macos-qa.md).

## Decide these first

Three points where an implementation choice was made that is cheap to reverse now and expensive after release.

### Currencies with no single-glyph symbol

The calculator engine accepts a **single character** as a currency symbol. That excludes CHF, Nordic `kr`, PLN `zł` and CZK `Kč`, so those regions currently fall back to `$` — wrong for a Swiss or Swedish user. Supporting them means letting the engine hold a multi-character symbol, which touches parsing and display. This decides what the currency picker can offer, so it is worth settling before release.

### Currency key placement

The currency key sits in the mode row, bottom-right of the display, where VAT and TIP are planned to go. The UI was undecided when it was built, so confirm the placement.

### Three documented behaviors were overturned

Each had a passing test asserting the old result. They are intentional corrections, not broken tests, but they are behaviors existing users may have learned:

1. `5% + 3%` was `0.08`, now `8%`. Extended to subtraction (`10% − 4%` is `6%`) for coherence. `×` and `÷` deliberately unchanged — they combine percentages rather than accumulate them, so `9% × 9%` is `0.81%`, not `81%`.
2. `$6 + 200%` was `$12`, now `$18` — the percent applies to the amount instead of replacing it.
3. All Clear used to switch currency mode off; it now stays on.

## Page switching — #83

The swipe-intent change was driven on the iPad simulator: a 12pt horizontal drift starting on a digit key now enters nothing and turns no page, while a 400pt swipe pages normally and still creates a new page past the last one. There is a deliberate dead band between the two — a keypad key gives up on its tap at 8pt of horizontal travel, and paging does not engage until 18pt, so a slide in between does nothing. That is the intended fix: a slip of that size is not a clear press or a clear swipe.

**The keyboard shortcuts were not driven.** Sending hardware keys to the simulator needs the Mac's display awake, and it was asleep for this pass — the same limitation that blocked the macOS driver.

1. **iPad with a hardware keyboard:** Shift + Left moves to the page on the **right**, Shift + Right to the page on the **left**. This looks inverted; it is deliberate — the arrow points the way the pages move, matching the swipe. Confirm it feels right, and say so if it does not, because it is one line to flip.
2. Shift + Left on the last page opens a new page, the same as swiping. Shift + Right on the first page does nothing rather than wrapping.
3. Both appear under **View** in the menu bar, translated, and are reachable by VoiceOver.
4. **⇧⌘C copies the operation** on both platforms, while ⌘C still copies the result. Worth checking carefully: both platforms intercept keyboard events before the menus see them, so this needed handling in two places, not just the menu item. Without that it would have silently copied the result instead.
5. **Swipe feel:** with pages open, check that ordinary keypad use never turns a page, and that a deliberate swipe still feels responsive rather than sticky. The thresholds are named constants in `CalculatorPagerGestureIntent` if they want tuning.
6. **Theme fade:** set two pages to different themes — Dark and Light — and switch between them. The change should crossfade over about a quarter-second rather than cutting. Check with Reduce Motion on, where it should cut instantly instead.
7. **macOS:** confirm Cmd + ` still cycles calculator windows and that the Window menu lists them. #83 asked whether Shift + Arrow should do this; the answer taken was no — see [keyboard.md](keyboard.md) for why.

## macOS theme sync — PR #97

The fix rests entirely on this check: the repro could not be reproduced automatically, because the macOS QA driver reads text and structure but not colors.

1. Set macOS to Dark Mode, then set the calculator theme to **Light**.
2. Quit and reopen the calculator. Open a **new window** with `+`. This is the case that used to fail — a new window has not been through a focus cycle.
3. In that window, switch the theme to **System**. Header and body should both go dark immediately, with no half-dark window.
4. Still on System, flip macOS between Light and Dark in System Settings. The app should follow without needing focus or a restart.
5. Check the settings sheet and the history and rounding overlays in both themes — these resolve the color scheme separately and should match the window.

## Currency mode — PR #100

The toggle cycle was verified on the iOS simulator. macOS and layout were not.

1. **macOS:** type `5`, press the currency key. Display becomes `$5`, label switches Basic → Currency, key takes the accent color.
2. Press it again: symbol clears, label returns to Basic, and the `5` is still there.
3. Check the key does not crowd the mode label at the smallest window width, or in landscape on iPhone.
4. Tap or click the display body while in currency mode — it should still copy. The mode row now takes taps for the key, so this is the regression risk.
5. Change the currency symbol in Settings while a value is on screen; the symbol should update immediately, not on the next entry.
6. Confirm the default symbol matches your region before ever opening Settings.
7. Type `€` on a hardware keyboard, then press the currency key. It should clear the `€`, not swap it for the configured symbol.
8. With currency on, press **AC**. Currency mode should stay on. Verified on iOS; check macOS.
9. Confirm the currency symbol picker sits under **Language** in Settings on both platforms.

## Percent — PR #98

Engine behavior is unit-tested; these cover display, history and formatting interaction.

1. `9 % + 9 % =` on both platforms shows `18%`.
2. Open history and check the entry reads `18%`, not `0.18`.
3. Copy the `18%` result and paste it back in. Round-tripping a percent result is not unit-tested.
4. Repeat with result rounding enabled — rounding and the percent display interact.
5. In currency mode, `10 + 25 % =` gives `$12.50`. This returned `$2.50` before the fix.
6. In currency mode, `10 + .25 =` gives `$10.25`. Plain decimal addition must be untouched.
7. In currency mode, `10 × 10 % =` gives `$1`. Multiply and divide were deliberately left alone.

## Feedback and ratings — PR #99

1. Settings → About shows the version on the left and **Feedback** on the right, one row, no star, not bold.
2. On a device, tap **Feedback** — it should open the support page.
3. Same on macOS, and check the About group looks right at the bottom of the settings sheet.
4. The rating prompt cannot be triggered on demand: it needs 3 distinct days of use, 25 completed calculations, and fires after a completed calculation. Worth confirming over a few days of real use that it appears **once** and never mid-calculation.

## Keypad and input — PRs #103, #104

1. Settings no longer offers **Use equals button**.
2. Default keypad in English shows `Enter`; switch language and it becomes `=`. Verified live on iOS with German; check macOS.
3. Turn on the alternative keypad — it shows `=` even in English.
4. If you had the old toggle set, confirm nothing odd happens on upgrade. The stored value is now ignored rather than migrated.
5. Haptics still fire on key presses, and the equals key still plays its sound.
6. **Turn haptics off in the system Settings app, then return to EnterCalc — haptics must stop without relaunching.** This is the regression risk from caching the preference, since the Settings bundle is a different process.
7. Ideally: an Instruments trace for the actual before/after latency. The issue asks for a 20% median reduction and that number is **unverified**.

## Accessibility — PR #106

1. With VoiceOver on, the macOS Settings, history and new-window buttons announce **Settings**, **Toggle History Panel** and **Open New Window** — not SF Symbol names. Verified via the accessibility tree; worth confirming by ear.
2. Known gap, not fixed: the keypad-height and history-overlay **resize handles are drag-only**, so they cannot be operated by VoiceOver or keyboard. Tracked on #77.

## Release mechanics — PR #96

1. Confirm both apps report **1.1.0** in About and iOS Settings. The first preview build reported `1.0.0` — the committed Xcode project hardcoded the old version, so the `project.yml` bump did nothing on its own. Fixed and verified, but re-check after merge.
2. Run `scripts/macos/build-installer-dmg.sh` against a Release build to confirm the installer flow still works after the version bump.

## Known, pre-existing, not introduced here

**13 test failures pre-date this work.** Four tests fail on untouched `main` — backspace unwinding parenthesized expressions, two clear-entry cases, and a German localization string. Verified failing identically before any of these changes. They are real bugs deserving their own issues.

**The committed Xcode project has drifted from `project.yml`.** Regenerating with the installed XcodeGen rewrites ~820 unrelated lines, so new files were kept in the SPM module and the version was edited in place. Worth reconciling before someone adds a file to an app target and hits it.

**A localization key can be added to `Base.lproj` and never propagate.** `settings.equals.enterKeySymbol` existed only in Base and was never added to any of the seven language files, so its label fell back to English everywhere with no failure signal. A Base-vs-languages parity check would catch this class of bug; noted on #65.
