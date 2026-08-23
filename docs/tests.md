---
title: Unit Tests
permalink: /tests/
---

# EnterCalc Unit Test Matrix

This document tracks the shared-module checks currently discovered by `swift test list` for the Swift package in `apple/`.
Each row in the matrix below maps directly to a discovered test method in `apple/tests/CalculatorViewModelTests.swift`.

Current verification status on macOS:
- `swift test list` discovers `190` `CalculatorViewModelTests` methods.
- This matrix documents the same `190` methods with no missing or extra entries.
- The current macOS run includes the AppKit-only clipboard tests guarded by `canImport(AppKit)`.

### Other suites

`apple/tests/SystemAppearanceTests.swift` covers `SystemAppearance.colorScheme(forInterfaceStyle:)`, which maps the macOS global-domain `AppleInterfaceStyle` value to a color scheme for the `system` theme. macOS only writes that key while Dark Mode is on, so the absent case must resolve to light, and accent variants such as `DarkAqua` must resolve to dark.

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
| Arithmetic | Enter `97`, apply square root, `+ 8 =` | Display `17.8488578017961`, expression `√(97) + 8 =`, history entry `√(97) + 8 -> 17.8488578017961` | `testSquareRootPlusAdditionProducesExpectedResultAndHistory` |
| Arithmetic | Enter `123246 - 105317.74 =` | Display `17,928.26`; stored history result is `17928.26` without binary floating-point residue | `testDecimalSubtractionDoesNotExposeBinaryFloatingPointResidue` |
| Arithmetic | Enter `0.1 + 0.2 =` | Display and history result are `0.3` | `testTenthsAdditionRoundsLikeANormalCalculatorDisplay` |
| Arithmetic | Enter `0.1 + 0.1 + 0.1 =` | Display and history result are `0.3`, preserving normal calculator rounding across chained tenths | `testThreeTenthsAdditionRoundsLikeANormalCalculatorDisplay` |
| Arithmetic | Enter `4`, apply square root, then enter `(2 + 2)` and evaluate | Display `8`; expression and history use implicit multiplication `√(4) × ( 2 + 2 )` | `testSquareRootThenParenthesizedExpressionImplicitlyMultiplies` |
| Arithmetic | Enter `4`, apply reciprocal, then enter `(2 + 2)` and evaluate | Display `1`; expression and history use implicit multiplication `1/(4) × ( 2 + 2 )` | `testReciprocalThenParenthesizedExpressionImplicitlyMultiplies` |
| Arithmetic | Enter `3`, apply square, then enter `(2 + 1)` and evaluate | Display `27`; expression and history use implicit multiplication `3² × ( 2 + 1 )` | `testSquareThenParenthesizedExpressionImplicitlyMultiplies` |
| Arithmetic | Evaluate `(2 + 3)(√(4) + 1)` | Display `15`; grouped expressions preserve precedence and implicit multiplication between adjacent parentheses | `testNestedParenthesesWithSquareRootEvaluatesWithExpectedPrecedence` |
| Arithmetic | Enter `1234567891234567 × 9999999999999999 =` with scientific notation enabled | Display `1.234567891234567e+31` | `testLargeResultUsesScientificNotationByDefault` |
| Arithmetic | Enter `99999999999 × 99999999999 =` | Display and history result are `9.9999999998e+21` | `testScientificNotationMatchesCalculatorForLargeIntegerProduct` |
| Arithmetic | Enter `2 ÷ 3 =` | Display and history result stay in decimal notation as `0.6666666666666667` | `testTwoThirdsStaysInDecimalNotation` |
| Arithmetic | Enter `0.000000000000001 + 0.000000000000001 =` | Display and history result are `0.000000000000002` instead of collapsing to zero | `testSmallDecimalInputsDoNotCollapseToZero` |
| Arithmetic | Enter `1.01 - 0.42 =` | Display and history result are `0.59` without scientific notation | `testSimpleDecimalDifferenceDoesNotSwitchToScientificNotation` |
| Arithmetic | Enter `10 ÷ 3 =` | Display and history result are `3.333333333333333` | `testTenThirdsMatchesCalculatorRounding` |
| Arithmetic | Enter `7`, apply reciprocal | Display `0.1428571428571429` | `testReciprocalMatchesCalculatorRounding` |
| Arithmetic | Enter `9999999999999999 - 9999999999999998 =` | Display and history result are exactly `1` | `testLargeIntegerDifferenceMatchesCalculatorExactly` |
| Arithmetic | Run the same multiplication, then disable scientific notation | Display `12,345,678,912,345,670,000,000,000,000,000` | `testScientificNotationCanBeDisabledToShowExpandedValue` |
| Number format | Enter `1234567.89`, switch number format style to European | Display `1.234.567,89` | `testNumberFormatStyleCanDisplayEuropeanSeparators` |
| Number format | Detect format for `en_US`, `de_DE`, `fr_FR`, `hi_IN`, `de_CH` locales | Formats map to western, european, french, indian, and swiss respectively | `testSystemLocaleDetectionMapsKnownFormats` |
| Number format | For each supported UI language, run style fixtures across western/european/french/indian/swiss and evaluate fixture operands | Operation rendering and result separators follow the active number style (not UI language) | `testOperationRenderingUsesTheActiveNumberStyleAcrossAllLanguages` |
| Number format | For each supported UI language, paste `2,333` and add `1` in western/european/french styles | Parser treats comma as grouping or decimal according to active style (`2,334` in western; `3,333` in european/french) | `testParserTreatsCommaAndDecimalSeparatorsAccordingToActiveNumberStyleAcrossAllLanguages` |
| Number format | During an active calculation with history and memory populated, switch number format from western to french | Current display, expression line, history display entries, memory display, copy output, and follow-up paste parsing refresh to the new format without losing calculation state | `testChangingNumberFormatRefreshesDisplayExpressionHistoryMemoryAndClipboard` |
| Rounding | For each supported UI language and number style fixture, enable result rounding, copy rounded operation/result, commit to history, and paste rounded operation into a fresh model | Rounded display, copied text, history restoration, replay precision, and separators stay aligned with the active number style | `testRoundRenderingCopyPasteAndHistoryRestorationUseNumberStyleAcrossAllLanguages` |
| Clipboard | Paste `9.32227`, enable rounding, then copy the current result | Pasteboard writes the rounded value `9.3` | `testCopyToPasteboardCopiesRoundedValueWhenRoundingIsEnabled` |
| Rounding | Enter `12 +`, begin rounding, then commit without completing the operation | No history entry is appended for an incomplete pending operation | `testCommitResultRoundingDoesNotAppendHistoryForIncompletePendingOperation` |
| Rounding | Paste `9.32227`, open rounding, then commit without selecting a level | History stays empty; display remains `9.32227`; rounding stays disabled | `testOpenThenCloseResultRoundingDoesNotAppendHistory` |
| Rounding | Paste `5`, enable rounding with precision `3`, then commit | Display stays `5`; expression display uses `=round(5, 0)`; stored history expression remains `round(5, 3)` | `testExactRoundingUsesEqualsAndPreservesSelectedSignificantDigits` |
| Rounding | Paste `$5`, enable rounding with precision `3`, then copy the rounded operation from both the live view and saved history | On-screen rounded operation line is currency-free (`=round(5, 0)`), while copied `=round(...)` text also omits the currency symbol and stays `=round(5,0)` | `testRoundedOperationCopyOmitsCurrencySymbols` |
| Rounding | Paste `$5`, then enable rounding with precision `3` | Normal currency display stays `$5`, but rounding-enabled display, copy, and saved history result show `$5.00` without restoring forced `.00` padding to normal mode | `testCurrencyRoundingDisplaysTwoDecimalsWithoutNormalPadding` |
| Rounding | Round `54321` at levels `1`, `2`, `5`, then round `1.5678` at levels `1`, `2`, `8` | Rounding removes least-significant digits by level and preserves at least one significant digit | `testResultRoundingLevelsRoundFromLeastSignificantDigit` |
| Rounding | Evaluate `2 + 2.33 =`, then enable rounding level `1` | Display becomes `4.3`; operation display collapses to `=round(4.33, 1) ≈` | `testResultRoundingCollapsesEvaluatedExpressionToCurrentTotal` |
| Rounding | Evaluate `2 + 2.33 =`, enable rounding level `1`, then backspace | Display resets to `0`; rounded operation display updates to `=round(0, 0)` | `testBackspaceUpdatesRoundedOperationBaseValue` |
| Arithmetic | Enter `5 + 2 = = =` | Repeated equals is idempotent after evaluation: display remains `7`, expression remains `5 + 2 =`, and history stays at a single evaluation entry | `testRepeatedEqualsAfterEvaluateDoesNotReplayLastOperation` |
| Arithmetic | Enter `2 × 2 × 2` and evaluate | Operation line keeps the full chain before and after evaluate (`2 × 2 × 2 =`) and history stores the full expression instead of collapsing to `4 × 2` | `testChainedMultiplicationKeepsFullExpressionDisplayOnEvaluate` |
| Arithmetic | Enter `6 +`, then press `+` again without entering a right operand | Pressing the same operator twice is a no-op; expression remains `6 +`, then normal chaining continues to `6 + 6 + 6 =` after evaluate | `testPressingSameOperatorTwiceWithoutRightOperandIsNoOp` |
| Arithmetic | Enter `9`, apply `√`, then press `+ =` (and repeat for `x²`, `1/x`, and `%`) | Trailing-operator evaluate finalizes the standalone unary/percent result without duplicating the operand; history stores the standalone expression (for example `√(9)`) | `testEvaluateAfterTrailingOperatorKeepsStandaloneUnaryAndPercentResult` |
| Arithmetic | Enter `1 + 2 + 3 +` then evaluate | Trailing-operator evaluate uses the computed accumulator, producing `6` with history entry `1 + 2 + 3` | `testEvaluateTrailingOperatorInChainUsesComputedAccumulatorAndStoresHistory` |
| Arithmetic | Enter `2 + 2 × 2` and evaluate | Result follows precedence (`6`) and post-equals operation line is rendered in nested form (`2 + (2 × 2) =`) | `testMixedPrecedenceSimpleChainUsesNestedPostEqualsDisplayAndPrecedenceOnEvaluate` |
| Arithmetic | Enter `5 + 6 × 5 +` without evaluating | Result display keeps the current right operand (`5`) and operation line shows the full chain (`5 + 6 × 5 +`) without pre-equals total collapse | `testMixedChainDoesNotComputeDisplayUntilEvaluate` |
| Arithmetic | Enter `5 + 6 × 5 + ( 5 + 665 ) − 5 =` | Mixed precedence plus parenthesized segments render in nested post-equals form and evaluate to `700` | `testMixedPrecedenceWithParenthesizedSegmentUsesNestedPostEqualsDisplay` |
| Arithmetic | Enter `2 + 2`, then switch the next operator to `−` before entering a new operand | Expression preserves the full chain (`2 + 2 −`) and evaluates correctly to `3` after entering `1` | `testSwitchingFromPlusToMinusWithPendingOperandKeepsFullExpression` |
| Arithmetic | Enter `6 + 6 +`, then switch pending `+` to `−` before typing the next value | Operation line preserves chain state (`6 + 6 −`) and evaluates to `9` after entering `3` | `testSwitchingPendingOperatorWithoutNewOperandPreservesChain` |
| Arithmetic | Build a long mixed-operation chain with additive tail and a sign-toggled terminal operand | Long chained expression remains intact during construction and evaluates deterministically to `-76,131,078` | `testLongMixedOperationChainMatchesReferenceResult` |
| Arithmetic | Enter `10 + 5`, toggle sign on the right operand, then evaluate | Right operand sign toggles inline (`10 + -5`), and evaluation uses the left accumulator correctly to produce `5` | `testAddingSignToggledNegativeRightOperandUsesLeftAccumulator` |
| Arithmetic | Evaluate a long mixed expression containing additive and multiplicative subtract terms | Post-equals stacked rendering preserves subtract semantics (for example `− (554 × 5,454)` and `− 44.00022`) without sign inversion | `testStackedOperationDisplayPreservesSubtractTermsAfterEvaluate` |
| Parentheses | Evaluate `( 2 + 3 ) × 4 =` | Display `20`; expression and history preserve grouped precedence | `testParenthesesExpressionEvaluatesWithExpectedPrecedence` |
| Parentheses | Use the toggle button to insert `(` then `)` around `8`, then add `2` | Display `10`; history expression is `( 8 ) + 2` | `testParenthesesToggleButtonInsertsOpenThenClose` |
| Parentheses | Enter `6 + 6` then `(` | Expression keeps the pending right operand and becomes `6 + 6 × (` rather than collapsing to `6 + (` | `testTypingOpenParenthesisAfterPendingRightOperandPreservesThatOperand` |
| Parentheses | Build `6 + 6 + 6`, then press the parentheses key to open `(` | Existing multi-step chain is preserved inline (`6 + 6 + 6 × (`), then evaluates correctly after closing the parenthesized operand | `testParenthesisKeyPreservesExistingMultiChainExpression` |
| Parentheses | Enter `8 × ( 9² )` and evaluate | Display `648`; visible history uses `9²` while stored history uses `sqr(9)` | `testSquareInsideParenthesesRemainsInExpressionAndEvaluates` |
| Arithmetic | Enter `-2`, then apply square | Display `-4`; x² treats the signed input with exponent-style precedence for standalone negatives | `testSquareOfNegativeInputUsesExponentPrecedenceSemantics` |
| Parentheses | Use keyboard-typed `(` and `)` to enter `2 + 3 × ( 4 + 5 × ( 6 ) )` | Nested keyboard parentheses are accepted inline and evaluate with expected precedence (`104`) | `testKeyboardTypedNestedParenthesesAreAcceptedInline` |
| Percent | Enter `1 + 2 × ( 100%` and evaluate | Before `=`, display stays `100%`; evaluation treats `%` as decimal and resolves to `3` with expression `1 + 2 × ( 100% ) =` | `testPercentInsideParenthesizedExpressionStaysVisibleUntilEvaluate` |
| Percent | Enter `1 + 5 × ( 200% ) =` | Evaluation treats `%` as decimal inside parentheses, resulting in `11`; history stores `1 + 5 × ( 200% )` | `testPercentInsideParenthesizedExpressionEvaluatesAsDecimalPercent` |
| Arithmetic | Enter `50`, apply percent | Display `0.5`, expression `50%`, no error state | `testPercentConvertsCurrentInputToDecimalValue` |
| Percent | Enable classic percent mode, evaluate `50`, then apply percent | Display `25`; expression remains `50%` | `testClassicPercentModeTreatsEvaluatedValuesLikeClassicBehavior` |
| Percent | Enable classic percent mode, enter `50`, then apply percent as standalone input | Display `0`; expression remains `50%` | `testClassicPercentModeTreatsStandaloneInputLikeCalculator` |
| Percent | Evaluate `10 + 10%` | Display `11`; expression preserves percent as `10 + 10% =`; history stores `10 + 10%` | `testPercentMatchesCalculatorForAddition` |
| Percent | Repeat evaluate after `100 + 50% =` | First evaluation shows `100 + 50% = 150`; repeated equals does not advance or collapse expression and keeps the same result/context | `testRepeatedEqualsAfterPercentDoesNotAdvanceResult` |
| Percent | Evaluate `200 − 10%` | Pre-equals display shows `10%`; expression stays `200 − 10%`; final history stores `200 − 10% -> 180` | `testPercentMatchesCalculatorForSubtraction` |
| Percent | Evaluate `10 ÷ 10%` | Pre-equals display shows `10%`; expression stays `10 ÷ 10%`; final history stores `10 ÷ 10% -> 100` | `testPercentMatchesCalculatorForDivision` |
| Percent | Evaluate `100 × 15%` | Pre-equals display shows `15%`; expression stays `100 × 15%`; final history stores `100 × 15% -> 15` | `testPercentMatchesCalculatorForMultiplication` |
| Percent | Evaluate `5 ÷ 200%` | Pre-equals display shows `200%`; expression stays `5 ÷ 200%`; final history stores `5 ÷ 200% -> 2.5` | `testDivisionWithTwoHundredPercentKeepsPercentVisibleUntilEvaluate` |
| Percent | In currency mode, enter `$6 + 200%` then evaluate | Before `=`, display stays `200%`; evaluation finalizes to `$12` and keeps the operation line currency-free as `6 + 200% =` | `testCurrencyPercentInPendingAdditionStaysVisibleUntilEvaluate` |
| Percent | Apply `5%`, then add `3%` and evaluate | Display `8%`; expression and history remain `5% + 3%`; stored history result stays `0.08` | `testPercentAfterStandalonePercentUsesStandaloneSemantics` |
| Currency | Enter `10`, activate `$`, then `+ 10% =` | Display `$11`; the percent applies to the amount rather than replacing it | `testCurrencyPercentAdditionAppliesToTheAmount` |
| Currency | Compare `$10 + 25% =` against plain `10 + 25% =` | Currency shows `$12.5` and plain shows `12.5`; both modes share percent semantics | `testCurrencyPercentAdditionMatchesPlainPercentAddition` |
| Currency | Enter `200`, activate `$`, then `− 10% =` | Display `$180` | `testCurrencyPercentSubtractionAppliesToTheAmount` |
| Currency | Enter `10`, activate `$`, then `+ 0.25 =` | Display `$10.25`; only percent handling changed in currency mode | `testCurrencyPlainDecimalAdditionIsUnchanged` |
| Percent | Apply `9%`, then add `9%` and evaluate | Display `18%`; expression `9% + 9% =` | `testPercentPlusPercentKeepsPercentInResult` |
| Percent | Apply `10%`, then subtract `4%` and evaluate | Display `6%`; expression `10% − 4% =` | `testPercentMinusPercentKeepsPercentInResult` |
| Percent | Evaluate `200 + 10%` | Display `220`; a percent of a plain operand stays a value, not a percent | `testPercentAddedToPlainNumberStillResolvesToValue` |
| Percent | Apply `9%`, then multiply by `9%` and evaluate | Display `0.0081`; × and ÷ keep decimal semantics rather than carrying `%` | `testPercentTimesPercentStaysDecimal` |
| Percent | After `9% + 9% =`, add `1` and evaluate | Display `1.18`; the percent result is a display form over the stored `0.18` | `testCalculationContinuingFromPercentResultUsesDecimalValue` |
| Percent | After `9% + 9% =`, apply percent again | Display `0.0018`, expression `0.18%`; the result token is not re-wrapped as `18%%` | `testPercentPressedOnPercentResultUsesUnderlyingValue` |
| Percent | After `9% + 9% =`, undo | Display returns to `9%` with expression `9% + 9%` | `testUndoAfterPercentPlusPercentRestoresPendingPercentState` |
| Percent | Apply `5%`, then add `3` and evaluate | Display `3.05`; expression and history remain `5% + 3` | `testAdditionAfterStandalonePercentUsesPercentValueAsLeftOperand` |
| Error handling | Enter `9 ÷ 0 =` | Error state enabled, display `Cannot divide by zero`, empty expression, undo remains available | `testDivideByZeroSetsLocalizedErrorState` |
| Error handling | Enter `0 ÷ 0 =` | Same divide-by-zero error state and cleared expression as the standard divide-by-zero case | `testZeroDividedByZeroSetsLocalizedErrorState` |
| Error handling | Enter `9`, toggle sign, apply square root | Error state enabled, display `Invalid input`, empty expression | `testSquareRootOfNegativeNumberSetsInvalidInputError` |
| Error handling | Trigger `Invalid input`, then press backspace once | Error state clears and display restores to `-9` | `testBackspaceOnInvalidInputUndoesErrorOnce` |
| Backspace | Enter `3 + 3 + 3 + 3`, then backspace repeatedly | Backspace walks the pending expression left-to-right without implicit evaluate, keeping history empty until `=` | `testBackspaceOnPendingExpressionDoesNotAutoEvaluateAndKeepsRollbackEditable` |
| Backspace | Enter `6 + 55 + 777 + 8888`, then delete through `8888` and `+`, then delete `777` | Removing the final `777` digit immediately removes that operand from the operation line (no extra backspace step) | `testBackspaceRemovingFinalDigitAlsoRemovesExpressionOperandWithoutExtraStep` |
| Clear button | Enter `3 + 3 + 3 +`, then press `C` | With no active right-hand entry, `C` is a no-op that preserves the pending operation line and avoids pre-equals history/evaluation side effects | `testClearEntryOnPendingExpressionDoesNotAutoEvaluateOrMutateOperationLine` |
| Clear button | Enter `6 + 55 + 777`, then press `AC` | `AC` clears both the result display and operation line back to a fresh state | `testClearAllFromPendingExpressionClearsDisplayAndOperationLine` |
| Error handling | Apply reciprocal to zero | Error state enabled, display `Cannot divide by zero` | `testReciprocalOfZeroSetsDivideByZeroError` |
| Editing state | Enter `12`, then undo twice and redo twice | Display steps `12 -> 1 -> 0 -> 1 -> 12`; redo becomes unavailable at the end | `testUndoAndRedoRestorePriorDisplayStates` |
| Editing state | Build `2 × 2 × 2`, then undo and redo before evaluate | Undo restores the operation line to `2 × 2 ×`; redo restores `2 × 2 × 2`, preserving full chained expression state | `testUndoRedoRestoresFullChainedExpressionDuringConstruction` |
| Input sanitization | Enter more than `CalculatorViewModel.Limits.maxInputDigits` digits | Display is capped at the configured maximum input length | `testInputDigitsAreCappedAtMaximumLength` |
| Editing state | Enter `1234`, place the display caret between `2` and `3`, then enter `9` | Display updates to `12,934`; the caret advances with the inserted digit inside grouped output | `testDisplayEditCursorCanInsertDigitInsideGroupedDisplay` |
| Editing state | Enter `1234`, place the display caret between `2` and `3`, then backspace | The digit immediately before the caret is removed and display becomes `134` | `testDisplayEditCursorBackspaceRemovesDigitBeforeCursor` |
| Editing state | Enter `12`, place the display caret between `1` and `2`, then enter the decimal key | Display updates to `1.2`; the caret advances past the inserted decimal separator | `testDisplayEditCursorCanInsertDecimalWithinCurrentInput` |
| Editing state | Evaluate `12 + 3 = 15`, place the display caret after `1`, then enter `9` | The evaluated result remains editable in place and becomes `195` without resetting the session | `testDisplayEditCursorCanModifyEvaluatedResult` |
| Editing state | Evaluate `1234 + 1 = 1235`, place the caret near the final digit of grouped output, and insert `9` | Direct editing normalizes grouped stored input, preserves grouping in display (`12,395`), and advances the caret to the expected trailing boundary | `testDisplayEditCursorNormalizesGroupedCurrentInputBeforeInsertion` |
| Editing state | Enter `1234`, then press the left arrow key twice while editing the result display | The first press activates the caret from the trailing edge and subsequent presses move it left through grouped output boundaries | `testDisplayEditCursorLeftArrowMovesCaretLeftFromTrailingEdge` |
| Editing state | Enter `1234`, place the display caret between `2` and `3`, then press the right arrow key twice | The caret advances right through grouped output boundaries and reaches the trailing edge of the result | `testDisplayEditCursorRightArrowMovesCaretRightAndReachesTrailingEdge` |
| Editing state | Enter `1234 +`, place the display caret inside the shown left operand, edit it, then enter a right-hand value | The pending operation preview updates to the edited left operand and evaluation uses that edited value | `testDisplayEditCursorCanModifyPendingOperationLeftOperand` |
| Editing state | Build a parenthesized expression and edit an in-progress operand from the result display caret | Direct editing updates the operand token inside expression mode without breaking parenthesis state | `testDisplayEditCursorCanModifyOperandInsideParenthesesExpressionMode` |
| Editing state | Enter `1234`, edit the displayed value, then press `+` before typing the next number | The operator exits direct edit mode, preserves the edited left operand, and the next digit starts a fresh pending right-hand operand | `testSetOperatorExitsDisplayEditModeAndStartsFreshPendingOperand` |
| Editing state | In each supported number style, place the caret on a grouping separator and then on the decimal separator in `58,544.545`-style output | Grouping separators collapse to the preceding digit boundary, while the decimal separator remains directly selectable | `testDisplayEditCursorIgnoresGroupingSeparatorsAcrossSupportedNumberStyles` |
| Display layout | Render `12,345,678,901,234,567` into a constrained editable display width | The editable layout shrinks the font instead of overflowing, and the trailing boundary remains inside the available display width | `testEditableDisplayLayoutScalesLongNumbersToFitAvailableWidth` |
| Display layout | Compare short and long editable result strings in the same constrained width | Adding digits reduces the resolved editable display font size and keeps the trailing boundary inside the display width | `testEditableDisplayLayoutRescalesWhenDigitCountChanges` |
| History | Repeatedly evaluate `1 + 1` more than `64` times | History count is capped at `64`; newest entry is kept first | `testHistoryIsCappedAtMaximumEntryCount` |
| Memory | `MS 12`, clear, `M+ 3`, clear, `M- 5`, `MR`, `MC` | Memory progresses `12 -> 15 -> 10`; recall shows `10`; clear removes memory and entries | `testMemoryStoreRecallAddSubtractAndClearFlow` |
| Memory | Store more than `64` distinct values | Memory entries keep only the newest `64` stored values | `testMemoryEntriesAreCappedAtMaximumEntryCount` |
| Editing state | Perform more than `100` changes | Undo depth is capped at `100`; redo depth remains `0` | `testUndoDepthIsCappedAtMaximumEntryCount` |
| Editing state | Compare operation-chunk cap with undo cap constants | Operation chunk cap equals undo depth (`100`) | `testOperationChunkLimitMatchesUndoDepthLimit` |
| Arithmetic | Build a chained addition with `100` value chunks, then try to add one more operator chunk | Extra operator is ignored at the cap and evaluation still returns the sum of `1...100` (`5050`) | `testOperationChunkCountIsCappedAtMaximumUndoDepth` |
| History | Evaluate `8 × 7 =`, reuse the saved history entry, then type `2` | Reuse restores display `56` and expression `8 × 7 =`; next digit starts fresh input with display `2` | `testReuseHistoryEntryRestoresResultAsNewInput` |
| Screen management | Create a new screen store | Starts with one active home screen; it cannot be closed and can create more screens | `testScreenStoreStartsWithOneHomeScreen` |
| Screen management | Insert screens, activate the middle one, then insert again | New screen is inserted immediately to the right of the active screen | `testScreenInsertionOccursImmediatelyRightOfActiveScreen` |
| Screen management | Insert two sub-screens, then close the active one | Active selection moves to the immediate left neighbor | `testClosingSubScreenSelectsImmediateLeftNeighbor` |
| Screen management | Try to close the home screen, then insert more screens until the cap | Home cannot close; screen count caps at `5`; creation stops at the limit | `testHomeScreenCannotBeClosedAndScreenCountCapsAtFive` |
| Screen management | Customize one sub-screen, then create another | New screen inherits home settings rather than the current sub-screen settings | `testNewScreenInheritsHomeSettingsNotCurrentSubScreenSettings` |
| Screen settings | Create a sub-screen, customize it, update the home screen to German, then create another sub-screen | Existing sub-screen keeps its custom settings; new sub-screen inherits the updated home-screen settings | `testNewScreenUsesUpdatedHomeSettingsWhileExistingSubScreenKeepsItsOwnSettings` |
| Settings persistence | Load empty persisted settings, persist German settings, then load again | Existing in-memory settings remain unchanged; a new load picks up the newly persisted defaults | `testPersistedSettingsAffectNewlyLoadedSettingsWithoutMutatingExistingInMemorySettings` |
| Screen management | Populate the home screen, then create a sub-screen and change it independently | Each screen keeps independent display, history, and memory state | `testScreensKeepIndependentCalculatorState` |
| Localization | Override bundle to German | `settings.language` resolves to `Sprache`; `settings.credit.linkText` resolves to `GitHub` | `testLanguageOverrideReturnsLocalizedSettingsLabel` |
| Localization | Trigger divide-by-zero, switch bundle to German, refresh localization | Active error text changes from `Cannot divide by zero` to `Durch Null kann nicht geteilt werden` | `testRefreshLocalizationUpdatesActiveErrorMessage` |
| Localization | Clear the override bundle and localize `settings.title` | Falls back to the module or system-default localization without mutating the global override bundle | `testLocalizedUsesModuleFallbackWhenLanguageOverrideIsNil` |
| Licensing/resources | Load `Base`, `en`, `de`, `es`, `fr`, `ja`, `zh-Hans` string tables | All required credit keys exist; English credit text contains `MIT License` and `Tipli AI` | `testLocalizedCreditsExistAcrossSupportedBundles` |
| Localization | Load `Base`, `en`, `de`, `es`, `fr`, `ja`, `zh-Hans` about/credit strings | Each bundle keeps non-empty about labels, preserves `%@` placeholders, mentions `EnterCalc`, and uses `GitHub` as the credit link text | `testAboutAndCreditStringsStayAlignedAcrossSupportedBundles` |
| Localization | Load `Base`, `en`, `de`, `es`, `fr`, `ja`, `zh-Hans` screen strings | Screen labels and actions exist, are non-empty, and are translated across supported bundles | `testScreenLocalizationKeysExistAcrossSupportedBundles` |
| Localization | Load `Base`, `en`, `de`, `es`, `fr`, `ja`, `zh-Hans` copy-feedback strings | The localized `Copied` label exists, is non-empty, and is translated across supported bundles | `testCopyLocalizationKeysExistAcrossSupportedBundles` |
| Localization | Resolve localization code for `zh` | Maps to the supported `zh-Hans` bundle | `testResolvedLocalizationCodeMapsBaseLanguageToSupportedScriptLocalization` |
| Localization | Resolve localization code for unknown `zz-ZZ` | Falls back to `en` | `testResolvedLocalizationCodeFallsBackToEnglishForUnknownLanguage` |
| Localization | Resolve localization code for `default` with preferred language `de-DE` | Uses `de` from the preferred language list | `testResolvedLocalizationCodeUsesPreferredLanguageForDefaultSelection` |
| Licensing/resources | Read repository `LICENSE` file | License contains `MIT License` and `Tipli AI` | `testLicenseFileContainsRequiredNotices` |
| Clipboard | Enter `1234`, copy to pasteboard | Pasteboard string preserves displayed grouping as `1,234` | `testCopyToPasteboardWritesDisplayedGroupedValue` |
| Clipboard | With French number format (`1 234 567,89`), copy `8,333` | Pasteboard preserves the localized decimal separator and ungrouped value (`8,333`) | `testCopyToPasteboardUsesLocalizedDecimalSeparatorForFrenchStyle` |
| Clipboard | Copy operation `12 + 3 = 15`, then paste into a fresh view model | Pasted display is `15`; history stays empty; no error state | `testCopyOperationThenPasteReplaysTheOperation` |
| Clipboard | Paste `$1,234.50` from the pasteboard | Display normalizes to `$1,234.5`; no error state | `testPasteFromPasteboardNormalizesFormattedNumericContent` |
| Currency | Paste `$12.3`, continue with `+ 1 =`, then clear all | Currency mode stays active for results (`$12.3 -> $13.3`), while the operation line remains currency-free (`12.3 + 1`) until all-clear resets the session | `testLeadingCurrencyPasteKeepsCurrencyActiveUntilAllClear` |
| Currency | Evaluate `€12.34 + 1 =`, reuse the saved history entry | Reuse restores the currency-formatted result, while the restored operation line remains currency-free (`12.34 + 1 =`) | `testCurrencyReuseRestoresCurrencyAwareState` |
| Currency | Evaluate `$12.34 + 1 =`, copy the operation, then paste into a fresh view model | Replayed operation restores a currency-free operation line (`12.34 + 1 =`) and keeps currency mode active on the pasted result session | `testCurrencyOperationCopyThenPasteReplaysAndRestoresCurrencyMode` |
| Currency | Type `$`, then enter `1.2 + 2 =` | Leading currency symbol activates currency formatting immediately and arithmetic stays in currency mode without forced padding (`$1.2 -> $3.2`) | `testTypingCurrencySymbolActivatesCurrencyFormatting` |
| Currency | Build `10 + 5 ×`, then type `$` before entering the next operand | Result display switches to currency for the current operand (`$5`), while the operation line stays currency-free (`10 + 5 ×`) and continues evaluating correctly | `testTypingCurrencySymbolMidChainKeepsExistingExpression` |
| Currency | Type `$0.00043` manually in currency mode | Live entry preserves typed trailing zeros and copy output matches the full typed fractional precision | `testTypingCurrencyZerosPreservesLiveFractionPrecision` |
| Currency | Type `₿1.2` in currency mode | Bitcoin symbol is accepted as a supported currency prefix and copies back out as `₿1.2` | `testBitcoinCurrencySymbolIsSupported` |
| Currency | Paste `₿1.00043` | Currency formatting preserves extended pasted fractional precision instead of clamping to two decimals | `testPastingBitcoinCurrencyPreservesExtendedFractionPrecision` |
| Currency | Paste `12¢` | Cents notation converts to dollar currency mode and normalizes to `$0.12` | `testPastingCentsNotationConvertsToDollarCurrencyMode` |
| Currency | In French number style, paste `€1,2` and copy the result | Currency copy output respects the active locale decimal separator without forced padding (`€1,2`) | `testCurrencyCopyUsesActiveNumberStyleDecimalSeparator` |
| Currency | Evaluate `$100 × 115% =` in currency mode | Operation line remains currency-free (`100 × 115%`), while the final result remains currency-formatted (`$115`) | `testCurrencyModePercentOverridesCurrencyInMultiplyExpression` |
| Currency | Evaluate `€93.33 ÷ 60% =` in currency mode | Operation line remains currency-free (`93.33 ÷ 60%`), while the final result remains currency-formatted (`€155.55`) | `testCurrencyModePercentOverridesCurrencyInDivisionExpression` |
| Clipboard | Active style western (`1,234.56`), paste French value `1 000,00` | Value is parsed and converted into active style display as `1,000.00` | `testPasteFromPasteboardConvertsFrenchNumberToWesternActiveFormat` |
| Clipboard | Active style French (`1 234,56`), paste western value `1,000.00` | Value is parsed and converted into active style display as `1 000,00` | `testPasteFromPasteboardConvertsWesternNumberToFrenchActiveFormat` |
| Clipboard | Enter `12 +`, then paste `3` over the pending operand | Expression stays `12 + 3`, evaluation yields `15`, and the operation is not cleared by the paste | `testPasteFromPasteboardReplacesPendingOperandWithoutClearingOperation` |
| Clipboard | Paste a numeric string longer than `CalculatorViewModel.Limits.maxPasteCharacters` | Display stays `0`; history and memory entries remain empty | `testPasteFromPasteboardRejectsOversizedNumericInput` |
| Out of range | Enter `8`, then square repeatedly past Decimal limits | Error state is set; display becomes `Out of range`; expression clears | `testRepeatedSquaringOverflowSetsErrorState` |
| Out of range | Trigger overflow in each supported UI language | The displayed error matches the localized `error.outOfRange` string in every bundle | `testOverflowLocalizedInAllSupportedLanguages` |
| Out of range | Trigger overflow, then clear all | Error state clears and display resets to `0` | `testOverflowClearsCorrectly` |
| Out of range | Square `8` five times, then press `×` followed by `=` without typing a right operand | Trailing multiply is treated as an incomplete operation; evaluate keeps the existing value and does not overflow | `testEvaluateAfterTrailingMultiplyOperatorDoesNotDuplicateOperandIntoOverflow` |
| Out of range | Trigger overflow, then inspect copy state | Expression row stays empty and operation copy is unavailable | `testOverflowKeepsOperationRowEmptyAndOperationCopyUnavailable` |
| Out of range | Evaluate `999999999999999 × 999999999999999 =`, then evaluate again | Repeated equals does not replay multiplication; result and expression stay unchanged and avoid a second overflow pass | `testRepeatedEqualsAfterLargeProductDoesNotOverflowAgain` |
| Out of range | Overflow while resolving a pending operator change | Error state clears the operator preview row | `testOverflowDuringPendingOperatorResolutionDoesNotLeaveOperatorPreview` |
| Out of range | Trigger overflow, then undo and redo repeatedly | Undo leaves the error state; redo restores it; stack depths stay bounded | `testOverflowUndoRedoRoundTripsSafely` |
| Out of range | Trigger overflow, clear all, then run `2 + 3 =` | Normal calculation works again after reset | `testClearingAfterOverflowResetsAndAllowsNormalCalculation` |
| Out of range | Repeatedly evaluate very large additions beyond the history cap | History count and stored expression/result lengths stay within configured bounds | `testHistoryPayloadsRemainBoundedUnderLargeInputStress` |
| Out of range | Repeatedly paste large values, multiply, copy, undo/redo, and clear | History, undo, and redo remain bounded; display returns to `0` at the end | `testStressLargePasteCalculateUndoRedoCopyHistoryAndClearFlow` |
| Out of range | While already in `Out of range`, paste the text `Out of range` | Error state and display remain stable | `testPastingOutOfRangeTextLeavesOutOfRangeStateStable` |
| Out of range | While in overflow, copy the display | Pasteboard contains only `Out of range` | `testCopyOverflowWritesOverflowTextOnly` |
| Out of range | Repeatedly divide `1` by `10` until underflow | Underflow is reported as `Out of range` with an empty expression row | `testRepeatedDivisionUnderflowSetsOutOfRangeError` |
| Out of range | Apply square root exactly `maxConsecutiveSquareOrRootDepth` times | Computation still succeeds at the configured depth limit | `testSquareRootChainAtLimitStillComputes` |
| Out of range | Apply square root one step beyond `maxConsecutiveSquareOrRootDepth` | Error state becomes `Out of range` | `testSquareRootChainBeyondLimitSetsOutOfRange` |
| Out of range | Square `1` one step beyond `maxConsecutiveSquareOrRootDepth` | Error state becomes `Out of range` even though the numeric value is still representable | `testSquareChainBeyondLimitSetsOutOfRangeEvenWhenValueStaysRepresentable` |
| Out of range | Apply reciprocal exactly `maxConsecutiveSquareOrRootDepth` times | Computation still succeeds at the configured depth limit | `testReciprocalChainAtLimitStillComputes` |
| Out of range | Apply reciprocal one step beyond `maxConsecutiveSquareOrRootDepth` | Error state becomes `Out of range` | `testReciprocalChainBeyondLimitSetsOutOfRange` |
| Out of range | Enter `42`, then paste `1e999999` | Oversized scientific notation paste is ignored without corrupting state | `testScientificNotationPasteBeyondRangeIsIgnoredWithoutCorruptingState` |
| Out of range | Enter `5 + 3`, clear the entry, then paste `1e999999` | Blank pending-entry state is preserved, including expression row and undo depth | `testMalformedPasteAfterPendingClearKeepsPendingClearState` |
| Clear button | Enter `5 + 3`, then clear only the right-hand entry and continue with `7 =` | Pending operation is preserved and the final result is `12` | `testClearEntryKeepsPendingOperation` |
| Clear button | Enter `5 + 3`, clear the entry, then clear again and continue with `7 =` | Second clear performs all-clear; the final result is `7` | `testClearAllRemovesPendingOperation` |
| Clear button | Enter `5 + 3`, clear the entry, then continue with `7 =` | Clearing the entry still allows the original operation to continue | `testClearEntryAfterOperationCanThenContinue` |
| Clear button | Enter `9 ×`, then clear twice | First clear removes the pending operator context; second clear resets display to `0` | `testClearEntryRemovesPendingOperatorWhenNoRightHandEntry` |
| Clear button | Open a fresh view model | Initial state shows `0`, empty expression, and the all-clear button | `testInitialStateShowsAllClearButton` |
| Clear button | Evaluate `195 + 65 =`, then press clear | Clear acts as all-clear immediately after evaluation | `testClearAfterEqualsUsesAllClearImmediately` |
| Clear button | Evaluate `195 + 65 =`, clear, then enter `7` | New digit starts a fresh calculation with display `7` | `testDigitAfterAllClearFromEvaluatedResultStartsFreshCalculation` |
| Clear button | Enter `8`, apply square root, then clear | Standalone square root result uses all-clear behavior | `testClearAfterStandaloneSquareRootUsesAllClearBehavior` |
| Clear button | Enter `8`, apply square, then clear | Standalone square result uses all-clear behavior | `testClearAfterStandaloneSquareUsesAllClearBehavior` |
| Clear button | Enter `8`, apply reciprocal, then clear | Standalone reciprocal result uses all-clear behavior | `testClearAfterStandaloneReciprocalUsesAllClearBehavior` |
| Clear button | Start `9 × ( 985 + 1`, then clear inside the parentheses | Clearing rolls the state back to the outer `9 ×` operation before a second clear resets everything | `testClearInsideParenthesesRollsBackToOuterOperation` |
| Clear button | Enter `5 + 3`, clear the entry, then clear again | The second clear adds exactly one undo step | `testSecondClearFromBlankPendingEntryAddsSingleUndoStep` |
| Backspace | Enter `9 + 3`, then backspace three times | Backspace removes the right-hand digit, then the operator, then the left operand back to `0` | `testBackspaceCanRemovePendingDigitOperatorAndLeftOperand` |
| Backspace | Enter `3`, then backspace | Standalone backspace resets to a fresh all-clear state | `testBackspaceDeletingStandaloneDigitResetsToFreshAllClearState` |
| Backspace | Start `9 × ( 3 + 1`, then backspace repeatedly | Backspace fully unwinds the parenthesized expression back to `0` while keeping state balanced | `testBackspaceCanFullyUnwindParenthesizedExpression` |
| Clipboard | Enter `5 + 3`, clear the entry, then paste `7` | Pasted value becomes the pending operand and expression updates to `5 + 7` | `testPasteAfterPendingClearShowsPastedValue` |
| Parentheses | Build `2 + ( 3 + 4 ) × ( 5 + 1`, clear the inner entry, enter `6`, then close | Clearing inside nested parentheses keeps parenthesis depth balanced and expression becomes `2 + ( 3 + 4 ) × 6` | `testClearParenthesizedExpressionKeepsBalancedParenthesisDepth` |
| Rounding | Paste `10.123456`, enable rounding at precision `4`, set operator `+`, then type `0.0999999999` digit-by-digit | Operation display scale stays anchored to the LHS (`=round(10.123456 + 0.0999999999, 2) ≈`); scale does not drift to a value derived from the typed RHS | `testRoundingOperationScaleRemainsAnchoredToLHSWhileTypingRHSOperand` |
| Rounding | Same setup as above | While the RHS is being typed, the result display shows the full unrounded typed value (`0.0999999999`) rather than a prematurely rounded approximation | `testRoundingDisplayIsNotPrematurelyAppliedWhileTypingRHSOperand` |
| Rounding | Paste `10.123456`, enable rounding at precision `4`, `+ 0.0999999999`, then evaluate | After equals, display is `10.223456` and expression display uses a scale computed from the actual result value (`=round(10.2234559999, 6) ≈`) | `testRoundingFinalResultAfterPendingOperationUsesResultBasedScale` |
| Rounding | Paste `10.123456`, enable rounding at precision `4`, type `+ 0.0999999999`, then evaluate | `resultRoundingPrecision` remains `4` before the operator, while typing the RHS, and after evaluate; it never changes on its own | `testResultRoundingPrecisionPropertyRemainsFixedDuringFurtherInput` |