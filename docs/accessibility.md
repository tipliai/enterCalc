---
title: Accessibility
permalink: /accessibility/
---

# Accessibility Features

This page is a quick guide to accessibility features available in EnterCalc.

### Labels and control clarity

- Core controls in calculator, history, and settings are labeled for assistive technologies.
- Configurable function keys announce the *function* they currently carry — "Undo", "Square Root" — rather than the glyph drawn on them, so the label follows the key when it is reassigned.

### VoiceOver

- **The display is one element.** It's labelled "Result". Its value is the number on screen plus where it came from: "12, from 5 plus 7" after a calculation, or "7, after 5 plus" while one is in progress. Operators are read as words ("plus", "divided by").
- **Numbers are read the way people say them.** The whole part is read as a number and each decimal digit on its own, so 3.1415 is "3 point 1 4 1 5". A result cut off at the display's 16 digits, like 28 ÷ 3, is read as "9 point 3 3 3 repeating". Shorter numbers are read in full, since they are exact.
- **Currency amounts read as money.** Under one unit they are read in cents ("71 cents", "30 pence").
- **Changes are announced.** Enter announces the result ("Equals 12"), AC announces "Cleared", and an error is read out. Action keys say what they did and what is now shown ("Undo, 2 displayed"). Mode changes are announced ("Now in Currency mode"). Moving to another screen or window says which one and what it shows ("Screen 2, $1.55 shown"). With two calculators side by side on the iPhone Duo, it also says which half ("Left, Screen 2, $1.55 shown"), and each half is its own group, "Left calculator" and "Right calculator". On the Duo the Settings, History and New Screen buttons sit in a rail down the right edge under the status readout, in place of a header row, on the front display and in book position, where they serve the selected calculator: a "Two calculators" button at the top of the rail opens the second one, and then becomes a 1 | 2 toggle, "Left calculator" and "Right calculator", whose selected segment says which one the rail, the keys and the panes belong to. VoiceOver reaches the rail after the right calculator's keys. The iPad in landscape has the same rail at its right edge, and the same two calculators when the window is wide enough for each to be no narrower than an iPhone's; portrait keeps the header row. "Left" and "Right" are always the halves as seen, because the system turns the whole layout with the device.
- **On the Mac, typed keys are spoken** ("5", "plus"), because VoiceOver's focus stays on the window while you type.
- **The panes take VoiceOver focus.** History, Rounding, VAT, Tip, Settings and the Edit Action chooser announce themselves when they open and say "… closed" when they close. While a pane is open, VoiceOver and Tab only reach that pane's controls. The escape gesture closes the pane.
- **Sliders read their meaning, not a percentage.** The Round Result slider reads the rounded value. The Tip slider reads the rate with the tip and total, and VAT and Tip choices say what was selected along with the new amounts ("15% selected. Tip $1.50, Total $11.50").
- **The Edit Action chooser explains each option**, marks the key's current action, and confirms the choice ("Redo selected").
- **The display offers Copy and Copy Operation** as VoiceOver actions.

- **Checked before each release.** A light automated audit checks that every control has a name, and the [VoiceOver test script](voiceover-test-script.md) is run by hand on iPhone, iPad and Mac.

### Keyboard

- **Escape** closes whichever pane is open, leaving everything as it was.
- **Delete** does what the open pane's trash button does: turns rounding off, takes VAT or Tip off the display, clears the history, or asks to restore the default keys.
- **← and →** move the Round Result and Tip sliders. In the Edit Action chooser, the arrow keys move through the options and **Return** chooses the highlighted one.
- **Tab** moves between controls and **Space** presses the focused one. On the Mac this works whether or not the system's Keyboard navigation setting is on (#164); the focused control gets a focus ring. On iPhone and iPad, turn on **Full Keyboard Access** (Settings → Accessibility → Keyboards).
- **Return** is never a button press: it is =, or closes the Rounding, VAT and Tip panes.
- **Shift + Down Arrow** makes the display bigger and **Shift + Up Arrow** smaller.
- All VoiceOver text is translated into the seven app languages. VoiceOver speaks with the system's voice.

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

- **Settings ▸ User Interface** has a Text Size control that follows the system text size by default (**Use System Text Size**).
- Turn it off to choose one of five sizes for EnterCalc only: Extra Small, Small, Default, Large, and Extra Large.
- The chosen size applies to Settings, history, and the panels the same way the system's larger text does, and makes the calculator's numbers larger or smaller. Key sizes stay the same at every setting.
- The VAT, Tip and rounding panes scale their text too, on iPhone, iPad and Mac. A pane grows taller to fit larger text, and if it would cover too much of the screen it scrolls instead of cutting anything off. The VAT and TIP buttons in the display keep their size.

## Platform Notes

### iOS

- Supports OS Reduced Motion, Increase Contrast, and larger text settings.
- Compact action labels and history/settings text scaling are enabled.

### macOS

- Supports OS Reduced Motion, Increase Contrast, and larger text behavior.
- Compact action labels and history/settings text scaling are enabled.

## Notes

- Accessibility behavior follows OS settings where supported.
- We continue to improve accessibility with each release.
