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

## Input latency — #90

#104 removed work that sat between the touch and the display update, but this issue's acceptance criterion is a *number* — a median tap-to-display latency at least 20% lower — and a number needs an instrument. The press handler is now bracketed by two signposts, so the measurement is a trace rather than a research project.

They time the **handler** — from the tap being recognised on release to the handler returning — not touch delivery before it or the render after it. That is exactly the part #104 changed, so it is the fair comparison, but it is not the full on-glass latency; if that figure is wanted, read the render side off the same trace's Hitches and SwiftUI tracks.

**On a device, with Instruments:**

1. Instruments → **Points of Interest**, targeting EnterCalc on the device.
2. Record, then tap the keypad twenty or so times at a natural pace.
3. Two intervals appear per press. **`keypad press`** is the whole press handler; **`keypad result`** is the calculation and view-model update alone. The difference is what confirmation — haptics, sound, press animation — and per-press bookkeeping cost on the main thread.
4. Repeat steps 1–3 on the **baseline**: branch `perf/90-latency-baseline`, which is `main` from just before #104 (`f3e75fe^1`) with the same two signposts applied in the same places. A plain pre-#104 build emits neither interval, so it has nothing to compare against. Compare the two `keypad press` medians for the ≥20% figure.

**Without Instruments**, the same signposts come out of the unified log, which is enough to see the shape:

```bash
xcrun simctl spawn booted log stream --style compact --signpost --predicate 'subsystem == "com.tipliai.entercalc"'
```

**What the simulator already shows.** Across four taps: `keypad press` median **12.5ms**, `keypad result` median **1.0ms** — so roughly 92% of the press is confirmation rather than calculation. Treat that as a direction to look in, not a result: it is the simulator, where haptics do nothing at all, the log's timestamps are only millisecond-resolution, and four taps is not a sample. The device numbers are the ones the acceptance criterion is about.

## Page switching — #83

Swipe intent, as revised by #122: a key accepts a press that travels up to 22pt, so a 12pt drift starting on a digit key **enters the digit** and turns no page. #116 originally had the key give up at 8pt of sideways travel, which dropped digits during fast typing. Paging is recognised at 28pt (raised from 18pt), the page starts to move at 20% of its width, and it turns at 40% (or 24% with a flick). A 400pt swipe pages normally and still creates a new page past the last one. Between 22pt and 28pt neither happens: a slip of that size is not a clear press or a clear swipe.

**Page swipes and dots (#122), on iPhone and iPad:**

1. Swipe partway and let go. The page should not move until about 20% of the width, and if it moved it should spring back smoothly, never jump.
2. Start a swipe on a keypad key. The key should not play its press pop, and no digit is entered.
3. Add a page, then close it. The calculator must not resize; the page dots fade in and out in a strip that is always reserved.
4. Swipe slowly between pages. The dots stay fixed while the page slides beneath them.

**Fast typing (#122), on iPhone and iPad:** type `123456789` quickly and repeatedly, with one thumb and then two alternating. Every digit should land, and the page should never start to move. Then make a deliberate swipe: it should still page with no extra effort.

**The keyboard shortcuts were not driven.** Sending hardware keys to the simulator needs the Mac's display awake, and it was asleep for this pass — the same limitation that blocked the macOS driver.

1. **iPad with a hardware keyboard:** Shift + Right moves to the page on the **right**, Shift + Left to the page on the **left**. (The first build had these the other way round, following the swipe's finger direction; QA found that inverted, so it was flipped.)
2. Shift + Right on the last page opens a new page, the same as swiping. Shift + Left on the first page does nothing rather than wrapping.
   - Repeat both while editing the display (press Insert first, so plain Left/Right move the caret) and with the rounding panel open. Shift + Left/Right must still switch pages rather than moving the caret or the rounding selection, and Shift + Down must shrink the display rather than open the rounding panel. Each press should move exactly **one** page.
3. Both appear under **View** in the menu bar, translated, and are reachable by VoiceOver.
4. **⇧⌘C copies the operation** on both platforms, while ⌘C still copies the result. Worth checking carefully: both platforms intercept keyboard events before the menus see them, so this needed handling in two places, not just the menu item. Without that it would have silently copied the result instead.
5. **Swipe feel:** with pages open, check that ordinary keypad use never turns a page, and that a deliberate swipe still feels responsive rather than sticky. The thresholds are named constants in `CalculatorPagerGestureIntent` if they want tuning.
6. **Theme fade:** set two pages to different themes — Dark and Light — and switch between them. The change should crossfade over about a quarter-second rather than cutting. Check with Reduce Motion on, where it should cut instantly instead.
7. **iPad, two windows side by side:** open a second EnterCalc window in Split View and tap into one of them. Shift + Left/Right, Shift + Up/Down, ⇧⌘H and ⌘R must each affect **only the focused window** — the other window's page, display height and panels stay put. Tap into the other window and repeat. With no calculator window focused, the six items under **View** are disabled.
8. **macOS:** confirm Cmd + ` still cycles calculator windows and that the Window menu lists them. #83 asked whether Shift + Arrow should do this; the answer taken was no — see [keyboard.md](keyboard.md) for why.

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
17. **iPad:** set up page 1 and page 2 differently and swipe between them. Each page keeps its own layout. **macOS:** with two windows open, change one — the other keeps its layout until it is closed. A newly opened window starts from the most recently changed layout, the same as theme, language and every other window setting.
18. Switch to the **alternative keypad** in Settings. Its keys are deliberately fixed — press-and-hold and right-click should both do nothing there.
19. Check the panel in Dark and Light themes, at the smallest window width, and in landscape on iPhone.
20. **VoiceOver:** each configurable key should announce the *function's* name — "Undo", "Square Root" — not its glyph, and offer a **Change Function** action that opens the chooser.
21. Run in another language and confirm the chooser title, the hint and every function name are translated.

If a check fails, `ENTERCALC_DEBUG_LOGS=1` makes the app log every chooser open and every reassignment as `[functionKeys] <slot> = <function>; layout = …`, which the macOS driver's `log` command prints. The accessibility tree cannot show which function a key carries, so that log is the only readable record.
## Percentage and VAT maths — #25

Engine only: this ships the calculation behind percentage mode and reverse VAT, with no UI. The VAT and TIP controls that reach it are #92, so there is nothing to click yet and nothing here needs a manual pass — the maths is unit-tested, and the results were cross-checked against an independent implementation as well as against typing the same thing on the keypad.

Worth knowing when QA'ing #92 later:

1. `100 + 10%` gives an amount of `10` and a result of `110`; `100 - 10%` gives an amount of `10` and a result of `90`. The amount is unsigned in both directions, so a discount reads as its size rather than as a negative number.
2. Reverse VAT on `120` at 20% gives `100` net and `20` VAT.
3. Net plus VAT always equals the gross exactly, even where the division does not come out even — `100` including 20% VAT is `83.333…` net and `16.666…` VAT, and those two still add back to exactly `100`. Any rounding applied for display must preserve that.
4. Rates at or below −100% are refused rather than dividing by zero.

## Editing caret in Currency mode — #118

1. Enter `120`, press the currency key, then tap or click the far left of the display, on or just before the `$`. The caret should appear **between the `$` and the `1`**, never in front of the symbol.
2. With the caret in the number, press Left until it stops. It should stop after the symbol.
3. Type a digit there. It goes in front of the first digit, behind the symbol (`$5,120`).
4. Repeat with a negative amount (`±` first): the caret stops after `-$`.

## VAT presets and typed rates — #124

Rates were verified on 2026-10-06; sources and confidence are in [vat-rates-research.md](vat-rates-research.md). Rates live in `apple/src/shared/Resources/vat-rates.json`: changing one is a one-line edit there.

1. Set the device region to **Germany** and open VAT on an amount. The first row holds **three** presets and the rate selector (− rate +, with no "Rate" label): **19%** and **7%** (Germany's rates, 19% selected), topped up with 5. United Kingdom: 20 / 5 / 10. Switzerland: 8,1 / 3,8 / 2,6. United States (no VAT): 5 / 10 / 20. Tip: 15 / 18 / 20. The Tip panel has no Bill row.
   - **There is no Use Result button.** Opening VAT or Tip writes the result to the display straight away (with an operation line that starts from the original amount, such as `100 + VAT(20%) =`, `120 − VAT(20%) =` when removing, or `100 + TIP(18%) =`; like every currency operation line it shows the numbers without the symbol), and every change of rate or direction updates it. Close the panel with ✕ or by tapping outside; the header is laid out like the rounding pane's, with a **trash** button that takes the VAT or tip back off the display (restoring it exactly, operation line included) and closes. Reopen it to adjust: it works from the original amount (Ex VAT £100 after £120 was applied), so a new rate replaces the VAT or tip rather than adding to it. One **Undo** returns to the amount before the panel opened.
   - While a panel is open, its VAT or Tip pill in the display is **inverted** (filled), not blue.
   - Amounts in both panes show the currency's full decimals, trailing zeros kept: removing 19% from €100 reads €84,03 / €15,97 / €100,00; a 25.5% VAT on £100 reads £125.50; removing 10% from ¥1,000 reads ¥909 / ¥91 / ¥1,000. The tip is rounded to whole pence (or yen) and the total is the bill plus that tip.
   - The Tip pane has no split and no − / + selector: three presets (long-press still edits them, any value), the **Tip (18%)** and Total lines, and below them a slider like the rounding pane's, from Off (power icon) to 40% with a notch every 2%. The slider moves in whole 2% steps; at Off the tip comes back off the display. A preset such as 15% shows between notches. A preset is shown selected (blue) only after it is pressed; moving the slider clears it, even if the slider then lands on that preset's value, so fast slides don't flash the presets.
   - Check both panels in every language on the smallest iPhone: no label truncates (German *MwSt. herausrechnen* is the longest).
2. Tap the rate in the selector (between − and +). A system alert opens over the panel (a lightbox, not inline), titled **Rate**, with a text field: the decimal pad on iPhone, the numbers layout on iPad, a text field on Mac. Type `8,1` (German format) or `8.1`; up to three decimals are accepted (`9,975`, Quebec's QST). **Done** applies it; **Cancel**, or Done on an empty field, keeps the old rate; text that isn't a valid rate changes nothing.
3. Press and hold a preset. You feel the same haptic as other long-press actions, and the alert opens, titled **Edit Preset**; type a new value and press Done. The button shows the new value. Quit and relaunch: it is still there.
4. To undo an edit, press and hold the preset again and type its original value.
5. Repeat 3–4 on the **Tip** panel's presets.
6. While the alert is open, the calculator underneath must not change, and on iPhone the keyboard covers the VAT/Tip panel rather than pushing it up; when the alert closes, nothing has moved.
7. With a hardware keyboard: while the alert is open, keys type into its field and the calculator doesn't react; once it closes, keys go back to the calculator.
8. The − / + stepper moves by 1 on a whole rate, and by 0.5 once a rate has decimals (8,1 → 8,5).
9. VoiceOver: each preset offers an **Edit Preset** action; the alert is the standard system one.

## VAT and TIP controls — #92

The pills appear in the mode row only while a currency symbol is showing. The panels were reworked by #124 (see the section above): results apply live with no Use Result step, three presets share a row with the rate selector, and the Tip pane has no split. The steps below reflect that.

**macOS was not driven interactively.** The Mac's display was asleep for this pass, which makes the accessibility driver report zero windows (now documented in [macos-qa.md](macos-qa.md)). The panels themselves are the same shared code the iPhone run exercised, and the macOS target builds, but the placement, the theme and the click targets need a person.

1. Enter a value, press the currency key. **VAT** and **TIP** (uppercase in English) appear at the right of the mode row, and the **currency key turns blue** (accent fill, white symbol) to show the mode is on. **AC** keeps it on and blue; pressing the currency key again leaves the mode and the key returns to its normal colour. Reassign currency onto the large ( ) or % key and check it highlights the same way, on iPhone, iPad and Mac.
2. Neither should crowd the mode label at the smallest window width, or in landscape on iPhone.
3. Open **VAT**. The display changes straight away. Check **Add VAT** and **Remove VAT** both read correctly, the emphasised figure switches between Inc VAT and Ex VAT with the direction, and the display shows the gross when adding and the net when removing, with an operation line saying which.
4. Tap a preset rate, then use the `−`/`+` selector to reach a rate that is not a preset, such as 21%, and confirm the figures and the display follow.
5. Open **Tip**. The presets select, and the display shows the total (bill plus the rounded tip) straight away. There is no split.
6. Use the **trash** in either pane: the display returns to the amount before the pane opened, and the pane closes.
7. Undo after closing a pane returns to the amount before it opened, in one step.
8. Leave currency mode while a panel is open. It should close rather than hang over a Basic-mode calculator.
9. Check both panels in Dark and Light themes, and with larger text sizes — the figures shrink to fit rather than truncating.
10. Run in another language and confirm every label is translated, including the accessibility labels on the selector and the trash and close buttons.
11. **VoiceOver:** each result row should read as one phrase — "Inc VAT, $120" — rather than as two separate fragments.

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
