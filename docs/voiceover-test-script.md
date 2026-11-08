---
title: VoiceOver Test Script
permalink: /voiceover-test-script/
---

# VoiceOver Test Script

A quick hand check before each release, on an **iPhone**, an **iPad** and a **Mac**, with VoiceOver on (iPhone/iPad: Settings → Accessibility → VoiceOver; Mac: ⌘F5). Note any step that fails, with what was heard, in the release's tracking issue.

The automated audit (the `EnterCalc-iOSAccessibility` scheme) already checks that every control has a name.

| # | Do | Expect |
|---|---|---|
| 1 | Type 5 + 7, Enter | "Equals 12" (on the Mac each key is spoken as you type) |
| 2 | Move to the display | "Result, 12, from 5 plus 7" |
| 3 | 28 ÷ 3, Enter | "… 9 point 3 3 3 repeating" |
| 4 | AC | "Cleared" |
| 5 | Undo | "Undo, … displayed" |
| 6 | Mode menu → Currency, type 0.71 | "Now in Currency mode"; the display reads "71 cents" |
| 7 | Open Rounding, adjust the slider | The rounded value is read on each step |
| 8 | Open VAT, choose 20% | "20% selected. VAT …, Inc VAT …" |
| 9 | In any pane, swipe through it | VoiceOver stays in the pane; the escape gesture closes it ("… closed") |
| 10 | Edit Action on a key, choose an option | Each option is explained; "… selected" |
| 11 | Second screen (iPhone/iPad) or window (Mac) | "Screen 2, … shown" / "Window 2, … shown" |
| 12 | Two calculators side by side (iPhone Duo inner display, or iPad in landscape): open the second with "Two calculators", then swipe across both | Each half is a group, "Left calculator" and "Right calculator"; moving to a half says "Left, Screen 1, … shown"; the rail's toggle says which half is selected |
| 13 | Keyboard (Mac, or iPad with Full Keyboard Access): Tab, Space, Return | Tab moves with a ring, Space presses, Return is = |
| 14 | Voice Control on: "Show names" | Every control shows a name; "Tap 7" works |
