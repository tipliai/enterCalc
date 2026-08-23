---
title: 1.1.0 QA Plan
permalink: /qa-1-1-0/
---

# EnterCalc 1.1.0 QA Plan

Manual checks for the 1.1.0 release. Each section names the PR it covers and says what was already verified automatically, so QA time goes to the things that genuinely need a person.

Automated coverage lives in [tests.md](tests.md). The macOS driver used for several of these checks is described in [macos-qa.md](macos-qa.md).

## Decisions taken

These were open while the release was being built and are now settled. Recorded here because they change what QA should expect to see.

### Currencies with no single-glyph symbol — single-glyph only for 1.1.0

The calculator engine accepts a **single character** as a currency symbol. That excludes CHF, Nordic `kr`, PLN `zł` and CZK `Kč`. For 1.1.0 the engine stays as it is: the Settings picker offers only the locale-mappable single-glyph currencies, and regions with no clean mapping fall back to a documented default rather than silently to `$`. Multi-character symbols are a later change.

### Currency key placement — the configurable top row

The currency key is no longer in the mode row. It ships as a default assignment in the configurable top row (see below), and the mode row is a label again, reserved for the VAT and TIP controls. Anything that used to test the mode-row currency button now applies to the top-row key.

### Three documented behaviors were overturned — the new behavior is canon

Each had a passing test asserting the old result. They are intentional corrections, not broken tests, but they are behaviors existing users may have learned:

1. `5% + 3%` was `0.08`, now `8%`. Extended to subtraction (`10% − 4%` is `6%`) for coherence. `×` and `÷` deliberately unchanged — they combine percentages rather than accumulate them, so `9% × 9%` is `0.81%`, not `81%`.
2. `$6 + 200%` was `$12`, now `$18` — the percent applies to the amount instead of replacing it.
3. All Clear used to switch currency mode off; it now stays on.

## Configurable function keys — #67

Every step below was driven end to end automatically — on the iPhone simulator by synthetic touches, on macOS by synthetic mouse events — confirming the key changed, the swap moved the displaced function, and the press or click that opened the chooser did **not** also run the function it was replacing. What needs a person is how it feels and how the panel looks.

**macOS — right-click**

1. Right-click any key in the top row. The chooser opens next to it, above where there is room and below where there is not.
2. Control-click one. Same result; macOS treats it as a secondary click.
3. Click an option. The key changes immediately.
4. Click anywhere outside the panel. It closes and nothing changes.
5. Plain left-click still runs the key's function — the currency key should still enter and leave Currency mode.
6. Repeat on the two large `( )` and `%` keys.

**iOS — press and hold**

7. Press and hold any top-row key. The chooser appears after about 0.4s and **stays open when you lift your finger**.
8. Tap an option. The key changes immediately.
9. Tap anywhere outside the panel. It closes and nothing changes — including no keypad key firing underneath.
10. Without lifting, drag from the key straight onto an option and release there. That commits too, for anyone who prefers one continuous motion.
11. Press and hold, then move off before the chooser opens. No chooser; the key behaves as a normal press or swipe.
12. A plain quick tap still runs the key's function.
13. Repeat 7–9 on the two large `( )` and `%` keys.

**Both platforms**

14. Pick a function that already sits on another key — say put `backspace` where `undo` is. The two should **trade places**, not duplicate.
15. Pick a function that is not on the keypad at all. The displaced function simply disappears; that is intended.
16. Reassign a key, quit and reopen. The layout should survive.
17. **iPad:** set up page 1 and page 2 differently and swipe between them. Each page keeps its own layout. **macOS:** the same across two windows.
18. Switch to the **alternative keypad** in Settings. Its keys are deliberately fixed — press-and-hold and right-click should both do nothing there.
19. Check the panel in Dark and Light themes, at the smallest window width, and in landscape on iPhone.
20. **VoiceOver:** each configurable key should announce the *function's* name — "Undo", "Square Root" — not its glyph, and offer a **Change Function** action that opens the chooser.
21. Run in another language and confirm the chooser title, the hint and every function name are translated.

If a check fails, `ENTERCALC_DEBUG_LOGS=1` makes the app log every chooser open and every reassignment as `[functionKeys] <slot> = <function>; layout = …`, which the macOS driver's `log` command prints. The accessibility tree cannot show which function a key carries, so that log is the only readable record.

## macOS theme sync — PR #97

The fix rests entirely on this check: the repro could not be reproduced automatically, because the macOS QA driver reads text and structure but not colors.

1. Set macOS to Dark Mode, then set the calculator theme to **Light**.
2. Quit and reopen the calculator. Open a **new window** with `+`. This is the case that used to fail — a new window has not been through a focus cycle.
3. In that window, switch the theme to **System**. Header and body should both go dark immediately, with no half-dark window.
4. Still on System, flip macOS between Light and Dark in System Settings. The app should follow without needing focus or a restart.
5. Check the settings sheet and the history and rounding overlays in both themes — these resolve the color scheme separately and should match the window.

## Currency mode — PR #100

The toggle cycle was verified on the iOS simulator. macOS and layout were not.

1. **macOS:** type `5`, press the currency key in the top row. Display becomes `$5` and the label switches Basic → Currency.
2. Press it again: symbol clears, label returns to Basic, and the `5` is still there.
3. Check the six top-row keys do not crowd each other at the smallest window width, or in landscape on iPhone.
4. Tap or click the display body while in currency mode — it should still copy. The mode row no longer holds a control, so it passes taps straight through again.
5. Change the currency symbol in Settings while a value is on screen; the symbol should update immediately, not on the next entry.
6. Confirm the default symbol matches your region before ever opening Settings.
7. Type `€` on a hardware keyboard, then press the currency key. It should clear the `€`, not swap it for the configured symbol.
8. With currency on, press **AC**. Currency mode should stay on. Verified on iOS; check macOS.
9. Confirm the currency symbol picker sits under **Language** in Settings on both platforms.
10. On iOS, change the symbol in Settings, then quit and reopen. It should still be your choice — this did not persist before #67.

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
