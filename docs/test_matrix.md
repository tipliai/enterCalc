# EnterCalc Unit Test Matrix

This document tracks the shared-module checks covered by `swift test`.
Each row should map directly to a test method in `apple/tests/CalculatorViewModelTests.swift`.

## UI Settings Expectations

These behaviors are product expectations for the app UI and persistence model. They are broader than the current shared-module unit tests and should be preserved when changing localization or settings code.

- macOS first launch: a new window starts with `settings.language = default`, which means the app follows the current system language.
- macOS new windows: each newly opened window initializes from the most recently persisted app settings.
- macOS existing windows: changing language or other stored settings in one window updates that window immediately, but does not retroactively update other already-open windows.
- macOS existing windows on refocus: an already-open window should continue using the settings it was created with or last changed to, even if a different window later persisted new defaults.
- macOS default language option: selecting `default` means follow system language rather than pinning the UI to a previously resolved locale.
- iPad first page: the home page starts from the device or system defaults on first launch and is the only page whose settings are persisted to app storage.
- iPad new pages: each new page is seeded from the current home-page settings at the moment the page is created.
- iPad existing secondary pages: once created, a secondary page keeps its own settings and does not automatically update when the home page changes later.
- iPad future secondary pages: if the home page changes language from `default` to an explicit language such as German, pages created after that change should inherit German.

| Area | Test Value | Expected Result | Method |
| --- | --- | --- | --- |
| Arithmetic | Enter `97`, apply square root, `+ 8 =` | Display `17.848857801796`, expression `√(97) + 8 =`, history entry `√(97) + 8 -> 17.848857801796` | `testSquareRootPlusAdditionProducesExpectedResultAndHistory` |
| Arithmetic | Enter `1234567891234567 × 9999999999999999 =` with scientific notation enabled | Display `1.234567891234567e+31` | `testLargeResultUsesScientificNotationByDefault` |
| Arithmetic | Run the same multiplication, then disable scientific notation | Display `12,345,678,912,345,670,000,000,000,000,000` | `testScientificNotationCanBeDisabledToShowExpandedValue` |
| Number format | Enter `1234567.89`, switch number format style to European | Display `1.234.567,89` | `testNumberFormatStyleCanDisplayEuropeanSeparators` |
| Number format | Detect format for `en_US`, `de_DE`, `fr_FR`, `hi_IN`, `de_CH` locales | Formats map to western, european, french, indian, and swiss respectively | `testSystemLocaleDetectionMapsKnownFormats` |
| Arithmetic | Enter `5 + 2 = = =` | Display advances through `7`, `9`, `11`; final expression `9 + 2 =`; history records results for `5 + 2`, `7 + 2`, `9 + 2` | `testRepeatedEqualsRepeatsLastBinaryOperation` |
| Arithmetic | Enter `50`, apply percent | Display `0.5`, expression `50%`, no error state | `testPercentConvertsCurrentInputToDecimalValue` |
| Error handling | Enter `9 ÷ 0 =` | Error state enabled, display `Cannot divide by zero`, empty expression, undo remains available | `testDivideByZeroSetsLocalizedErrorState` |
| Error handling | Enter `9`, toggle sign, apply square root | Error state enabled, display `Invalid input`, empty expression | `testSquareRootOfNegativeNumberSetsInvalidInputError` |
| Error handling | Apply reciprocal to zero | Error state enabled, display `Cannot divide by zero` | `testReciprocalOfZeroSetsDivideByZeroError` |
| Editing state | Enter `12`, then undo twice and redo twice | Display steps `12 -> 1 -> 0 -> 1 -> 12`; redo becomes unavailable at the end | `testUndoAndRedoRestorePriorDisplayStates` |
| Input sanitization | Enter more than `CalculatorViewModel.Limits.maxInputDigits` digits | Display is capped at the configured maximum input length | `testInputDigitsAreCappedAtMaximumLength` |
| History | Repeatedly evaluate `1 + 1` more than `64` times | History count is capped at `64`; newest entry is kept first | `testHistoryIsCappedAtMaximumEntryCount` |
| Memory | `MS 12`, clear, `M+ 3`, clear, `M- 5`, `MR`, `MC` | Memory progresses `12 -> 15 -> 10`; recall shows `10`; clear removes memory and entries | `testMemoryStoreRecallAddSubtractAndClearFlow` |
| Memory | Store more than `64` distinct values | Memory entries keep only the newest `64` stored values | `testMemoryEntriesAreCappedAtMaximumEntryCount` |
| Editing state | Perform more than `64` changes | Undo depth is capped at `64`; redo depth remains `0` | `testUndoDepthIsCappedAtMaximumEntryCount` |
| History | Evaluate `8 × 7 =`, reuse the saved history entry, then type `2` | Reuse restores display `56` and expression `8 × 7 =`; next digit starts fresh input with display `2` | `testReuseHistoryEntryRestoresResultAsNewInput` |
| Screen settings | Create a sub-screen, customize it, update the home screen to German, then create another sub-screen | Existing sub-screen keeps its custom settings; new sub-screen inherits the updated home-screen settings | `testNewScreenUsesUpdatedHomeSettingsWhileExistingSubScreenKeepsItsOwnSettings` |
| Settings persistence | Load empty persisted settings, persist German settings, then load again | Existing in-memory settings remain unchanged; a new load picks up the newly persisted defaults | `testPersistedSettingsAffectNewlyLoadedSettingsWithoutMutatingExistingInMemorySettings` |
| Localization | Override bundle to German | `settings.language` resolves to `Sprache`; `settings.credit.linkText` resolves to `GitHub` | `testLanguageOverrideReturnsLocalizedSettingsLabel` |
| Localization | Trigger divide-by-zero, switch bundle to German, refresh localization | Active error text changes from `Cannot divide by zero` to `Durch Null kann nicht geteilt werden` | `testRefreshLocalizationUpdatesActiveErrorMessage` |
| Localization | Clear the override bundle and localize `settings.title` | Falls back to the module or system-default localization without mutating the global override bundle | `testLocalizedUsesModuleFallbackWhenLanguageOverrideIsNil` |
| Licensing/resources | Load `Base`, `en`, `de`, `es`, `fr`, `ja`, `zh-Hans` string tables | All required credit keys exist; English credit text contains `MIT License` and `Tipli AI` | `testLocalizedCreditsExistAcrossSupportedBundles` |
| Localization | Load `Base`, `en`, `de`, `es`, `fr`, `ja`, `zh-Hans` about/credit strings | Each bundle keeps non-empty about labels, preserves `%@` placeholders, mentions `EnterCalc`, and uses `GitHub` as the credit link text | `testAboutAndCreditStringsStayAlignedAcrossSupportedBundles` |
| Licensing/resources | Read repository `LICENSE` file | License contains `MIT License` and `Tipli AI` | `testLicenseFileContainsRequiredNotices` |
| Clipboard | Enter `1234`, copy to pasteboard | Pasteboard string is `1234` | `testCopyToPasteboardWritesUngroupedValue` |
| Clipboard | Copy operation `12 + 3 = 15`, then paste into a fresh view model | Pasted display is `15`; history stays empty; no error state | `testCopyOperationThenPasteReplaysTheOperation` |
| Clipboard | Paste `$1,234.50` from the pasteboard | Display normalizes to `1,234.5`; no error state | `testPasteFromPasteboardNormalizesFormattedNumericContent` |
| Clipboard | Paste a numeric string longer than `CalculatorViewModel.Limits.maxPasteCharacters` | Display stays `0`; history and memory entries remain empty | `testPasteFromPasteboardRejectsOversizedNumericInput` |