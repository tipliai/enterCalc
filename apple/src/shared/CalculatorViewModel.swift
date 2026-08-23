// src/shared/CalculatorViewModel.swift
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct HistoryEntry: Identifiable, Equatable {
    public let id = UUID()
    public let expression: String
    public let result: String
    public let displayExpression: String
    public let displayResult: String

    public init(
        expression: String,
        result: String,
        displayExpression: String,
        displayResult: String
    ) {
        self.expression = expression
        self.result = result
        self.displayExpression = displayExpression
        self.displayResult = displayResult
    }
}

public struct MemoryEntry: Identifiable, Equatable {
    public let id: UUID
    public let value: Double
    public let displayValue: String

    public init(id: UUID = UUID(), value: Double, displayValue: String) {
        self.id = id
        self.value = value
        self.displayValue = displayValue
    }
}

// The four standard arithmetic operators. Raw values are the display glyphs
// (note: subtract uses the minus sign U+2212, not a hyphen).
public enum BinaryOperator: String {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"

    var symbol: String { rawValue }

    // Calculations run in Decimal to match calculator-style rounding and avoid
    // binary floating-point residue.
    func apply(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        switch self {
        case .add: return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide: return lhs / rhs
        }
    }
}

/// Observable calculator brain that mirrors Microsoft Calculator behavior.
public final class CalculatorViewModel: ObservableObject {
    // Hard caps that bound input length, history/memory growth, undo depth, and
    // paste replay work so untrusted or pathological input can't blow up memory
    // or hang the UI.
    enum Limits {
        static let maxInputDigits = 16
        static let maxStoredHistoryEntries = 64
        static let maxHistoryExpressionCharacters = 512
        static let maxHistoryResultCharacters = 256
        static let maxStoredMemoryEntries = 64
        static let maxUndoDepth = 100
        static let maxRedoDepth = 100
        static let maxOperationChunks = maxUndoDepth
        static let maxConsecutiveSquareOrRootDepth = 25
        static let maxPasteCharacters = 512
        static let maxPasteReplaySteps = 256
        static let maxPasteNestingDepth = 32
        static let maxDisplayTokenLength = 160
    }

    private enum ParsedPasteContent {
        case value(String, currencySymbol: String?)
        case replay([PasteReplayStep], currencySymbol: String?)
        case roundedReplay(steps: [PasteReplayStep], precision: Int, currencySymbol: String?)
    }

    private enum ExpressionEvaluationError: Error {
        case invalidInput
        case divideByZero
        case overflow
        case underflow
    }

    private enum PasteReplayStep {
        case digit(String)
        case decimal
        case toggleSign
        case applyPercent
        case reciprocal
        case square
        case squareRoot
        case setOperator(BinaryOperator)
        case evaluate
    }

    // Immutable copy of all calculator state. Pushed onto the undo/redo stacks
    // so any user action can be reverted by restoring a snapshot wholesale.
    private struct CalculatorSnapshot: Equatable {
        let display: String
        let expressionDisplay: String
        let expression: String
        let history: [HistoryEntry]
        let lastResultSummary: String
        let memoryEntries: [MemoryEntry]
        let isErrorState: Bool
        let currentErrorKey: String?
        let currentInput: String
        let accumulator: Decimal?
        let pendingOperator: BinaryOperator?
        let lastOperator: BinaryOperator?
        let lastOperand: Decimal?
        let shouldResetInputOnNextDigit: Bool
        let justEvaluated: Bool
        let currentToken: String
        let accumulatorToken: String?
        let lastOperandToken: String?
        let expressionTokens: [String]
        let openParenthesisCount: Int
        let isExpressionMode: Bool
        let isResultRoundingEnabled: Bool
        let resultRoundingPrecision: Int
        let activeCurrencySymbol: String?
        let isPendingEntryClearedByClearButton: Bool
        let shouldPreserveTypedCurrencyInput: Bool
        let resultUsesPercentToken: Bool
        let displayEditCursorIndex: Int?
    }

    // Published state: what the UI renders. `display` is the large result line,
    // `expressionDisplay` the operation line above it; the rest drive overlays
    // (history, memory, rounding) and error styling.
    @Published public private(set) var display: String = "0"
    @Published public private(set) var expressionDisplay: String = ""
    @Published public private(set) var expression: String = ""
    @Published public private(set) var history: [HistoryEntry] = []
    @Published public private(set) var lastResultSummary: String = ""
    @Published public private(set) var memoryEntries: [MemoryEntry] = []
    @Published public private(set) var isErrorState: Bool = false
    @Published public private(set) var usesScientificNotation: Bool = true
    @Published public private(set) var numberFormatStyle: NumberFormatStyle = .western
    @Published public private(set) var isResultRoundingEnabled: Bool = false
    @Published public private(set) var resultRoundingPrecision: Int = 4
    @Published public private(set) var activeCurrencySymbol: String?
    /// Monotonic count of calculations carried through to a result, used to
    /// judge whether the app is genuinely in use. Deliberately outside the undo
    /// snapshot and unaffected by clearing history: it records what the person
    /// did, not what the calculator currently shows.
    public private(set) var completedCalculationCount: Int = 0
    @Published public private(set) var displayEditCursorIndex: Int?
    private var currentErrorKey: String? = nil

    // Internal state machine. `accumulator` holds the running left-hand value,
    // `pendingOperator` the operator awaiting a right operand, and the `last*`
    // fields remember the previous operation so repeated `=` can replay it.
    private var currentInput: String = "0"
    private var accumulator: Decimal?
    private var pendingOperator: BinaryOperator?
    private var lastOperator: BinaryOperator?
    private var lastOperand: Decimal?
    private var shouldResetInputOnNextDigit = false
    private var justEvaluated = false
    private var isPendingEntryClearedByClearButton = false
    private var undoStack: [CalculatorSnapshot] = []
    private var redoStack: [CalculatorSnapshot] = []
    private var suppressHistoryTracking = false
    private var roundingInteractionSnapshot: CalculatorSnapshot?
    private var roundingInteractionInitialEnabled: Bool?
    private var roundingInteractionInitialPrecision: Int?
    private var shouldPreserveTypedCurrencyInput = false
    // Set when an evaluation produced a percentage of a percentage (9% + 9%), so
    // the result line renders "18%" over the stored decimal 0.18.
    private var resultUsesPercentToken = false

    public init(numberFormatStyle: NumberFormatStyle = .western, usesScientificNotation: Bool = true) {
        self.numberFormatStyle = numberFormatStyle
        self.usesScientificNotation = usesScientificNotation
    }

    public var maxResultRoundingPrecision: Int {
        Limits.maxInputDigits
    }

    public func beginResultRounding(defaultPrecision: Int = 4) {
        if roundingInteractionSnapshot == nil {
            roundingInteractionSnapshot = beginUndoableChange()
            roundingInteractionInitialEnabled = isResultRoundingEnabled
            roundingInteractionInitialPrecision = resultRoundingPrecision
        }
    }

    public func setResultRoundingPrecision(_ precision: Int) {
        let normalized = normalizedRoundingPrecision(precision)
        let didChange = resultRoundingPrecision != normalized || !isResultRoundingEnabled
        resultRoundingPrecision = normalized
        isResultRoundingEnabled = true
        if didChange {
            updateDisplay()
        }
    }

    public func removeResultRounding() {
        guard isResultRoundingEnabled else { return }
        isResultRoundingEnabled = false
        updateDisplay()
    }

    public func commitResultRoundingInteraction() {
        guard let snapshot = roundingInteractionSnapshot else { return }

        let initialEnabled = roundingInteractionInitialEnabled ?? isResultRoundingEnabled
        let initialPrecision = roundingInteractionInitialPrecision ?? resultRoundingPrecision
        let netChanged = initialEnabled != isResultRoundingEnabled
            || (isResultRoundingEnabled && initialPrecision != resultRoundingPrecision)

        if netChanged {
            appendRoundedHistoryEventIfNeeded()
        }

        roundingInteractionSnapshot = nil
        roundingInteractionInitialEnabled = nil
        roundingInteractionInitialPrecision = nil
        completeUndoableChange(from: snapshot)
    }

    public var memoryValue: Double? {
        memoryEntries.first?.value
    }

    public var memoryDisplay: String? {
        memoryEntries.first?.displayValue
    }

    public var hasOperationToCopy: Bool {
        currentOperationCopyString() != nil
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public var canDirectlyEditDisplay: Bool {
        guard !isErrorState,
              !isResultRoundingEnabled,
              !shouldDisplayPercentTokenAsMainDisplay else {
            return false
        }

        return !currentInput.lowercased().contains("e")
    }

    public var displayEditCaretBoundaryIndex: Int? {
        guard let rawIndex = activeDisplayEditCursorIndex else { return nil }
        return displayBoundaryIndex(forRawCursorIndex: rawIndex)
    }

    public func setDisplayEditCursor(displayBoundaryIndex: Int) {
        guard canDirectlyEditDisplay else {
            displayEditCursorIndex = nil
            return
        }

        prepareCurrentInputForDirectDisplayEditing()
        let mapping = displayBoundaryToRawCursorMapping()
        guard mapping.indices.contains(displayBoundaryIndex) else { return }
        displayEditCursorIndex = mapping[displayBoundaryIndex]
    }

    public func clearDisplayEditCursor() {
        displayEditCursorIndex = nil
    }

    public var isDirectlyEditingDisplay: Bool {
        activeDisplayEditCursorIndex != nil
    }

    @discardableResult
    public func moveDisplayEditCursorLeft() -> Bool {
        guard canDirectlyEditDisplay else {
            displayEditCursorIndex = nil
            return false
        }

        if displayEditCursorIndex == nil {
            prepareCurrentInputForDirectDisplayEditing()
        }
        let currentIndex = activeDisplayEditCursorIndex ?? currentInput.count
        let nextIndex = normalizedDisplayEditCursorIndex(currentIndex - 1)
        let didMove = nextIndex != currentIndex || displayEditCursorIndex == nil
        displayEditCursorIndex = nextIndex
        return didMove
    }

    @discardableResult
    public func moveDisplayEditCursorRight() -> Bool {
        guard canDirectlyEditDisplay else {
            displayEditCursorIndex = nil
            return false
        }

        if displayEditCursorIndex == nil {
            prepareCurrentInputForDirectDisplayEditing()
        }
        let currentIndex = activeDisplayEditCursorIndex ?? currentInput.count
        let nextIndex = normalizedDisplayEditCursorIndex(currentIndex + 1)
        let didMove = nextIndex != currentIndex || displayEditCursorIndex == nil
        displayEditCursorIndex = nextIndex
        return didMove
    }

    public var shouldShowAllClearButton: Bool {
        isErrorState || isPendingEntryClearedByClearButton || isStandaloneUnaryResult || isResultStateUsingAllClear || isInClearAllState
    }

    var undoDepth: Int {
        undoStack.count
    }

    var redoDepth: Int {
        redoStack.count
    }

    // Maximum absolute value the NumberFormatter can display before clipping to 0.
    // Determined by maximumIntegerDigits = 32 in the formatter (values >= 1e32 are clipped).
    private static let maxFormatterMagnitude: Double = 1e32

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesSignificantDigits = true
        f.minimumSignificantDigits = 1
        f.maximumSignificantDigits = Limits.maxInputDigits
        // Allow large results (e.g., 16-digit × 16-digit) without clamping to 0.
        f.maximumIntegerDigits = 32
        f.usesGroupingSeparator = false
        return f
    }()

    private let scientificMantissaFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumIntegerDigits = 1
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = Limits.maxInputDigits - 1
        f.usesGroupingSeparator = false
        return f
    }()

    private var currentValue: Decimal {
        parseStoredNumber(currentInput) ?? 0
    }

    private var currentDoubleValue: Double {
        parseStoredNumber(currentInput).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    }

    private static let supportedCurrencySymbolCharacters = Set("$€£¥₹₩₽¢฿₺₫₴₪₦₱₲₡₵₭₮₤₳₸₼₾₣₠₧₯₿")
    private static let minimumRoundedCurrencyFractionDigits = 2

    // Human-readable token for the current input, including unary wrappers (e.g., "√(4)").
    private var currentToken: String = "0"
    private var accumulatorToken: String?
    private var lastOperandToken: String?
    private var pendingParenthesisExpressionSeedTokens: [String]?
    private var expressionTokens: [String] = []
    private var openParenthesisCount: Int = 0
    private var isExpressionMode = false

    // Inserts a parenthesis, choosing open vs close based on the current
    // expression so a single button can toggle between them naturally.
    public func inputParentheses() {
        let symbol: Character = shouldInsertClosingParenthesisInExpressionMode() ? ")" : "("
        inputParenthesis(symbol)
    }

    public func inputParenthesis(_ symbol: Character) {
        guard symbol == "(" || symbol == ")" else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        if isErrorState {
            resetStateForNewEntry()
        }
        enterExpressionModeIfNeeded()

        if symbol == "(" {
            if !shouldResetInputOnNextDigit {
                appendCurrentTokenToExpressionIfNeeded()
            }
            if let last = expressionTokens.last,
               isExpressionValueToken(last) || last == ")" {
                expressionTokens.append(BinaryOperator.multiply.symbol)
            }
            expressionTokens.append("(")
            openParenthesisCount += 1
            shouldResetInputOnNextDigit = true
            justEvaluated = false
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if !shouldResetInputOnNextDigit {
            appendCurrentTokenToExpressionIfNeeded()
        }

        guard openParenthesisCount > 0,
              let last = expressionTokens.last,
              isExpressionValueToken(last) || last == ")" else {
            completeUndoableChange(from: snapshot)
            return
        }

        expressionTokens.append(")")
        openParenthesisCount -= 1
        shouldResetInputOnNextDigit = true
        justEvaluated = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Appends a digit to the current operand. Handles the reset-on-next-digit
    // flag (after evaluation or an operator) and direct display cursor editing.
    public func inputDigit(_ digit: String) {
        guard digit.count == 1, "0123456789".contains(digit) else { return }
        let snapshot = beginUndoableChange()
        let isEditingDisplay = activeDisplayEditCursorIndex != nil
        if isErrorState { resetStateForNewEntry() }
        isPendingEntryClearedByClearButton = false
        if justEvaluated, !isEditingDisplay {
            resetStateForNewEntry()
        } else if shouldResetInputOnNextDigit, !isEditingDisplay {
            currentInput = "0"
            shouldResetInputOnNextDigit = false
        }
        isErrorState = false
        if let cursorIndex = activeDisplayEditCursorIndex {
            let previousInput = currentInput
            let previousCursor = displayEditCursorIndex
            insertDigitIntoCurrentInput(digit, at: cursorIndex)
            if currentInput != previousInput || displayEditCursorIndex != previousCursor {
                resetPostEvaluateStateForDirectDisplayEditingIfNeeded()
            }
        } else if currentInput == "0" {
            currentInput = digit
        } else if currentInputDigitCount < Limits.maxInputDigits {
            currentInput.append(digit)
        }
        shouldPreserveTypedCurrencyInput = activeCurrencySymbol != nil
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func inputCurrencySymbol(_ symbol: String) {
        guard symbol != "¢", Self.isSupportedCurrencySymbol(symbol) else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        if isErrorState {
            resetStateForNewEntry()
        }
        isPendingEntryClearedByClearButton = false
        activeCurrencySymbol = symbol
        refreshCurrentSessionDisplayTokens()
        completeUndoableChange(from: snapshot)
    }

    // Inserts the locale decimal separator, guarding against a second separator
    // in the same operand.
    public func inputDecimal() {
        let snapshot = beginUndoableChange()
        let isEditingDisplay = activeDisplayEditCursorIndex != nil
        if isErrorState { resetStateForNewEntry() }
        isPendingEntryClearedByClearButton = false
        if justEvaluated, !isEditingDisplay {
            resetStateForNewEntry()
        } else if shouldResetInputOnNextDigit, !isEditingDisplay {
            currentInput = "0"
            shouldResetInputOnNextDigit = false
        }
        isErrorState = false
        let decimalSeparator = numberFormatStyle.decimalSeparator
        if let cursorIndex = activeDisplayEditCursorIndex {
            let previousInput = currentInput
            let previousCursor = displayEditCursorIndex
            insertDecimalIntoCurrentInput(at: cursorIndex)
            if currentInput != previousInput || displayEditCursorIndex != previousCursor {
                resetPostEvaluateStateForDirectDisplayEditingIfNeeded()
            }
        } else if !currentInput.contains(decimalSeparator), !currentInput.contains("."), currentInputDigitCount < Limits.maxInputDigits {
            currentInput.append(contentsOf: decimalSeparator)
        }
        shouldPreserveTypedCurrencyInput = activeCurrencySymbol != nil
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Flips the sign of the current operand. "0" stays unsigned so we never show
    // a stray "-0".
    public func toggleSign() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        if currentInput.hasPrefix("-") {
            currentInput.removeFirst()
        } else if currentInput != "0" {
            currentInput = "-" + currentInput
        }
        shouldPreserveTypedCurrencyInput = activeCurrencySymbol != nil
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Applies a percent. Standalone it scales the operand by 1/100; with a
    // pending operation it is interpreted relative to the left operand (e.g.
    // 200 + 10% = 220), matching standard calculator behavior.
    public func applyPercent() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        // A percent-of-percent result displays as "18%" over a stored 0.18.
        // Applying % again works from that value, not the token, so the result
        // is 0.18% rather than a doubled-up "18%%".
        let operandToken = resultUsesPercentToken
            ? displayString(for: currentInput, useActiveCurrency: false)
            : currentToken
        resultUsesPercentToken = false
        let percentOperandToken = activeCurrencySymbol == nil
            ? operandToken
            : displayString(for: currentInput, useActiveCurrency: false)
        let percentToken = boundedDisplayToken(
            "\(percentOperandToken)%",
            fallback: displayString(for: currentInput, useActiveCurrency: activeCurrencySymbol == nil)
        )
        let percentValue = resolvedPercentValue()
        currentInput = format(percentValue)
        shouldPreserveTypedCurrencyInput = false
        if pendingOperator == nil {
            currentToken = percentToken
            if !isExpressionMode {
                expression = currentToken
            }
        } else if pendingOperandShouldKeepPercentToken || pendingOperatorShouldKeepPercentToken || activeCurrencySymbol != nil {
            currentToken = percentToken
        } else {
            currentToken = displayString(for: currentInput, useActiveCurrency: false)
        }
        justEvaluated = false
        shouldResetInputOnNextDigit = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func clearEntry() {
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()

        if shouldUseAllClearBehavior {
            resetAllStateForClearAll()
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if clearParenthesizedExpressionIfNeeded() {
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if pendingOperator != nil, shouldResetInputOnNextDigit {
            // C should keep a pending expression intact when no right-hand entry is active.
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if pendingOperator != nil {
            setBlankPendingEntryState()
        } else {
            setBlankPendingEntryState()
        }

        justEvaluated = false
        isErrorState = false
        currentErrorKey = nil
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Full reset to the initial state (AC). Rounding and currency context are
    // cleared too, since they belong to the prior calculation.
    public func clearAll() {
        let snapshot = beginUndoableChange()
        resetAllStateForClearAll()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    private func resetAllStateForClearAll() {
        currentInput = "0"
        accumulator = nil
        pendingOperator = nil
        lastOperator = nil
        lastOperand = nil
        lastResultSummary = ""
        expression = ""
        resultUsesPercentToken = false
        shouldResetInputOnNextDigit = false
        justEvaluated = false
        isErrorState = false
        currentErrorKey = nil
        accumulatorToken = nil
        currentToken = "0"
        lastOperandToken = nil
        expressionTokens.removeAll()
        openParenthesisCount = 0
        isExpressionMode = false
        isPendingEntryClearedByClearButton = false
        shouldPreserveTypedCurrencyInput = false
        isResultRoundingEnabled = false
        resultRoundingPrecision = 4
        activeCurrencySymbol = nil
        displayEditCursorIndex = nil
    }

    // Deletes the last input. Behavior is contextual: it removes whole tokens in
    // expression mode, recovers from an error, or trims a digit otherwise.
    public func backspace() {
        if currentErrorKey == "error.invalidInput" {
            undo()
            return
        }

        let snapshot = beginUndoableChange()
        if isErrorState {
            resetAllStateForClearAll()
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }
        if backspaceExpressionTokenIfNeeded() {
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }
        if shouldResetInputOnNextDigit, pendingOperator != nil {
            // Convert non-expression pending previews into expression-mode editing
            // so backspace walks tokens without forcing an implicit evaluation.
            enterExpressionModeIfNeeded()
            _ = backspaceExpressionTokenIfNeeded()
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        isPendingEntryClearedByClearButton = false

        if let cursorIndex = activeDisplayEditCursorIndex {
            let previousInput = currentInput
            let previousCursor = displayEditCursorIndex
            deleteDigitBeforeDisplayCursor(cursorIndex)
            if currentInput != previousInput || displayEditCursorIndex != previousCursor {
                resetPostEvaluateStateForDirectDisplayEditingIfNeeded()
            }
            shouldPreserveTypedCurrencyInput = activeCurrencySymbol != nil
            setCurrentTokenToCurrentInput()
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if shouldResetInputOnNextDigit {
            currentInput = "0"
            shouldResetInputOnNextDigit = false
        } else if currentInput.count > 1 {
            currentInput.removeLast()
        } else if currentInput != "0" {
            if removeActiveExpressionValueTokenIfNeeded() {
                updateDisplay()
                completeUndoableChange(from: snapshot)
                return
            }

            if isExpressionMode || pendingOperator != nil {
                setBlankPendingEntryState()
            } else {
                resetAllStateForClearAll()
            }
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        } else {
            currentInput = "0"
        }
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Records a pending binary operator. If one is already pending it evaluates
    // first (chained operations), and in expression mode it appends the operator
    // token instead.
    public func setOperator(_ op: BinaryOperator) {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        pendingParenthesisExpressionSeedTokens = nil
        if isExpressionMode {
            if !shouldResetInputOnNextDigit {
                appendCurrentTokenToExpressionIfNeeded()
            } else if expressionTokens.isEmpty {
                expressionTokens.append(currentToken)
            }

            guard let last = expressionTokens.last else {
                completeUndoableChange(from: snapshot)
                return
            }

            if last == "(" {
                completeUndoableChange(from: snapshot)
                return
            }

            let isReplacingTrailingOperator = isExpressionOperatorToken(last)
            if !isReplacingTrailingOperator,
               operationChunkCount(in: expressionTokens) >= Limits.maxOperationChunks {
                completeUndoableChange(from: snapshot)
                return
            }

            if isReplacingTrailingOperator {
                expressionTokens.removeLast()
            }

            expressionTokens.append(op.symbol)
            shouldResetInputOnNextDigit = true
            justEvaluated = false
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if let existingPending = pendingOperator,
           shouldResetInputOnNextDigit {
            if existingPending == op {
                completeUndoableChange(from: snapshot)
                return
            }

            let pendingExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pendingExpression.isEmpty,
               pendingExpression.hasSuffix(existingPending.symbol) {
                let expressionWithoutOperator = pendingExpression
                    .dropLast(existingPending.symbol.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                expression = expressionWithoutOperator.isEmpty
                    ? op.symbol
                    : "\(expressionWithoutOperator) \(op.symbol)"
                pendingOperator = op
                justEvaluated = false
                updateDisplay()
                completeUndoableChange(from: snapshot)
                return
            }
        }

        let didBuildChainedExpression: Bool
        if let existingPending = pendingOperator, !shouldResetInputOnNextDigit {
            if nonExpressionOperationChunkCountIncludingCurrentInput() >= Limits.maxOperationChunks {
                completeUndoableChange(from: snapshot)
                return
            }

            let previousExpression = expression
            let previousLhsToken = accumulatorToken ?? currentToken
            let previousRhsToken = currentToken
            let previousRhsInput = currentInput
            let shouldGroupCompletedExpression =
                (existingPending == .add || existingPending == .subtract)
                && (op == .multiply || op == .divide)
                && (previousExpression.contains(BinaryOperator.multiply.symbol)
                    || previousExpression.contains(BinaryOperator.divide.symbol))
            if (existingPending == .add || existingPending == .subtract),
               (op == .multiply || op == .divide) {
                let lhsToken = accumulatorToken ?? currentToken
                pendingParenthesisExpressionSeedTokens = [lhsToken, existingPending.symbol, currentToken, op.symbol]
            }
            performPendingOperation(addToHistory: false, refreshDisplay: false)
            if isErrorState {
                completeUndoableChange(from: snapshot)
                return
            }
            // Keep the currently typed right operand visible until evaluate, even when
            // the internal pending accumulator advances for chained operations.
            currentInput = previousRhsInput
            currentToken = previousRhsToken
            expression = chainedExpressionPreview(
                existingExpression: previousExpression,
                lhsToken: previousLhsToken,
                completedOperator: existingPending,
                rhsToken: previousRhsToken,
                nextOperator: op,
                shouldGroupCompletedExpression: shouldGroupCompletedExpression
            )
            didBuildChainedExpression = true
        } else if accumulator == nil {
            accumulator = currentValue
            accumulatorToken = currentToken
            didBuildChainedExpression = false
        } else {
            didBuildChainedExpression = false
        }
        pendingOperator = op
        if !didBuildChainedExpression {
            expression = makeExpressionPreview()
        }
        shouldResetInputOnNextDigit = true
        justEvaluated = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Computes the result (=). Expression mode evaluates the full token stream
    // (auto-closing open parentheses) with operator precedence; otherwise it
    // finishes the pending binary operation. Repeated equals does not replay.
    public func evaluate() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        if isExpressionMode {
            if !shouldResetInputOnNextDigit {
                appendCurrentTokenToExpressionIfNeeded()
            } else if expressionTokens.isEmpty {
                expressionTokens.append(currentToken)
            }

            guard !expressionTokens.isEmpty else {
                completeUndoableChange(from: snapshot)
                return
            }

            var evaluationTokens = expressionTokens
            while openParenthesisCount > 0 {
                evaluationTokens.append(")")
                openParenthesisCount -= 1
            }

            switch evaluateExpressionTokens(evaluationTokens) {
            case .success(let result):
                let resultText = format(result)
                let evaluatedExpression = evaluationTokens.joined(separator: " ")
                let displayExpression = completedOperationDisplayExpression(evaluatedExpression)
                appendHistory(expression: evaluatedExpression, result: resultText, displayExpressionOverride: displayExpression)
                lastResultSummary = displayExpression + " ="
                currentInput = resultText
                currentToken = displayString(for: resultText, useActiveCurrency: false)
                accumulator = result
                accumulatorToken = displayString(for: resultText, useActiveCurrency: false)
                pendingOperator = nil
                lastOperator = nil
                lastOperand = nil
                lastOperandToken = nil
                expression = ""
                expressionTokens.removeAll()
                openParenthesisCount = 0
                isExpressionMode = false
                shouldResetInputOnNextDigit = true
                justEvaluated = true
                updateDisplay()
            case .failure(.divideByZero):
                expressionTokens.removeAll()
                openParenthesisCount = 0
                isExpressionMode = false
                setError("error.divideByZero")
            case .failure(.invalidInput):
                expressionTokens.removeAll()
                openParenthesisCount = 0
                isExpressionMode = false
                setError("error.invalidInput")
            case .failure(.overflow):
                expressionTokens.removeAll()
                openParenthesisCount = 0
                isExpressionMode = false
                setError("error.outOfRange")
            case .failure(.underflow):
                expressionTokens.removeAll()
                openParenthesisCount = 0
                isExpressionMode = false
                setError("error.outOfRange")
            }
            completeUndoableChange(from: snapshot)
            return
        }

        if pendingOperator != nil {
            if shouldResetInputOnNextDigit {
                // No right-hand operand was entered after the operator; finalize
                // the existing accumulated value without duplicating the operand.
                evaluateTrailingPendingOperatorAsStandaloneResult()
            } else if evaluatePendingExpressionWithDisplayedPrecedence() {
                // handled inside helper
            } else {
                performPendingOperation(addToHistory: true)
            }
        } else if justEvaluated {
            // Repeated equals should not replay the previous operation.
            if lastResultSummary.isEmpty {
                lastResultSummary = "\(currentToken) ="
            }
            shouldResetInputOnNextDigit = true
            updateDisplay()
        } else {
            accumulator = currentValue
            accumulatorToken = displayString(for: currentInput, useActiveCurrency: false)
            lastResultSummary = "\(currentToken) ="
            shouldResetInputOnNextDigit = true
            justEvaluated = true
            updateDisplay()
        }
        completeUndoableChange(from: snapshot)
    }

    // Finalizes a pending operation where no right-hand operand was entered (the
    // user pressed = immediately after an operator). The trailing operator is
    // dropped and the accumulated left-hand value is used as the result, so the
    // history entry reflects only the complete portion of the expression.
    private func evaluateTrailingPendingOperatorAsStandaloneResult() {
        guard let pending = pendingOperator else { return }

        let result = accumulator ?? currentValue
        let resultText = format(result)
        let pendingExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        let baseExpression: String
        if !pendingExpression.isEmpty, pendingExpression.hasSuffix(pending.symbol) {
            let trimmed = pendingExpression
                .dropLast(pending.symbol.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            baseExpression = trimmed.isEmpty ? (accumulatorToken ?? currentToken) : trimmed
        } else if !pendingExpression.isEmpty {
            baseExpression = pendingExpression
        } else {
            baseExpression = accumulatorToken ?? currentToken
        }

        let displayExpression = completedOperationDisplayExpression(baseExpression)
        appendHistory(expression: baseExpression, result: resultText, displayExpressionOverride: displayExpression)
        lastResultSummary = displayExpression + " ="
        currentInput = resultText
        currentToken = displayString(for: resultText, useActiveCurrency: false)
        accumulator = result
        accumulatorToken = displayString(for: resultText, useActiveCurrency: false)
        pendingOperator = nil
        lastOperator = nil
        lastOperand = nil
        lastOperandToken = nil
        expression = ""
        shouldResetInputOnNextDigit = true
        justEvaluated = true
        updateDisplay()
    }

    private func evaluatePendingExpressionWithDisplayedPrecedence() -> Bool {
        guard let pending = pendingOperator else { return false }

        // Preserve existing calculator-style percent semantics (e.g. 10 + 10% = 11)
        // by falling back to immediate pending-operation evaluation when % is present.
        let pendingExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingExpression.isEmpty else {
            return false
        }

        let evaluationExpression: String
        if pendingExpression.hasSuffix(pending.symbol) {
            evaluationExpression = "\(pendingExpression) \(currentToken)"
        } else {
            evaluationExpression = pendingExpression
        }

        let normalizedEvaluationExpression = evaluationExpression.lowercased()
        guard !evaluationExpression.contains("%"),
              !normalizedEvaluationExpression.contains("e+"),
              !normalizedEvaluationExpression.contains("e-") else {
            return false
        }

        let evaluationTokens = evaluationExpression
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !evaluationTokens.isEmpty else { return false }

        let hasAdditiveOperator = evaluationTokens.contains { isDisplayAdditiveOperator($0) }
        let hasMultiplicativeOperator = evaluationTokens.contains { isDisplayMultiplicativeOperator($0) }
        guard hasAdditiveOperator, hasMultiplicativeOperator else {
            return false
        }

        switch evaluateExpressionTokens(evaluationTokens) {
        case .success(let result):
            let resultText = format(result)
            let evaluatedExpression = evaluationTokens.joined(separator: " ")
            let displayExpression = completedOperationDisplayExpression(evaluatedExpression)
            appendHistory(expression: evaluatedExpression, result: resultText, displayExpressionOverride: displayExpression)
            lastResultSummary = displayExpression + " ="
            currentInput = resultText
            currentToken = displayString(for: resultText, useActiveCurrency: false)
            accumulator = result
            accumulatorToken = displayString(for: resultText, useActiveCurrency: false)
            pendingOperator = nil
            lastOperator = nil
            lastOperand = nil
            lastOperandToken = nil
            expression = ""
            shouldResetInputOnNextDigit = true
            justEvaluated = true
            updateDisplay()
            return true
        case .failure(.divideByZero):
            setError("error.divideByZero")
            return true
        case .failure(.invalidInput):
            setError("error.invalidInput")
            return true
        case .failure(.overflow):
            setError("error.outOfRange")
            return true
        case .failure(.underflow):
            setError("error.outOfRange")
            return true
        }
    }

    // Computes 1/x. Guards against divide-by-zero and display underflow, and
    // wraps the operand token as "1/(...)" so the expression stays readable.
    public func reciprocal() {
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        if nextUnaryChainDepth(for: currentToken) > Limits.maxConsecutiveSquareOrRootDepth {
            setError("error.outOfRange")
            completeUndoableChange(from: snapshot)
            return
        }
        let value = currentValue
        guard value != 0 else {
            setError("error.divideByZero")
            completeUndoableChange(from: snapshot)
            return
        }
        let operandToken = currentToken
        let result = Decimal(1) / value
        if valueWouldUnderflowDisplay(result) {
            setError("error.outOfRange")
            completeUndoableChange(from: snapshot)
            return
        }
        currentInput = format(result)
        currentToken = boundedDisplayToken("1/(\(operandToken))", fallback: groupedNumberString(currentInput))
        if isExpressionMode {
            applyCurrentUnaryTokenToExpression()
        } else {
            expression = pendingOperator == nil ? currentToken : expression
        }
        justEvaluated = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Computes x squared. A negative operand keeps its sign in the result
    // (-2 squared shows as -4) to mirror exponent precedence where the unary
    // minus binds looser than the power (-2 squared == -(2 squared)). Range guarded.
    public func square() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        if nextUnaryChainDepth(for: currentToken) > Limits.maxConsecutiveSquareOrRootDepth {
            setError("error.outOfRange")
            completeUndoableChange(from: snapshot)
            return
        }
        let val = currentValue
        let dbl = NSDecimalNumber(decimal: val).doubleValue
        if abs(dbl) >= Self.maxFormatterMagnitude.squareRoot() {
            setError("error.outOfRange")
            completeUndoableChange(from: snapshot)
            return
        }
        let isNegativeOperand = val < 0
        var result = val * val
        if isNegativeOperand {
            result = -result
        }
        if valueWouldUnderflowDisplay(result) {
            setError("error.outOfRange")
            completeUndoableChange(from: snapshot)
            return
        }
        let operandToken = currentToken
        currentInput = format(result)
        currentToken = boundedDisplayToken("sqr(\(operandToken))", fallback: groupedNumberString(currentInput))
        if isExpressionMode {
            applyCurrentUnaryTokenToExpression()
        } else {
            expression = pendingOperator == nil ? currentToken : expression
        }
        justEvaluated = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    // Computes the square root. Negative inputs are an invalid-input error; the
    // operand token is wrapped as "√(...)".
    public func squareRoot() {
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        isPendingEntryClearedByClearButton = false
        if nextUnaryChainDepth(for: currentToken) > Limits.maxConsecutiveSquareOrRootDepth {
            setError("error.outOfRange")
            completeUndoableChange(from: snapshot)
            return
        }
        let decimalValue = currentValue
        let value = currentDoubleValue
        if value < 0 {
            setError("error.invalidInput")
        } else if decimalValue != 0 && value == 0 {
            setError("error.outOfRange")
        } else {
            let operandToken = currentToken
            let root = sqrt(value)
            let rootDecimal = Decimal(root)
            if valueWouldUnderflowDisplay(rootDecimal) {
                setError("error.outOfRange")
                completeUndoableChange(from: snapshot)
                return
            }
            currentInput = format(rootDecimal)
            currentToken = boundedDisplayToken("√(\(operandToken))", fallback: groupedNumberString(currentInput))
            if isExpressionMode {
                applyCurrentUnaryTokenToExpression()
            } else {
                expression = pendingOperator == nil ? currentToken : expression
            }
            justEvaluated = false
            updateDisplay()
        }
        completeUndoableChange(from: snapshot)
    }

    public func copyToPasteboard() {
        writeStringToPasteboard(display)
    }

    public func copyOperationToPasteboard() {
        guard let operation = currentOperationCopyString() else { return }
        writeStringToPasteboard(operation)
    }

    public func copyOperationToPasteboard(_ entry: HistoryEntry) {
        writeStringToPasteboard(operationCopyString(expression: entry.displayExpression, result: entry.displayResult))
    }

    public func copyResultToPasteboard(_ entry: HistoryEntry) {
        writeStringToPasteboard(entry.displayResult)
    }

    public func pasteFromPasteboard() {
        let snapshot = beginUndoableChange()
        finishDirectDisplayEditingIfNeeded()
        let string: String?
        #if os(macOS)
        string = NSPasteboard.general.string(forType: .string)
        #else
        string = UIPasteboard.general.string
        #endif
        guard let string = string else {
            completeUndoableChange(from: snapshot)
            return
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Limits.maxPasteCharacters else {
            completeUndoableChange(from: snapshot)
            return
        }
        switch parsePastedContent(trimmed) {
        case .value(let rawValue, let currencySymbol):
            guard let normalized = normalizePastedNumber(rawValue), let value = decimalValue(fromCanonicalString: normalized) else {
                completeUndoableChange(from: snapshot)
                return
            }
            if let currencySymbol {
                activeCurrencySymbol = currencySymbol
            }
            isPendingEntryClearedByClearButton = false
            let isReplacingPendingOperand = pendingOperator != nil || accumulator != nil
            currentInput = formattedPastedInput(fromCanonical: normalized, value: value)
            shouldPreserveTypedCurrencyInput = false
            currentToken = displayString(for: currentInput, useActiveCurrency: false)
            if !isReplacingPendingOperand {
                expression = ""
                lastOperator = nil
                lastOperand = nil
                pendingOperator = nil
                accumulator = nil
                accumulatorToken = nil
                lastOperandToken = nil
                lastResultSummary = ""
            }
            shouldResetInputOnNextDigit = false
            justEvaluated = false
            isErrorState = false
            currentErrorKey = nil
            isResultRoundingEnabled = false
            updateDisplay()
        case .replay(let steps, let currencySymbol):
            let tempModel = CalculatorViewModel(numberFormatStyle: numberFormatStyle, usesScientificNotation: usesScientificNotation)
            tempModel.suppressHistoryTracking = true
            if let currencySymbol {
                tempModel.inputCurrencySymbol(currencySymbol)
            }
            for step in steps {
                tempModel.applyPasteReplayStep(step)
                if tempModel.isErrorState {
                    break
                }
            }
            adoptPastedState(from: tempModel)
            isResultRoundingEnabled = false
        case .roundedReplay(let steps, let precision, let currencySymbol):
            let tempModel = CalculatorViewModel(numberFormatStyle: numberFormatStyle, usesScientificNotation: usesScientificNotation)
            tempModel.suppressHistoryTracking = true
            if let currencySymbol {
                tempModel.inputCurrencySymbol(currencySymbol)
            }
            for step in steps {
                tempModel.applyPasteReplayStep(step)
                if tempModel.isErrorState {
                    break
                }
            }
            adoptPastedState(from: tempModel)
            setResultRoundingPrecision(precision)
        }
        completeUndoableChange(from: snapshot)
    }

    public func reuse(_ entry: HistoryEntry) {
        let snapshot = beginUndoableChange()
        activeCurrencySymbol = explicitCurrencySymbol(in: entry.expression) ?? explicitCurrencySymbol(in: entry.result)
        if let rounded = parseRoundedOperation(entry.expression),
           let recalculated = evaluateExpressionString(rounded.baseExpression) {
            currentInput = recalculated
            shouldPreserveTypedCurrencyInput = false
            setResultRoundingPrecision(rounded.precision)
            lastResultSummary = "\(rounded.baseExpression) ="
        } else {
            currentInput = normalizePastedNumber(entry.result) ?? entry.result
            shouldPreserveTypedCurrencyInput = false
            isResultRoundingEnabled = false
            lastResultSummary = "\(entry.expression) ="
        }
        accumulator = nil
        pendingOperator = nil
        lastOperator = nil
        lastOperand = nil
        expression = ""
        currentToken = displayString(for: currentInput, useActiveCurrency: false)
        accumulatorToken = nil
        lastOperandToken = nil
        shouldResetInputOnNextDigit = true
        justEvaluated = true
        isErrorState = false
        currentErrorKey = nil
        isPendingEntryClearedByClearButton = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func clearHistory() {
        let snapshot = beginUndoableChange()
        history.removeAll()
        completeUndoableChange(from: snapshot)
    }

    public func clearMemory() {
        let snapshot = beginUndoableChange()
        memoryEntries.removeAll()
        completeUndoableChange(from: snapshot)
    }

    public func storeMemory() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        insertMemoryEntry(currentValue)
        completeUndoableChange(from: snapshot)
    }

    public func recallMemory() {
        guard let entry = memoryEntries.first else { return }
        recallMemory(entry)
    }

    public func recallMemory(_ entry: MemoryEntry) {
        let snapshot = beginUndoableChange()
        isPendingEntryClearedByClearButton = false
        let value = decimalValue(fromDisplayText: entry.displayValue) ?? Decimal(entry.value)
        if isErrorState {
            resetStateForNewEntry()
        }
        let formatted = format(value)
        currentInput = formatted
        shouldPreserveTypedCurrencyInput = false
        currentToken = displayString(for: formatted, useActiveCurrency: false)
        shouldResetInputOnNextDigit = true
        justEvaluated = false
        isErrorState = false
        currentErrorKey = nil
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func addToMemory() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        if let entry = memoryEntries.first {
            updateMemoryEntry(entry, value: (decimalValue(fromDisplayText: entry.displayValue) ?? Decimal(entry.value)) + currentValue)
        } else {
            insertMemoryEntry(currentValue)
        }
        completeUndoableChange(from: snapshot)
    }

    public func subtractFromMemory() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        if let entry = memoryEntries.first {
            updateMemoryEntry(entry, value: (decimalValue(fromDisplayText: entry.displayValue) ?? Decimal(entry.value)) - currentValue)
        } else {
            insertMemoryEntry(-currentValue)
        }
        completeUndoableChange(from: snapshot)
    }

    public func clearMemory(_ entry: MemoryEntry) {
        let snapshot = beginUndoableChange()
        memoryEntries.removeAll { $0.id == entry.id }
        completeUndoableChange(from: snapshot)
    }

    public func addToMemory(_ entry: MemoryEntry) {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        updateMemoryEntry(entry, value: (decimalValue(fromDisplayText: entry.displayValue) ?? Decimal(entry.value)) + currentValue)
        completeUndoableChange(from: snapshot)
    }

    public func subtractFromMemory(_ entry: MemoryEntry) {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        updateMemoryEntry(entry, value: (decimalValue(fromDisplayText: entry.displayValue) ?? Decimal(entry.value)) - currentValue)
        completeUndoableChange(from: snapshot)
    }

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        let current = makeSnapshot()
        suppressHistoryTracking = true
        apply(snapshot: snapshot)
        suppressHistoryTracking = false
        redoStack.append(current)
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        let current = makeSnapshot()
        suppressHistoryTracking = true
        apply(snapshot: snapshot)
        suppressHistoryTracking = false
        undoStack.append(current)
        trimToRecentSnapshots(&undoStack, maxCount: Limits.maxUndoDepth)
    }

    // MARK: - Private helpers

    private func groupDigits(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }

        if numberFormatStyle.usesIndianGrouping {
            let trailingGroup = String(digits.suffix(3))
            let leadingDigits = String(digits.dropLast(3))
            guard !leadingDigits.isEmpty else { return trailingGroup }

            var groupedLeading: [String] = []
            var index = leadingDigits.endIndex
            while index > leadingDigits.startIndex {
                let previous = leadingDigits.index(index, offsetBy: -2, limitedBy: leadingDigits.startIndex) ?? leadingDigits.startIndex
                groupedLeading.insert(String(leadingDigits[previous..<index]), at: 0)
                index = previous
            }

            return groupedLeading.joined(separator: numberFormatStyle.groupingSeparator)
                + numberFormatStyle.groupingSeparator
                + trailingGroup
        }

        var result = ""
        for (idx, char) in digits.reversed().enumerated() {
            if idx != 0 && idx % 3 == 0 {
                result.insert(contentsOf: numberFormatStyle.groupingSeparator, at: result.startIndex)
            }
            result.insert(char, at: result.startIndex)
        }
        return result
    }

    private func groupedNumberString(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }

        var working = raw
        var prefix = ""
        if working.hasPrefix("-") || working.hasPrefix("−") {
            prefix = "-"
            working.removeFirst()
        }

        // Only group plain numeric strings; leave errors like "Error" untouched.
        let groupingCharacters = String(numberFormatStyle.groupingSeparatorCharacters)
        let allowed = CharacterSet(charactersIn: "0123456789." + numberFormatStyle.decimalSeparator + groupingCharacters)
        guard working.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return raw
        }

        let decimalSeparator = numberFormatStyle.decimalSeparator
        let activeDecimalSeparator: Character?
        if working.contains(decimalSeparator) {
            activeDecimalSeparator = Character(decimalSeparator)
        } else if decimalSeparator != "." && working.contains(".") {
            activeDecimalSeparator = "."
        } else {
            activeDecimalSeparator = nil
        }

        let components: [Substring]
        if let activeDecimalSeparator {
            components = working.split(separator: activeDecimalSeparator, maxSplits: 1, omittingEmptySubsequences: false)
        } else {
            components = [Substring(working)]
        }

        let intPart = String(components.first ?? "").filter { $0.isNumber }
        let fracPart = components.count > 1 ? String(components[1]) : ""
        let keepTrailingDecimalSeparator = activeDecimalSeparator != nil && fracPart.isEmpty

        let groupedInt = groupDigits(intPart)
        var result = prefix + groupedInt
        if keepTrailingDecimalSeparator {
            result.append(contentsOf: decimalSeparator)
        } else if !fracPart.isEmpty {
            result.append(contentsOf: decimalSeparator)
            result.append(fracPart)
        }
        return result
    }

    private func groupedExpressionString(_ expression: String) -> String {
        guard !expression.isEmpty else { return "" }
        let tokens = expression.split(separator: " ", omittingEmptySubsequences: false)
        let grouped = tokens.map { formatExpressionTokenForDisplay(String($0)) }
        return grouped.joined(separator: " ")
    }

    private indirect enum DisplayExpressionNode {
        case value(String)
        case binary(String, DisplayExpressionNode, DisplayExpressionNode)
    }

    private func completedOperationDisplayExpression(_ expression: String) -> String {
        let groupedExpression = groupedExpressionString(expression)
        let tokens = groupedExpression.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard shouldUseStackedOperationDisplay(tokens: tokens),
              let node = buildDisplayExpressionNode(tokens: tokens) else {
            return groupedExpression
        }

        return renderDisplayExpressionNode(node, isRoot: true)
    }

    private func shouldUseStackedOperationDisplay(tokens: [String]) -> Bool {
        let operatorTokens = tokens.filter(isDisplayBinaryOperatorToken)
        let hasAdditiveOperator = operatorTokens.contains { isDisplayAdditiveOperator($0) }
        let hasMultiplicativeOperator = operatorTokens.contains { isDisplayMultiplicativeOperator($0) }
        return hasAdditiveOperator && hasMultiplicativeOperator
    }

    private func isDisplayBinaryOperatorToken(_ token: String) -> Bool {
        switch token {
        case BinaryOperator.add.symbol,
             BinaryOperator.subtract.symbol,
             BinaryOperator.multiply.symbol,
             BinaryOperator.divide.symbol,
             "×",
             "x",
             "X",
             "*",
             "÷",
             "/",
             "-",
             "−":
            return true
        default:
            return false
        }
    }

    private func isDisplayAdditiveOperator(_ token: String) -> Bool {
        token == BinaryOperator.add.symbol || token == BinaryOperator.subtract.symbol || token == "-" || token == "−"
    }

    private func isDisplayMultiplicativeOperator(_ token: String) -> Bool {
        token == BinaryOperator.multiply.symbol || token == BinaryOperator.divide.symbol || token == "×" || token == "x" || token == "X" || token == "*" || token == "÷" || token == "/"
    }

    private func buildDisplayExpressionNode(tokens: [String]) -> DisplayExpressionNode? {
        var values: [DisplayExpressionNode] = []
        var operators: [String] = []

        func precedence(for token: String) -> Int {
            switch token {
            case BinaryOperator.multiply.symbol, BinaryOperator.divide.symbol, "×", "x", "X", "*", "÷", "/":
                return 2
            case BinaryOperator.add.symbol, BinaryOperator.subtract.symbol, "-", "−":
                return 1
            default:
                return 0
            }
        }

        func applyTopOperator() -> Bool {
            guard let operatorToken = operators.popLast(),
                  let rhs = values.popLast(),
                  let lhs = values.popLast() else {
                return false
            }

            values.append(.binary(operatorToken, lhs, rhs))
            return true
        }

        for token in tokens {
            if token == "(" {
                operators.append(token)
            } else if token == ")" {
                while let last = operators.last, last != "(" {
                    guard applyTopOperator() else { return nil }
                }
                guard operators.popLast() == "(" else { return nil }
            } else if isDisplayBinaryOperatorToken(token) {
                while let last = operators.last, last != "(", precedence(for: last) >= precedence(for: token) {
                    guard applyTopOperator() else { return nil }
                }
                operators.append(token)
            } else {
                values.append(.value(token))
            }
        }

        while let last = operators.last {
            guard last != "(" else { return nil }
            guard applyTopOperator() else { return nil }
        }

        return values.count == 1 ? values[0] : nil
    }

    private func collectSignedAdditiveTerms(
        from node: DisplayExpressionNode,
        inheritedSign: Int = 1
    ) -> [(sign: Int, node: DisplayExpressionNode)] {
        guard case let .binary(operatorToken, lhs, rhs) = node,
              isDisplayAdditiveOperator(operatorToken) else {
            return [(sign: inheritedSign, node: node)]
        }

        let lhsTerms = collectSignedAdditiveTerms(from: lhs, inheritedSign: inheritedSign)
        let rhsSign = operatorToken == BinaryOperator.subtract.symbol || operatorToken == "-" || operatorToken == "−"
            ? -inheritedSign
            : inheritedSign
        let rhsTerms = collectSignedAdditiveTerms(from: rhs, inheritedSign: rhsSign)
        return lhsTerms + rhsTerms
    }

    private func renderDisplayExpressionNode(_ node: DisplayExpressionNode, isRoot: Bool) -> String {
        switch node {
        case .value(let token):
            let formattedToken = formatExpressionTokenForDisplay(token)
            if !isRoot, formattedToken.hasPrefix("-") {
                return "(\(formattedToken))"
            }
            return formattedToken
        case .binary(let operatorToken, let lhs, let rhs):
            if isDisplayAdditiveOperator(operatorToken) {
                let terms = collectSignedAdditiveTerms(from: node)
                guard let first = terms.first else { return "" }

                var combined = renderDisplayExpressionNode(first.node, isRoot: false)
                if first.sign < 0 {
                    combined = "-(\(combined))"
                }

                for term in terms.dropFirst() {
                    let renderedTerm = renderDisplayExpressionNode(term.node, isRoot: false)
                    if term.sign < 0 {
                        combined += " \(BinaryOperator.subtract.symbol) \(renderedTerm)"
                    } else {
                        combined += " \(BinaryOperator.add.symbol) \(renderedTerm)"
                    }
                }
                return isRoot ? combined : "(\(combined))"
            }

            let lhsExpression = renderDisplayExpressionNode(lhs, isRoot: false)
            let rhsExpression = renderDisplayExpressionNode(rhs, isRoot: false)
            let expression = "\(lhsExpression) \(operatorToken) \(rhsExpression)"
            return isRoot ? expression : "(\(expression))"
        }
    }

    private func enterExpressionModeIfNeeded() {
        guard !isExpressionMode else { return }
        if let seedTokens = pendingParenthesisExpressionSeedTokens,
           pendingOperator != nil,
           shouldResetInputOnNextDigit {
            isExpressionMode = true
            expressionTokens = seedTokens
            openParenthesisCount = 0
            lastOperator = nil
            lastOperand = nil
            lastOperandToken = nil
            pendingParenthesisExpressionSeedTokens = nil
            pendingOperator = nil
            accumulator = nil
            accumulatorToken = nil
            shouldResetInputOnNextDigit = true
            justEvaluated = false
            return
        }

        pendingParenthesisExpressionSeedTokens = nil
        let didHavePendingOperator = pendingOperator != nil
        let wasEnteringRightOperand = didHavePendingOperator && !shouldResetInputOnNextDigit
        let rightOperandToken = currentToken
        let pendingExpressionTokens = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        isExpressionMode = true
        expressionTokens.removeAll()
        openParenthesisCount = 0
        lastOperator = nil
        lastOperand = nil
        lastOperandToken = nil

        if didHavePendingOperator, !pendingExpressionTokens.isEmpty {
            expressionTokens = pendingExpressionTokens
            if wasEnteringRightOperand {
                if let last = expressionTokens.last, isExpressionOperatorToken(last) {
                    expressionTokens.append(rightOperandToken)
                } else if let last = expressionTokens.last, isExpressionNumberToken(last) {
                    expressionTokens[expressionTokens.count - 1] = rightOperandToken
                }
            }
        } else if let pending = pendingOperator {
            let lhs = accumulatorToken ?? currentToken
            expressionTokens.append(lhs)
            expressionTokens.append(pending.symbol)
            if wasEnteringRightOperand {
                expressionTokens.append(rightOperandToken)
            }
        } else if currentToken != "0" {
            expressionTokens.append(currentToken)
        }

        pendingOperator = nil
        accumulator = nil
        accumulatorToken = nil
        shouldResetInputOnNextDigit = !wasEnteringRightOperand
        justEvaluated = false
    }

    private func shouldInsertClosingParenthesisInExpressionMode() -> Bool {
        if !isExpressionMode { return false }
        guard openParenthesisCount > 0 else { return false }
        if !shouldResetInputOnNextDigit { return true }
        guard let last = expressionTokens.last else { return false }
        return isExpressionValueToken(last) || last == ")"
    }

    private func appendCurrentTokenToExpressionIfNeeded() {
        guard !shouldResetInputOnNextDigit else { return }
        let displayToken: String
        if currentToken.hasSuffix("%") {
            displayToken = currentToken
        } else if let normalized = normalizeDisplayNumberToken(currentToken) {
            displayToken = displayString(for: normalized)
        } else {
            return
        }

        if let last = expressionTokens.last, isExpressionNumberToken(last) {
            expressionTokens[expressionTokens.count - 1] = displayToken
        } else {
            expressionTokens.append(displayToken)
        }
    }

    private func expressionPreviewHeader() -> String {
        var previewTokens = expressionTokens
        if !shouldResetInputOnNextDigit {
            let displayToken: String
            if currentToken.hasSuffix("%") {
                displayToken = currentToken
            } else if let normalized = normalizeDisplayNumberToken(currentToken) {
                displayToken = displayString(for: normalized)
            } else {
                return previewTokens.joined(separator: " ")
            }

            if let last = previewTokens.last, isExpressionNumberToken(last) {
                previewTokens[previewTokens.count - 1] = displayToken
            } else if previewTokens.last != ")" {
                previewTokens.append(displayToken)
            }
        }
        return previewTokens.joined(separator: " ")
    }

    private func isExpressionOperatorToken(_ token: String) -> Bool {
        token == BinaryOperator.add.symbol
            || token == BinaryOperator.subtract.symbol
            || token == BinaryOperator.multiply.symbol
            || token == BinaryOperator.divide.symbol
    }

    private func operationChunkCount(in tokens: [String]) -> Int {
        tokens.reduce(into: 0) { count, token in
            if isExpressionValueToken(token) {
                count += 1
            }
        }
    }

    private func nonExpressionOperationChunkCountIncludingCurrentInput() -> Int {
        let expressionTokens = expression
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var chunkCount = operationChunkCount(in: expressionTokens)

        guard pendingOperator != nil, !shouldResetInputOnNextDigit else {
            return chunkCount
        }

        if let last = expressionTokens.last, isExpressionOperatorToken(last) {
            chunkCount += 1
        } else if chunkCount == 0 {
            chunkCount = 1
        }

        return chunkCount
    }

    private func isExpressionNumberToken(_ token: String) -> Bool {
        normalizeDisplayNumberToken(token) != nil
    }

    private func isExpressionValueToken(_ token: String) -> Bool {
        switch expressionTokenValue(token) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    private func applyCurrentUnaryTokenToExpression() {
        guard isExpressionMode else { return }
        if let last = expressionTokens.last, isExpressionValueToken(last) {
            expressionTokens[expressionTokens.count - 1] = currentToken
        } else {
            expressionTokens.append(currentToken)
        }
        shouldResetInputOnNextDigit = true
    }

    private func wrappedExpressionOperand(_ token: String, prefix: String) -> String? {
        guard token.hasPrefix(prefix), token.hasSuffix(")") else { return nil }
        let start = token.index(token.startIndex, offsetBy: prefix.count)
        let end = token.index(before: token.endIndex)
        guard start < end else { return nil }
        return String(token[start..<end])
    }

    private func expressionTokenValue(_ token: String) -> Result<Decimal, ExpressionEvaluationError> {
        expressionTokenValue(token, unaryDepth: 0)
    }

    private func expressionTokenValue(_ token: String, unaryDepth: Int) -> Result<Decimal, ExpressionEvaluationError> {
        if token.hasSuffix("%") {
            let baseToken = String(token.dropLast())
            if let normalizedBase = normalizeDisplayNumberToken(baseToken),
               let baseValue = decimalValue(fromCanonicalString: normalizedBase) {
                return .success(baseValue / 100)
            }
            return .failure(.invalidInput)
        }

        if let normalized = normalizeDisplayNumberToken(token),
           let value = decimalValue(fromCanonicalString: normalized) {
            return .success(value)
        }

        if let inner = wrappedExpressionOperand(token, prefix: "sqr(") {
            let nextDepth = unaryDepth + 1
            if nextDepth > Limits.maxConsecutiveSquareOrRootDepth { return .failure(.underflow) }
            switch expressionTokenValue(inner, unaryDepth: nextDepth) {
            case .success(let value):
                let dbl = NSDecimalNumber(decimal: value).doubleValue
                if abs(dbl) >= Self.maxFormatterMagnitude.squareRoot() { return .failure(.overflow) }
                var squared = value * value
                if value < 0 {
                    squared = -squared
                }
                if valueWouldUnderflowDisplay(squared) { return .failure(.underflow) }
                return .success(squared)
            case .failure(let error):
                return .failure(error)
            }
        }

        if let inner = wrappedExpressionOperand(token, prefix: "√(") {
            let nextDepth = unaryDepth + 1
            if nextDepth > Limits.maxConsecutiveSquareOrRootDepth { return .failure(.underflow) }
            switch expressionTokenValue(inner, unaryDepth: nextDepth) {
            case .success(let value):
                let root = sqrt(NSDecimalNumber(decimal: value).doubleValue)
                let rootDecimal = Decimal(root)
                if valueWouldUnderflowDisplay(rootDecimal) { return .failure(.underflow) }
                return .success(rootDecimal)
            case .failure(let error):
                return .failure(error)
            }
        }

        if let inner = wrappedExpressionOperand(token, prefix: "1/(") {
            let nextDepth = unaryDepth + 1
            if nextDepth > Limits.maxConsecutiveSquareOrRootDepth { return .failure(.underflow) }
            switch expressionTokenValue(inner, unaryDepth: nextDepth) {
            case .success(let value):
                if value == 0 {
                    return .failure(.divideByZero)
                }
                let reciprocal = Decimal(1) / value
                if valueWouldUnderflowDisplay(reciprocal) { return .failure(.underflow) }
                return .success(reciprocal)
            case .failure(let error):
                return .failure(error)
            }
        }

        return .failure(.invalidInput)
    }

    private func formatExpressionTokenForDisplay(_ token: String) -> String {
        if token.hasSuffix("%") {
            return token
        }

        if let normalized = normalizeDisplayNumberToken(token) {
            return displayString(for: normalized, useActiveCurrency: false)
        }

        if let inner = wrappedExpressionOperand(token, prefix: "sqr(") {
            return "\(formatExpressionTokenForDisplay(inner))²"
        }

        if let inner = wrappedExpressionOperand(token, prefix: "√(") {
            return "√(\(formatExpressionTokenForDisplay(inner)))"
        }

        if let inner = wrappedExpressionOperand(token, prefix: "1/(") {
            return "1/(\(formatExpressionTokenForDisplay(inner)))"
        }

        return token
    }

    // Evaluates a tokenized expression using the shunting-yard algorithm: two
    // stacks (values and operators) honor precedence and parentheses in a single
    // pass. Returns a typed error for divide-by-zero, overflow, etc.
    private func evaluateExpressionTokens(_ tokens: [String]) -> Result<Decimal, ExpressionEvaluationError> {
        var values: [Decimal] = []
        var operators: [String] = []

        func precedence(_ op: String) -> Int {
            switch op {
            case BinaryOperator.multiply.symbol, BinaryOperator.divide.symbol:
                return 2
            case BinaryOperator.add.symbol, BinaryOperator.subtract.symbol:
                return 1
            default:
                return 0
            }
        }

        func applyTopOperator() -> ExpressionEvaluationError? {
            guard let opToken = operators.popLast(),
                  let rhs = values.popLast(),
                  let lhs = values.popLast() else {
                return .invalidInput
            }

            let result: Decimal
            switch opToken {
            case BinaryOperator.add.symbol:
                result = lhs + rhs
            case BinaryOperator.subtract.symbol:
                result = lhs - rhs
            case BinaryOperator.multiply.symbol:
                if multiplicationWouldOverflowDisplay(lhs, rhs) { return .overflow }
                result = lhs * rhs
            case BinaryOperator.divide.symbol:
                if rhs == 0 { return .divideByZero }
                result = lhs / rhs
            default:
                return .invalidInput
            }
            if valueWouldUnderflowDisplay(result) { return .underflow }
            values.append(result)
            return nil
        }

        for token in tokens {
            if token == "(" {
                operators.append(token)
                continue
            }

            if token == ")" {
                while let top = operators.last, top != "(" {
                    if let error = applyTopOperator() { return .failure(error) }
                }
                guard operators.last == "(" else { return .failure(.invalidInput) }
                operators.removeLast()
                continue
            }

            if isExpressionOperatorToken(token) {
                while let top = operators.last,
                      isExpressionOperatorToken(top),
                      precedence(top) >= precedence(token) {
                    if let error = applyTopOperator() { return .failure(error) }
                }
                operators.append(token)
                continue
            }

            switch expressionTokenValue(token) {
            case .success(let value):
                values.append(value)
            case .failure(let error):
                return .failure(error)
            }
        }

        while let top = operators.last {
            if top == "(" { return .failure(.invalidInput) }
            if let error = applyTopOperator() { return .failure(error) }
        }

        guard values.count == 1, let result = values.first else {
            return .failure(.invalidInput)
        }
        return .success(result)
    }

    // Applies the single pending binary operator to accumulator/current operand.
    // With addToHistory it finalizes the calculation (records history, clears
    // pending); without it the result becomes the new accumulator for chaining.
    private func performPendingOperation(addToHistory: Bool, refreshDisplay: Bool = true) {
        guard let pending = pendingOperator else { return }
        let lhs = accumulator ?? currentValue
        let rhs = currentValue
        let lhsToken = accumulatorToken ?? currentToken
        let rhsToken = currentToken
        if pending == .divide && rhs == 0 {
            setError("error.divideByZero")
            return
        }
        if pending == .multiply, multiplicationWouldOverflowDisplay(lhs, rhs) {
            setError("error.outOfRange")
            return
        }
        let result = pending.apply(lhs, rhs)
        if valueWouldUnderflowDisplay(result) {
            setError("error.outOfRange")
            return
        }
        let resultText = format(result)
        let percentResultToken = operationYieldsPercentResult(pending: pending, lhsToken: lhsToken, rhsToken: rhsToken)
            ? percentTokenString(forStoredValue: result)
            : nil

        if addToHistory {
            let exp = completedPendingExpression(lhsToken: lhsToken, pending: pending, rhsToken: rhsToken)
            appendHistory(expression: exp, result: resultText, displayResultOverride: percentResultToken)
            lastResultSummary = exp + " ="
            expression = ""
            pendingOperator = nil
            lastOperator = pending
            lastOperand = rhs
            lastOperandToken = rhsToken
            justEvaluated = true
            shouldResetInputOnNextDigit = true
        } else {
            accumulator = result
            accumulatorToken = displayString(for: resultText, useActiveCurrency: false)
            currentToken = accumulatorToken ?? displayString(for: resultText, useActiveCurrency: false)
            expression = "\(accumulatorToken ?? displayString(for: resultText, useActiveCurrency: false)) \(pending.symbol)"
            lastOperator = nil
            lastOperand = nil
            shouldResetInputOnNextDigit = true
            justEvaluated = false
        }

        currentInput = resultText
        accumulator = result
        // The percent form is a display token only: `currentInput` keeps the
        // decimal so anything calculated from this result stays correct.
        accumulatorToken = percentResultToken ?? displayString(for: resultText, useActiveCurrency: false)
        currentToken = accumulatorToken ?? displayString(for: resultText, useActiveCurrency: false)
        resultUsesPercentToken = percentResultToken != nil
        if refreshDisplay {
            updateDisplay()
        }
    }

    private func appendHistory(
        expression: String,
        result: String,
        displayExpressionOverride: String? = nil,
        displayResultOverride: String? = nil
    ) {
        let historyExpression: String
        let historyResult: String
        let displayResult: String
        let displayExpression: String
        if isResultRoundingEnabled {
            let roundedResult = roundedDisplayString(fromStoredNumber: result, precision: resultRoundingPrecision)
            let relationSymbol = roundingRelationSymbol(fromStoredNumber: result, precision: resultRoundingPrecision)
            if relationSymbol == "≈" {
                historyExpression = "round(\(expression)\(numberFormatStyle.spreadsheetArgumentSeparator) \(resultRoundingPrecision)) ≈"
            } else {
                historyExpression = "round(\(expression)\(numberFormatStyle.spreadsheetArgumentSeparator) \(resultRoundingPrecision))"
            }
            historyResult = roundedResult
            displayResult = roundedResult
            displayExpression = roundedOperationDisplayString(
                baseExpression: expression,
                sourceValue: result,
                precision: resultRoundingPrecision,
                relationSymbol: relationSymbol
            )
        } else {
            historyExpression = expression
            historyResult = storedHistoryResultString(from: result)
            displayResult = displayResultOverride ?? displayString(for: historyResult, useActiveCurrency: false)
            displayExpression = displayExpressionOverride ?? completedOperationDisplayExpression(expression)
        }

        completedCalculationCount += 1

        let boundedExpression = String(historyExpression.prefix(Limits.maxHistoryExpressionCharacters))
        let boundedResult = String(historyResult.prefix(Limits.maxHistoryResultCharacters))
        let boundedDisplayExpression = String(displayExpression.prefix(Limits.maxHistoryExpressionCharacters))
        history.insert(
            HistoryEntry(
                expression: boundedExpression,
                result: boundedResult,
                displayExpression: boundedDisplayExpression,
                displayResult: displayResult
            ),
            at: 0
        )
        trimToNewestEntries(&history, maxCount: Limits.maxStoredHistoryEntries)
    }

    private func multiplicationWouldOverflowDisplay(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        let lhsDbl = NSDecimalNumber(decimal: lhs).doubleValue
        let rhsDbl = NSDecimalNumber(decimal: rhs).doubleValue

        guard lhsDbl.isFinite, rhsDbl.isFinite else { return true }
        guard lhsDbl != 0, rhsDbl != 0 else { return false }

        return abs(lhsDbl) >= Self.maxFormatterMagnitude / abs(rhsDbl)
    }

    private func valueWouldUnderflowDisplay(_ value: Decimal) -> Bool {
        if value.isNaN { return true }
        guard value != 0 else { return false }

        let rendered = formatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalNumberString(from: value)
        return rendered == "0" || rendered == "-0"
    }

    private func nextUnaryChainDepth(for token: String) -> Int {
        unaryChainDepth(of: token) + 1
    }

    private func unaryChainDepth(of token: String) -> Int {
        if let inner = wrappedExpressionOperand(token, prefix: "sqr(") {
            return unaryChainDepth(of: inner) + 1
        }

        if let inner = wrappedExpressionOperand(token, prefix: "√(") {
            return unaryChainDepth(of: inner) + 1
        }

        if let inner = wrappedExpressionOperand(token, prefix: "1/(") {
            return unaryChainDepth(of: inner) + 1
        }

        return 0
    }

    private func insertMemoryEntry(_ value: Decimal) {
        let formattedValue = format(value)
        memoryEntries.insert(
            MemoryEntry(value: NSDecimalNumber(decimal: value).doubleValue, displayValue: displayString(for: formattedValue)),
            at: 0
        )
        trimToNewestEntries(&memoryEntries, maxCount: Limits.maxStoredMemoryEntries)
    }

    private func updateMemoryEntry(_ entry: MemoryEntry, value: Decimal) {
        guard let index = memoryEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        let formattedValue = format(value)
        memoryEntries[index] = MemoryEntry(
            id: entry.id,
            value: NSDecimalNumber(decimal: value).doubleValue,
            displayValue: displayString(for: formattedValue)
        )
    }

    private func beginUndoableChange() -> CalculatorSnapshot? {
        guard !suppressHistoryTracking else { return nil }
        return makeSnapshot()
    }

    private func completeUndoableChange(from snapshot: CalculatorSnapshot?) {
        guard let snapshot, !suppressHistoryTracking else { return }
        let current = makeSnapshot()
        guard current != snapshot else { return }
        undoStack.append(snapshot)
        trimToRecentSnapshots(&undoStack, maxCount: Limits.maxUndoDepth)
        redoStack.removeAll()
    }

    private func makeSnapshot() -> CalculatorSnapshot {
        CalculatorSnapshot(
            display: display,
            expressionDisplay: expressionDisplay,
            expression: expression,
            history: history,
            lastResultSummary: lastResultSummary,
            memoryEntries: memoryEntries,
            isErrorState: isErrorState,
            currentErrorKey: currentErrorKey,
            currentInput: currentInput,
            accumulator: accumulator,
            pendingOperator: pendingOperator,
            lastOperator: lastOperator,
            lastOperand: lastOperand,
            shouldResetInputOnNextDigit: shouldResetInputOnNextDigit,
            justEvaluated: justEvaluated,
            currentToken: currentToken,
            accumulatorToken: accumulatorToken,
            lastOperandToken: lastOperandToken,
            expressionTokens: expressionTokens,
            openParenthesisCount: openParenthesisCount,
            isExpressionMode: isExpressionMode,
            isResultRoundingEnabled: isResultRoundingEnabled,
            resultRoundingPrecision: resultRoundingPrecision,
            activeCurrencySymbol: activeCurrencySymbol,
            isPendingEntryClearedByClearButton: isPendingEntryClearedByClearButton,
            shouldPreserveTypedCurrencyInput: shouldPreserveTypedCurrencyInput,
            resultUsesPercentToken: resultUsesPercentToken,
            displayEditCursorIndex: displayEditCursorIndex
        )
    }

    private func apply(snapshot: CalculatorSnapshot) {
        display = snapshot.display
        expressionDisplay = snapshot.expressionDisplay
        expression = snapshot.expression
        history = snapshot.history
        lastResultSummary = snapshot.lastResultSummary
        memoryEntries = snapshot.memoryEntries
        isErrorState = snapshot.isErrorState
        currentErrorKey = snapshot.currentErrorKey
        currentInput = snapshot.currentInput
        accumulator = snapshot.accumulator
        pendingOperator = snapshot.pendingOperator
        lastOperator = snapshot.lastOperator
        lastOperand = snapshot.lastOperand
        shouldResetInputOnNextDigit = snapshot.shouldResetInputOnNextDigit
        justEvaluated = snapshot.justEvaluated
        currentToken = snapshot.currentToken
        accumulatorToken = snapshot.accumulatorToken
        lastOperandToken = snapshot.lastOperandToken
        expressionTokens = snapshot.expressionTokens
        openParenthesisCount = snapshot.openParenthesisCount
        isExpressionMode = snapshot.isExpressionMode
        isResultRoundingEnabled = snapshot.isResultRoundingEnabled
        resultRoundingPrecision = snapshot.resultRoundingPrecision
        activeCurrencySymbol = snapshot.activeCurrencySymbol
        isPendingEntryClearedByClearButton = snapshot.isPendingEntryClearedByClearButton
        shouldPreserveTypedCurrencyInput = snapshot.shouldPreserveTypedCurrencyInput
        resultUsesPercentToken = snapshot.resultUsesPercentToken
        displayEditCursorIndex = snapshot.displayEditCursorIndex
        trimToNewestEntries(&history, maxCount: Limits.maxStoredHistoryEntries)
        trimToNewestEntries(&memoryEntries, maxCount: Limits.maxStoredMemoryEntries)
        trimToRecentSnapshots(&undoStack, maxCount: Limits.maxUndoDepth)
        trimToRecentSnapshots(&redoStack, maxCount: Limits.maxRedoDepth)
    }

    private func currentOperationCopyString() -> String? {
        if isResultRoundingEnabled {
            let roundedOperation = expressionDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
            let compactOperation = compactRoundedOperationCopyString(roundedOperation)
            return compactOperation.isEmpty ? nil : compactOperation
        }

        let currentExpression = expressionDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentResult = display.trimmingCharacters(in: .whitespacesAndNewlines)

        if !currentExpression.isEmpty, !currentResult.isEmpty {
            if currentExpression.hasSuffix("=") {
                return "\(currentExpression) \(currentResult)"
            }
            return "\(currentExpression) = \(currentResult)"
        }

        let previousExpression = lastResultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousExpression.isEmpty, !currentResult.isEmpty else { return nil }
        return "\(previousExpression) \(currentResult)"
    }

    private func operationCopyString(expression: String, result: String) -> String {
        if expression.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=round(") {
            return compactRoundedOperationCopyString(expression)
        }
        if expression.contains("≈") {
            if expression.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("≈") {
                return "\(expression) \(result)"
            }
            return expression
        }
        return "\(expression) = \(result)"
    }

    private func compactRoundedOperationCopyString(_ expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutApproximation: String
        if trimmed.hasSuffix("≈") {
            withoutApproximation = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            withoutApproximation = trimmed
        }

        return withoutApproximation.filter {
            !$0.isWhitespace && !Self.supportedCurrencySymbolCharacters.contains($0)
        }
    }

    private func writeStringToPasteboard(_ string: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    private func applyPasteReplayStep(_ step: PasteReplayStep) {
        switch step {
        case .digit(let digit):
            inputDigit(digit)
        case .decimal:
            inputDecimal()
        case .toggleSign:
            toggleSign()
        case .applyPercent:
            applyPercent()
        case .reciprocal:
            reciprocal()
        case .square:
            square()
        case .squareRoot:
            squareRoot()
        case .setOperator(let op):
            setOperator(op)
        case .evaluate:
            evaluate()
        }
    }

    private func adoptPastedState(from other: CalculatorViewModel) {
        currentInput = other.currentInput
        accumulator = other.accumulator
        pendingOperator = other.pendingOperator
        lastOperator = other.lastOperator
        lastOperand = other.lastOperand
        shouldResetInputOnNextDigit = other.shouldResetInputOnNextDigit
        justEvaluated = other.justEvaluated
        currentErrorKey = other.currentErrorKey
        currentToken = other.currentToken
        accumulatorToken = other.accumulatorToken
        lastOperandToken = other.lastOperandToken
        display = other.display
        expressionDisplay = other.expressionDisplay
        expression = other.expression
        lastResultSummary = other.lastResultSummary
        isErrorState = other.isErrorState
        expressionTokens = other.expressionTokens
        openParenthesisCount = other.openParenthesisCount
        isExpressionMode = other.isExpressionMode
        isResultRoundingEnabled = other.isResultRoundingEnabled
        resultRoundingPrecision = other.resultRoundingPrecision
        activeCurrencySymbol = other.activeCurrencySymbol
        isPendingEntryClearedByClearButton = other.isPendingEntryClearedByClearButton
        shouldPreserveTypedCurrencyInput = other.shouldPreserveTypedCurrencyInput
    }

    private func makeExpressionPreview() -> String {
        guard let op = pendingOperator else { return "" }
        let lhsText = accumulatorToken ?? currentToken
        return "\(lhsText) \(op.symbol)"
    }

    private func completedPendingExpression(lhsToken: String, pending: BinaryOperator, rhsToken: String) -> String {
        let pendingExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingExpression.isEmpty else {
            return "\(lhsToken) \(pending.symbol) \(rhsToken)"
        }

        if pendingExpression.hasSuffix(pending.symbol) {
            return "\(pendingExpression) \(rhsToken)"
        }

        return pendingExpression
    }

    private func chainedExpressionPreview(
        existingExpression: String,
        lhsToken: String,
        completedOperator: BinaryOperator,
        rhsToken: String,
        nextOperator: BinaryOperator,
        shouldGroupCompletedExpression: Bool
    ) -> String {
        let trimmedExpression = existingExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        let completedExpression: String
        if trimmedExpression.isEmpty {
            completedExpression = "\(lhsToken) \(completedOperator.symbol) \(rhsToken)"
        } else if trimmedExpression.hasSuffix(completedOperator.symbol) {
            completedExpression = "\(trimmedExpression) \(rhsToken)"
        } else {
            completedExpression = trimmedExpression
        }

        let groupedCompletedExpression: String
        if shouldGroupCompletedExpression,
           !(completedExpression.hasPrefix("(") && completedExpression.hasSuffix(")")) {
            groupedCompletedExpression = "( \(completedExpression) )"
        } else {
            groupedCompletedExpression = completedExpression
        }

        return "\(groupedCompletedExpression) \(nextOperator.symbol)"
    }

    private var isStandaloneUnaryResult: Bool {
        guard pendingOperator == nil,
              !isExpressionMode,
              !isErrorState else {
            return false
        }
        return currentToken.hasPrefix("sqr(") || currentToken.hasPrefix("√(") || currentToken.hasPrefix("1/(")
    }

    private var isResultStateUsingAllClear: Bool {
        justEvaluated && pendingOperator == nil && !isExpressionMode
    }

    private var isInClearAllState: Bool {
        currentInput == "0"
            && currentToken == "0"
            && accumulator == nil
            && pendingOperator == nil
            && lastOperator == nil
            && lastOperand == nil
            && accumulatorToken == nil
            && lastOperandToken == nil
            && expression.isEmpty
            && lastResultSummary.isEmpty
            && expressionTokens.isEmpty
            && openParenthesisCount == 0
            && !isExpressionMode
            && !justEvaluated
            && !isPendingEntryClearedByClearButton
            && !isStandaloneUnaryResult
    }

    private var shouldUseAllClearBehavior: Bool {
        isPendingEntryClearedByClearButton || isStandaloneUnaryResult || isErrorState || isResultStateUsingAllClear || isInClearAllState
    }

    @discardableResult
    private func removeActiveExpressionValueTokenIfNeeded() -> Bool {
        guard isExpressionMode,
              !shouldResetInputOnNextDigit,
              let last = expressionTokens.last,
              isExpressionNumberToken(last) else {
            return false
        }

        expressionTokens.removeLast()
        if expressionTokens.isEmpty {
            resetAllStateForClearAll()
        } else {
            currentInput = "0"
            currentToken = "0"
            shouldResetInputOnNextDigit = true
            isPendingEntryClearedByClearButton = true
            justEvaluated = false
            isErrorState = false
            currentErrorKey = nil
        }

        return true
    }

    @discardableResult
    private func backspaceExpressionTokenIfNeeded() -> Bool {
        guard isExpressionMode, shouldResetInputOnNextDigit else {
            return false
        }

        if let removed = expressionTokens.popLast() {
            if removed == "(" {
                openParenthesisCount = max(0, openParenthesisCount - 1)
            } else if removed == ")" {
                openParenthesisCount += 1
            }
            if expressionTokens.isEmpty {
                resetAllStateForClearAll()
            } else if let last = expressionTokens.last,
                      isExpressionNumberToken(last),
                      let normalized = normalizeDisplayNumberToken(last) {
                currentInput = normalized
                currentToken = last
                shouldResetInputOnNextDigit = false
                isPendingEntryClearedByClearButton = false

                if expressionTokens.count == 1, openParenthesisCount == 0 {
                    expressionTokens.removeAll()
                    isExpressionMode = false
                    expression = ""
                }
            }
        } else {
            resetAllStateForClearAll()
        }

        return true
    }

    private func setBlankPendingEntryState() {
        currentInput = "0"
        currentToken = "0"
        shouldResetInputOnNextDigit = true
        isPendingEntryClearedByClearButton = true
    }

    private func clearParenthesizedExpressionIfNeeded() -> Bool {
        guard isExpressionMode,
              let openIndex = expressionTokens.lastIndex(of: "(") else {
            return false
        }

        let prefix = Array(expressionTokens[..<openIndex])
        if prefix.isEmpty {
            currentInput = "0"
            accumulator = nil
            pendingOperator = nil
            lastOperator = nil
            lastOperand = nil
            lastResultSummary = ""
            expression = ""
            shouldResetInputOnNextDigit = false
            justEvaluated = false
            isErrorState = false
            currentErrorKey = nil
            accumulatorToken = nil
            currentToken = "0"
            lastOperandToken = nil
            expressionTokens.removeAll()
            openParenthesisCount = 0
            isExpressionMode = false
            isPendingEntryClearedByClearButton = false
            isResultRoundingEnabled = false
            resultRoundingPrecision = 4
            return true
        }

        expressionTokens = prefix
        openParenthesisCount = expressionTokens.reduce(into: 0) { count, token in
            if token == "(" {
                count += 1
            } else if token == ")" {
                count = max(0, count - 1)
            }
        }
        isExpressionMode = true
        currentInput = "0"
        currentToken = "0"
        shouldResetInputOnNextDigit = true
        justEvaluated = false
        isPendingEntryClearedByClearButton = true
        isErrorState = false
        currentErrorKey = nil
        return true
    }

    private func updateDisplay() {
        if shouldDisplayPercentTokenAsMainDisplay {
            let header: String
            if isExpressionMode {
                header = expressionPreviewHeader()
                expression = header
            } else if let op = pendingOperator {
                let pendingExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pendingExpression.isEmpty {
                    if shouldResetInputOnNextDigit {
                        header = pendingExpression
                    } else if pendingExpression.hasSuffix(op.symbol) {
                        header = "\(pendingExpression) \(currentToken)"
                    } else {
                        header = pendingExpression
                    }
                } else {
                    let lhsText = accumulatorToken ?? currentToken
                    let rhsText = shouldResetInputOnNextDigit ? nil : currentToken
                    if let rhsText {
                        header = "\(lhsText) \(op.symbol) \(rhsText)"
                    } else {
                        header = "\(lhsText) \(op.symbol)"
                    }
                }
            } else if !expression.isEmpty {
                header = expression
            } else {
                header = lastResultSummary
            }

            display = currentToken
            expressionDisplay = groupedExpressionString(header)
            displayEditCursorIndex = nil
            return
        }

        let shouldUseCurrencyForCurrentDisplay = !(activeCurrencySymbol != nil && currentToken.hasSuffix("%"))
        let plainDisplay = isPendingEntryClearedByClearButton && currentInput == "0"
            ? ""
            : displayString(
                for: currentInput,
                useActiveCurrency: shouldUseCurrencyForCurrentDisplay,
                preserveTrailingZeros: shouldPreserveTypedCurrencyInput
            )
        let header: String
        if isExpressionMode {
            header = expressionPreviewHeader()
            expression = header
        } else if let op = pendingOperator {
            let pendingExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pendingExpression.isEmpty {
                if shouldResetInputOnNextDigit {
                    header = pendingExpression
                } else if pendingExpression.hasSuffix(op.symbol) {
                    header = "\(pendingExpression) \(currentToken)"
                } else {
                    header = pendingExpression
                }
            } else {
                let lhsText = accumulatorToken ?? currentToken
                let rhsText = shouldResetInputOnNextDigit ? nil : currentToken
                if let rhsText {
                    header = "\(lhsText) \(op.symbol) \(rhsText)"
                } else {
                    header = "\(lhsText) \(op.symbol)"
                }
            }
        } else if !expression.isEmpty {
            header = expression
        } else {
            header = lastResultSummary
        }

        guard isResultRoundingEnabled, !isErrorState else {
            display = plainDisplay
            expressionDisplay = groupedExpressionString(header)
            if canDirectlyEditDisplay {
                if let displayEditCursorIndex {
                    self.displayEditCursorIndex = min(max(displayEditCursorIndex, 0), currentInput.count)
                }
            } else {
                displayEditCursorIndex = nil
            }
            return
        }

        // When the user is actively typing the right-hand operand of a pending binary
        // operation, do not prematurely apply rounding to the display (bug: "0.0999999999"
        // was collapsed to "0.1"). Also anchor the operation-display scale to the
        // accumulated LHS value so it does not drift as more digits are typed (bug:
        // scale changed from 4 to 8 with further input).
        let isTypingRHS = !isExpressionMode && pendingOperator != nil && !shouldResetInputOnNextDigit
        if isTypingRHS {
            display = plainDisplay
        } else {
            display = roundedDisplayString(fromStoredNumber: currentInput, precision: resultRoundingPrecision)
        }
        let baseExpression = baseExpressionForRounding(from: header)
        let roundingSourceValue: String
        if isTypingRHS, let acc = accumulator {
            roundingSourceValue = decimalNumberString(from: acc)
        } else {
            roundingSourceValue = currentInput
        }
        let relationSymbol = roundingRelationSymbol(fromStoredNumber: roundingSourceValue, precision: resultRoundingPrecision)
        expressionDisplay = roundedOperationDisplayString(
            baseExpression: baseExpression,
            sourceValue: roundingSourceValue,
            precision: resultRoundingPrecision,
            relationSymbol: relationSymbol
        )

        if canDirectlyEditDisplay {
            if let displayEditCursorIndex {
                self.displayEditCursorIndex = min(max(displayEditCursorIndex, 0), currentInput.count)
            }
        } else {
            displayEditCursorIndex = nil
        }
    }

    /// Attempt to extract a numeric string from pasted content, preferring the active style and
    /// falling back to other supported styles when the pasted format differs.
    private func normalizePastedNumber(_ raw: String) -> String? {
        return normalizeNumberString(raw, treatPercentAsMultiplier: true)
            ?? normalizeNumberStringUsingAnyStyle(raw, treatPercentAsMultiplier: true, excluding: numberFormatStyle)
    }

    private func parsePastedContent(_ raw: String) -> ParsedPasteContent {
        guard raw.count <= Limits.maxPasteCharacters else {
            return .value("", currencySymbol: nil)
        }
        let currencySymbol = explicitCurrencySymbol(in: raw)
        let normalizedRaw = raw.replacingOccurrences(of: "≈", with: "=")
        if let rounded = parseRoundedOperation(normalizedRaw),
           let steps = parseReplaySteps(rounded.baseExpression) {
            return .roundedReplay(steps: steps + [.evaluate], precision: rounded.precision, currencySymbol: currencySymbol)
        }

        let parts = normalizedRaw.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let lhs = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if let steps = parseReplaySteps(lhs) {
                return .replay(steps + [.evaluate], currencySymbol: currencySymbol)
            }

            let rhs = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return .value(rhs.isEmpty ? lhs : rhs, currencySymbol: currencySymbol)
        }

        if containsReplaySyntax(normalizedRaw), let steps = parseReplaySteps(normalizedRaw) {
            return .replay(steps, currencySymbol: currencySymbol)
        }

        return .value(normalizedRaw, currencySymbol: currencySymbol)
    }

    private func containsReplaySyntax(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var working = trimmed
        if working.hasPrefix("+") || working.hasPrefix("-") || working.hasPrefix("−") {
            working.removeFirst()
        }

        let replayCharacters = CharacterSet(charactersIn: "+−×xX*÷/()≈=")
        if working.unicodeScalars.contains(where: { replayCharacters.contains($0) }) {
            return true
        }

        return working.localizedCaseInsensitiveContains("sqr") || working.contains("√")
    }

    private func parseReplaySteps(_ raw: String) -> [PasteReplayStep]? {
        var index = raw.startIndex
        skipWhitespace(in: raw, index: &index)

        guard let firstOperand = parseOperandSteps(raw, index: &index, depth: 0) else { return nil }
        var steps = firstOperand

        while true {
            skipWhitespace(in: raw, index: &index)
            guard index < raw.endIndex else { break }
            guard let op = parseBinaryOperator(raw, index: &index) else { return nil }
            skipWhitespace(in: raw, index: &index)
            guard let operandSteps = parseOperandSteps(raw, index: &index, depth: 0) else { return nil }
            steps.append(.setOperator(op))
            steps.append(contentsOf: operandSteps)
            guard steps.count <= Limits.maxPasteReplaySteps else { return nil }
        }

        return steps
    }

    private func parseOperandSteps(_ raw: String, index: inout String.Index, depth: Int) -> [PasteReplayStep]? {
        skipWhitespace(in: raw, index: &index)
        guard index < raw.endIndex else { return nil }
        guard depth <= Limits.maxPasteNestingDepth else { return nil }

        var steps: [PasteReplayStep]

        if raw[index...].hasPrefix("sqr(") {
            index = raw.index(index, offsetBy: 4)
            guard let inner = parseOperandSteps(raw, index: &index, depth: depth + 1) else { return nil }
            guard consumeCharacter(")", in: raw, index: &index) else { return nil }
            steps = inner + [.square]
        } else if raw[index...].hasPrefix("√(") {
            index = raw.index(index, offsetBy: 2)
            guard let inner = parseOperandSteps(raw, index: &index, depth: depth + 1) else { return nil }
            guard consumeCharacter(")", in: raw, index: &index) else { return nil }
            steps = inner + [.squareRoot]
        } else if raw[index...].hasPrefix("1/(") {
            index = raw.index(index, offsetBy: 3)
            guard let inner = parseOperandSteps(raw, index: &index, depth: depth + 1) else { return nil }
            guard consumeCharacter(")", in: raw, index: &index) else { return nil }
            steps = inner + [.reciprocal]
        } else if consumeCharacter("(", in: raw, index: &index) {
            guard let inner = parseOperandSteps(raw, index: &index, depth: depth + 1) else { return nil }
            guard consumeCharacter(")", in: raw, index: &index) else { return nil }
            steps = inner
        } else {
            guard let numberSteps = parseNumberSteps(raw, index: &index) else { return nil }
            steps = numberSteps
        }

        while true {
            skipWhitespace(in: raw, index: &index)
            guard consumeCharacter("%", in: raw, index: &index) else { break }
            steps.append(.applyPercent)
            guard steps.count <= Limits.maxPasteReplaySteps else { return nil }
        }

        return steps
    }

    private func parseNumberSteps(_ raw: String, index: inout String.Index) -> [PasteReplayStep]? {
        skipWhitespace(in: raw, index: &index)
        guard index < raw.endIndex else { return nil }

        let start = index
        var hasDigits = false

        if raw[index] == "+" {
            index = raw.index(after: index)
        } else if raw[index] == "-" || raw[index] == "−" {
            index = raw.index(after: index)
        }

        while index < raw.endIndex,
              Self.supportedCurrencySymbolCharacters.contains(raw[index]),
              raw[index] != "¢" {
            index = raw.index(after: index)
        }

        while index < raw.endIndex {
            let character = raw[index]
            if character.isNumber {
                hasDigits = true
                index = raw.index(after: index)
            } else if character == "." || character == "," || character == "'" || character.isWhitespace {
                index = raw.index(after: index)
            } else if character == "¢" {
                index = raw.index(after: index)
                break
            } else {
                break
            }
        }

        guard hasDigits else {
            index = start
            return nil
        }

        let token = String(raw[start..<index])
          guard let normalized = normalizePastedNumber(token),
              let value = decimalValue(fromCanonicalString: normalized) else {
            index = start
            return nil
        }

        let formatted = format(value)
        var steps: [PasteReplayStep] = []
        var unsignedFormatted = formatted
        let isNegative = unsignedFormatted.hasPrefix("-")
        if isNegative {
            unsignedFormatted.removeFirst()
        }

        let decimalSeparator = numberFormatStyle.decimalSeparator.first
        let groupingSeparators = numberFormatStyle.groupingSeparatorCharacters

        for character in unsignedFormatted {
            if let decimalSeparator, character == decimalSeparator {
                steps.append(.decimal)
            } else if groupingSeparators.contains(character) {
                continue
            } else {
                steps.append(.digit(String(character)))
            }
        }

        if isNegative && unsignedFormatted != "0" {
            steps.append(.toggleSign)
        }

        return steps
    }

    private func parseBinaryOperator(_ raw: String, index: inout String.Index) -> BinaryOperator? {
        skipWhitespace(in: raw, index: &index)
        guard index < raw.endIndex else { return nil }

        let op: BinaryOperator?
        switch raw[index] {
        case "+": op = .add
        case "-", "−": op = .subtract
        case "×", "x", "X", "*": op = .multiply
        case "÷", "/": op = .divide
        default: op = nil
        }

        if op != nil {
            index = raw.index(after: index)
        }

        return op
    }

    private func consumeCharacter(_ character: Character, in raw: String, index: inout String.Index) -> Bool {
        skipWhitespace(in: raw, index: &index)
        guard index < raw.endIndex, raw[index] == character else { return false }
        index = raw.index(after: index)
        return true
    }

    private func skipWhitespace(in raw: String, index: inout String.Index) {
        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
    }

    private func format(_ value: Decimal) -> String {
        if value == 0 { return "0" }
        let roundedDecimal = formatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalNumberString(from: value)
        if shouldUseScientificNotation(for: roundedDecimal) {
            return scientificString(fromRoundedDecimal: roundedDecimal)
        }
        return groupedNumberString(roundedDecimal)
    }

    private func format(_ value: Double) -> String {
        if value.isNaN { return "Error" }
        if value.isInfinite { return "∞" }
        if abs(value) < pow(10, Double(-Limits.maxInputDigits)) { return "0" }
        let roundedDecimal = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        if shouldUseScientificNotation(for: roundedDecimal) {
            return scientificString(fromRoundedDecimal: roundedDecimal)
        }
        return groupedNumberString(roundedDecimal)
    }

    private func resetStateForNewEntry() {
        accumulator = nil
        pendingOperator = nil
        lastOperator = nil
        lastOperand = nil
        lastResultSummary = ""
        expression = ""
        currentInput = "0"
        currentToken = "0"
        resultUsesPercentToken = false
        shouldResetInputOnNextDigit = false
        justEvaluated = false
        isErrorState = false
        currentErrorKey = nil
        accumulatorToken = nil
        lastOperandToken = nil
        expressionTokens.removeAll()
        openParenthesisCount = 0
        isExpressionMode = false
        isPendingEntryClearedByClearButton = false
        shouldPreserveTypedCurrencyInput = false
    }

    private func setError(_ messageKey: String) {
        let message = localized(messageKey)
        currentInput = message
        display = message
        expressionDisplay = ""
        expression = ""
        accumulator = nil
        pendingOperator = nil
        lastOperator = nil
        lastOperand = nil
        lastResultSummary = ""
        shouldResetInputOnNextDigit = false
        justEvaluated = false
        isErrorState = true
        currentErrorKey = messageKey
        currentToken = message
        accumulatorToken = nil
        lastOperandToken = nil
        expressionTokens.removeAll()
        openParenthesisCount = 0
        isExpressionMode = false
        isPendingEntryClearedByClearButton = false
        shouldPreserveTypedCurrencyInput = false
    }

    private func setCurrentTokenToCurrentInput() {
        let formatted = displayString(
            for: currentInput,
            useActiveCurrency: false,
            preserveTrailingZeros: shouldPreserveTypedCurrencyInput
        )
        currentToken = boundedDisplayToken(formatted, fallback: formatted)

        // When a binary operator is armed but no RHS entry has started yet, the
        // visible display is still the stored left operand. Keep that pending
        // operand in sync so preview and evaluation use the edited value.
        if pendingOperator != nil, shouldResetInputOnNextDigit {
            accumulator = currentValue
            accumulatorToken = currentToken
            if shouldRefreshPendingExpressionPreview {
                expression = makeExpressionPreview()
            }
        }
    }

    private var shouldRefreshPendingExpressionPreview: Bool {
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedExpression.isEmpty {
            return true
        }

        let operatorTokenCount = trimmedExpression
            .split(separator: " ", omittingEmptySubsequences: true)
            .filter { token in
                token == BinaryOperator.add.symbol
                    || token == BinaryOperator.subtract.symbol
                    || token == BinaryOperator.multiply.symbol
                    || token == BinaryOperator.divide.symbol
            }
            .count

        // Preserve already-built chains when token formatting changes (for example,
        // after switching to a currency symbol mid-expression).
        return operatorTokenCount <= 1
    }

    private func resetPostEvaluateStateForDirectDisplayEditingIfNeeded() {
        guard justEvaluated else { return }

        // Editing a previously evaluated result creates a fresh input state,
        // so stale operation summary/repeat-equals metadata must be cleared.
        accumulator = nil
        accumulatorToken = nil
        lastOperator = nil
        lastOperand = nil
        lastOperandToken = nil
        lastResultSummary = ""
        expression = ""
        justEvaluated = false
        shouldResetInputOnNextDigit = false
    }

    public func refreshLocalization() {
        if let key = currentErrorKey {
            let message = localized(key)
            currentInput = message
            display = message
            expressionDisplay = ""
        }
    }

    public func setScientificNotationEnabled(_ enabled: Bool) {
        guard usesScientificNotation != enabled else { return }
        usesScientificNotation = enabled
        refreshFormattedState()
    }

    public func setNumberFormatStyle(_ style: NumberFormatStyle) {
        guard numberFormatStyle != style else { return }
        let preservedCurrentInput = parseStoredNumber(currentInput)
        numberFormatStyle = style
        if let preservedCurrentInput {
            currentInput = format(preservedCurrentInput)
        }
        shouldPreserveTypedCurrencyInput = false
        refreshFormattedState()
    }

    private var currentInputDigitCount: Int {
        significantDigitCount(in: currentInput)
    }

    private var activeDisplayEditCursorIndex: Int? {
        guard canDirectlyEditDisplay, let displayEditCursorIndex else { return nil }
        return normalizedDisplayEditCursorIndex(displayEditCursorIndex)
    }

    private func normalizedDisplayEditCursorIndex(_ rawIndex: Int) -> Int {
        let clamped = min(max(rawIndex, 0), currentInput.count)
        if currentInput.hasPrefix("-") {
            return max(1, clamped)
        }
        return clamped
    }

    private func finishDirectDisplayEditingIfNeeded() {
        guard activeDisplayEditCursorIndex != nil else { return }
        displayEditCursorIndex = nil
    }

    private func prepareCurrentInputForDirectDisplayEditing() {
        guard canDirectlyEditDisplay,
              let canonical = canonicalNumberString(from: currentInput) else {
            return
        }

        if currentInput != canonical {
            currentInput = canonical
            shouldPreserveTypedCurrencyInput = activeCurrencySymbol != nil
            setCurrentTokenToCurrentInput()
            updateDisplay()
        }
    }

    private func insertDigitIntoCurrentInput(_ digit: String, at rawIndex: Int) {
        let insertionIndex = normalizedDisplayEditCursorIndex(rawIndex)

        if currentInput == "0" {
            currentInput = digit
            displayEditCursorIndex = 1
            return
        }

        if currentInput == "-0" {
            currentInput = "-\(digit)"
            displayEditCursorIndex = 2
            return
        }

        guard currentInputDigitCount < Limits.maxInputDigits else { return }
        let stringIndex = currentInput.index(currentInput.startIndex, offsetBy: insertionIndex)
        currentInput.insert(contentsOf: digit, at: stringIndex)
        displayEditCursorIndex = insertionIndex + digit.count
    }

    private func insertDecimalIntoCurrentInput(at rawIndex: Int) {
        let decimalSeparator = numberFormatStyle.decimalSeparator
        guard !currentInput.contains(decimalSeparator), !currentInput.contains(".") else { return }

        let insertionIndex = normalizedDisplayEditCursorIndex(rawIndex)
        let insertionText: String
        if insertionIndex == 0 || (currentInput.hasPrefix("-") && insertionIndex == 1) {
            insertionText = "0\(decimalSeparator)"
        } else {
            insertionText = decimalSeparator
        }

        let stringIndex = currentInput.index(currentInput.startIndex, offsetBy: insertionIndex)
        currentInput.insert(contentsOf: insertionText, at: stringIndex)
        displayEditCursorIndex = insertionIndex + insertionText.count
        normalizeCurrentInputAfterCursorEdit()
    }

    private func deleteDigitBeforeDisplayCursor(_ rawIndex: Int) {
        let cursorIndex = normalizedDisplayEditCursorIndex(rawIndex)
        guard cursorIndex > 0 else { return }
        guard !(currentInput.hasPrefix("-") && cursorIndex == 1) else { return }

        let removalIndex = currentInput.index(currentInput.startIndex, offsetBy: cursorIndex - 1)
        currentInput.remove(at: removalIndex)
        displayEditCursorIndex = cursorIndex - 1
        normalizeCurrentInputAfterCursorEdit()
    }

    private func normalizeCurrentInputAfterCursorEdit() {
        let decimalSeparator = numberFormatStyle.decimalSeparator

        if currentInput.isEmpty || currentInput == "-" {
            currentInput = "0"
            displayEditCursorIndex = 1
            return
        }

        if currentInput.hasPrefix(decimalSeparator) || currentInput.hasPrefix(".") {
            currentInput = "0" + currentInput
            if let cursorIndex = displayEditCursorIndex {
                displayEditCursorIndex = cursorIndex + 1
            }
            return
        }

        let negativeDecimalPrefix = "-\(decimalSeparator)"
        if currentInput.hasPrefix(negativeDecimalPrefix) || currentInput.hasPrefix("-.") {
            currentInput.insert("0", at: currentInput.index(after: currentInput.startIndex))
            if let cursorIndex = displayEditCursorIndex {
                displayEditCursorIndex = cursorIndex + 1
            }
        }
    }

    private func displayBoundaryToRawCursorMapping() -> [Int] {
        let displayCharacters = Array(display)
        let rawCharacters = Array(currentInput)
        var rawIndex = 0
        var mapping: [Int] = [0]

        for displaySymbol in displayCharacters {
            if rawIndex < rawCharacters.count,
               displayCharacterMatchesRawCharacter(displaySymbol, rawCharacter: rawCharacters[rawIndex]) {
                rawIndex += 1
            }
            mapping.append(rawIndex)
        }

        return mapping
    }

    private func displayBoundaryIndex(forRawCursorIndex rawIndex: Int) -> Int? {
        let normalized = normalizedDisplayEditCursorIndex(rawIndex)
        return displayBoundaryToRawCursorMapping().firstIndex(of: normalized)
    }

    private func displayCharacterMatchesRawCharacter(_ displayCharacter: Character, rawCharacter: Character) -> Bool {
        if displayCharacter == rawCharacter {
            return true
        }

        if rawCharacter == "-" {
            return displayCharacter == "-" || displayCharacter == "−"
        }

        let decimalSeparator = Character(numberFormatStyle.decimalSeparator)
        if rawCharacter == decimalSeparator || rawCharacter == "." || rawCharacter == "," {
            return displayCharacter == decimalSeparator || displayCharacter == "." || displayCharacter == ","
        }

        return false
    }

    private var pendingOperandShouldKeepPercentToken: Bool {
        pendingOperator != nil && accumulatorUsesStandalonePercentToken
    }

    private var pendingOperatorShouldKeepPercentToken: Bool {
        pendingOperator != nil
    }

    private var shouldDisplayPercentTokenAsMainDisplay: Bool {
        guard currentToken.hasSuffix("%") else {
            return false
        }

        // A percent-of-percent result has no pending operator left, so it needs
        // its own reason to keep showing the token rather than the raw decimal.
        if resultUsesPercentToken {
            return true
        }

        if isExpressionMode && !shouldResetInputOnNextDigit {
            return true
        }

        return pendingOperator != nil
    }

    // True when both sides of the operation were themselves standalone percent
    // tokens: 9% + 9% is 18%, not 0.18. Restricted to + and − because × and ÷
    // combine the percentages instead of accumulating them (9% × 9% is 0.81%).
    private func operationYieldsPercentResult(pending: BinaryOperator, lhsToken: String, rhsToken: String) -> Bool {
        guard lhsToken.hasSuffix("%"), rhsToken.hasSuffix("%") else { return false }

        switch pending {
        case .add, .subtract:
            return true
        case .multiply, .divide:
            return false
        }
    }

    private func percentTokenString(forStoredValue value: Decimal) -> String {
        "\(format(value * 100))%"
    }

    private var accumulatorUsesStandalonePercentToken: Bool {
        accumulatorToken?.hasSuffix("%") == true
    }

    private func resolvedPercentValue() -> Decimal {
        if let pending = pendingOperator, let lhs = accumulator {
            switch pending {
            case .add, .subtract:
                if accumulatorUsesStandalonePercentToken {
                    return currentValue / 100
                }
                return lhs * currentValue / 100
            case .multiply, .divide:
                return currentValue / 100
            }
        }

        return currentValue / 100
    }

    private func refreshFormattedState() {
        guard !isErrorState else {
            updateDisplay()
            return
        }

        if let value = parseStoredNumber(currentInput) {
            currentInput = format(value)
            shouldPreserveTypedCurrencyInput = false
            setCurrentTokenToCurrentInput()
        }

        if let accumulator {
            accumulatorToken = displayString(for: format(accumulator), useActiveCurrency: false)
        }

        if let lastOperand {
            lastOperandToken = displayString(for: format(lastOperand), useActiveCurrency: false)
        }

        expressionTokens = expressionTokens.map { token in
            guard let normalized = normalizeDisplayNumberToken(token) else { return token }
            return displayString(for: normalized, useActiveCurrency: false)
        }

        memoryEntries = memoryEntries.map {
            MemoryEntry(id: $0.id, value: $0.value, displayValue: displayString(for: format($0.value)))
        }

        history = history.map {
            let displayResult: String
            let displayExpression: String
            if $0.expression.contains("round(") {
                displayResult = displayString(for: $0.result, useActiveCurrency: false)
                if let rounded = parseRoundedOperation($0.expression),
                   let sourceValue = evaluateExpressionString(rounded.baseExpression) {
                    let relationSymbol = $0.expression.contains("≈") ? "≈" : "="
                    displayExpression = roundedOperationDisplayString(
                        baseExpression: rounded.baseExpression,
                        sourceValue: sourceValue,
                        precision: rounded.precision,
                        relationSymbol: relationSymbol
                    )
                } else {
                    displayExpression = groupedExpressionString($0.expression)
                }
            } else {
                displayResult = displayString(for: $0.result, useActiveCurrency: false)
                displayExpression = groupedExpressionString($0.expression)
            }
            return HistoryEntry(
                expression: $0.expression,
                result: $0.result,
                displayExpression: displayExpression,
                displayResult: displayResult
            )
        }

        updateDisplay()
    }

    private func refreshCurrentSessionDisplayTokens() {
        if let value = parseStoredNumber(currentInput), !isErrorState {
            currentInput = format(value)
            shouldPreserveTypedCurrencyInput = false
            setCurrentTokenToCurrentInput()
        }

        if let accumulator {
            accumulatorToken = displayString(for: format(accumulator), useActiveCurrency: false)
        }

        if let lastOperand {
            lastOperandToken = displayString(for: format(lastOperand), useActiveCurrency: false)
        }

        expressionTokens = expressionTokens.map { token in
            guard let normalized = normalizeDisplayNumberToken(token) else { return token }
            return displayString(for: normalized, useActiveCurrency: false)
        }

        updateDisplay()
    }

    private func boundedDisplayToken(_ proposed: String, fallback: String) -> String {
        proposed.count <= Limits.maxDisplayTokenLength ? proposed : fallback
    }

    private func parseStoredNumber(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^[+-]?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$", options: .regularExpression) != nil {
            let decimal = NSDecimalNumber(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
            if decimal != .notANumber {
                return decimal.decimalValue
            }
        }

        guard let normalized = normalizeNumberString(raw, treatPercentAsMultiplier: false)
            ?? normalizeNumberStringUsingAnyStyle(raw, treatPercentAsMultiplier: false, excluding: numberFormatStyle)
        else {
            return nil
        }
        let decimal = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        return decimal == .notANumber ? nil : decimal.decimalValue
    }

    private func canonicalNumberString(from raw: String) -> String? {
        parseStoredNumber(raw).map(decimalNumberString(from:))
    }

    private func clipboardNumberString(from raw: String, preserveTrailingZeros: Bool = false) -> String? {
        if let currencySymbol = effectiveCurrencySymbol(for: raw, useActiveCurrency: true) {
            if shouldUseScientificNotation(for: raw) {
                let numeric = raw.localizedCaseInsensitiveContains("e")
                    ? localizedNumericString(raw)
                    : displayString(for: raw, useActiveCurrency: false)
                return decorateCurrencyAmount(numeric, with: currencySymbol)
            }

            guard let value = parseStoredNumber(raw) else { return nil }
            let amount = currencyAmountString(
                from: value,
                raw: raw,
                useGrouping: false,
                preserveTrailingZeros: preserveTrailingZeros
            )
            return decorateCurrencyAmount(amount, with: currencySymbol)
        }

        if raw.localizedCaseInsensitiveContains("e") {
            return raw
        }

        guard let canonical = canonicalNumberString(from: raw) else { return nil }
        if numberFormatStyle.decimalSeparator == "." {
            return canonical
        }

        return canonical.replacingOccurrences(of: ".", with: numberFormatStyle.decimalSeparator)
    }

    private func displayString(for raw: String, useActiveCurrency: Bool = true, preserveTrailingZeros: Bool = false) -> String {
        guard let value = parseStoredNumber(raw) else { return raw }
        let currencySymbol = effectiveCurrencySymbol(for: raw, useActiveCurrency: useActiveCurrency)
        if shouldUseScientificNotation(for: raw) {
            let scientific = formatScientific(value)
            if let currencySymbol {
                return decorateCurrencyAmount(scientific, with: currencySymbol)
            }
            return scientific
        }
        let normalizedRaw: String
        if raw.localizedCaseInsensitiveContains("e") {
            normalizedRaw = formatter.string(from: NSDecimalNumber(decimal: value)) ?? raw
        } else {
            normalizedRaw = raw
        }
        if let currencySymbol {
            let amount = currencyAmountString(
                from: value,
                raw: raw,
                useGrouping: true,
                preserveTrailingZeros: preserveTrailingZeros
            )
            return decorateCurrencyAmount(amount, with: currencySymbol)
        }
        return groupedNumberString(normalizedRaw)
    }

    private func currencyAmountString(
        from value: Decimal,
        raw: String,
        useGrouping: Bool,
        preserveTrailingZeros: Bool
    ) -> String {
        if preserveTrailingZeros,
           let normalized = normalizedCurrencyNumberString(from: raw),
           normalized.contains(".") {
            return useGrouping ? groupedNumberString(normalized) : localizedNumericString(normalized)
        }

        return localizedFixedScaleString(from: value, scale: currencyFractionScale(for: raw), useGrouping: useGrouping)
    }

    private func localizedNumericString(_ raw: String) -> String {
        if numberFormatStyle.decimalSeparator == "." {
            return raw
        }

        return raw.replacingOccurrences(of: ".", with: numberFormatStyle.decimalSeparator)
    }

    private func localizedFixedScaleString(from value: Decimal, scale: Int, useGrouping: Bool) -> String {
        var working = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &working, scale, .plain)

        var canonical = decimalNumberString(from: rounded)
        if scale > 0 {
            let parts = canonical.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 1 {
                canonical.append(".")
                canonical.append(String(repeating: "0", count: scale))
            } else if parts[1].count < scale {
                canonical.append(String(repeating: "0", count: scale - parts[1].count))
            }
        }

        if useGrouping {
            return groupedNumberString(canonical)
        }

        return localizedNumericString(canonical)
    }

    private func canonicalFixedScaleString(from value: Decimal, scale: Int) -> String {
        let localized = localizedFixedScaleString(from: value, scale: scale, useGrouping: false)
        if numberFormatStyle.decimalSeparator == "." {
            return localized
        }

        return localized.replacingOccurrences(of: numberFormatStyle.decimalSeparator, with: ".")
    }

    private func decorateCurrencyAmount(_ amount: String, with symbol: String) -> String {
        if amount.hasPrefix("-") || amount.hasPrefix("−") {
            return "-\(symbol)\(String(amount.dropFirst()))"
        }

        return "\(symbol)\(amount)"
    }

    private func normalizedCurrencyNumberString(from raw: String) -> String? {
        normalizeNumberString(raw, treatPercentAsMultiplier: false)
            ?? normalizeNumberStringUsingAnyStyle(raw, treatPercentAsMultiplier: false, excluding: numberFormatStyle)
    }

    private func currencyFractionScale(for raw: String, minimumFractionDigits: Int = 0) -> Int {
        guard let normalized = normalizedCurrencyNumberString(from: raw),
              let decimalIndex = normalized.firstIndex(of: ".")
        else {
            return minimumFractionDigits
        }

        let fraction = String(normalized[normalized.index(after: decimalIndex)...])
        guard !fraction.isEmpty else { return 0 }

        var trimmedFraction = fraction
        while trimmedFraction.last == "0" {
            trimmedFraction.removeLast()
        }

        return max(minimumFractionDigits, trimmedFraction.count)
    }

    private func storedHistoryResultString(from raw: String) -> String {
        guard let currencySymbol = effectiveCurrencySymbol(for: raw, useActiveCurrency: true),
              !raw.localizedCaseInsensitiveContains("e"),
              let value = parseStoredNumber(raw) else {
            if raw.localizedCaseInsensitiveContains("e") {
                return raw
            }
            if let value = parseStoredNumber(raw) {
                return decimalNumberString(from: value)
            }
            return raw
        }

        let amount = localizedFixedScaleString(from: value, scale: currencyFractionScale(for: raw), useGrouping: false)
        return decorateCurrencyAmount(amount, with: currencySymbol)
    }

    private func shouldUseScientificNotation(for raw: String) -> Bool {
        guard usesScientificNotation else { return false }
        let numericRaw = normalizeNumberString(raw, treatPercentAsMultiplier: false) ?? raw
        if numericRaw == "0" { return false }
        let digitCount = significantDigitCount(in: numericRaw)
        return numericRaw.localizedCaseInsensitiveContains("e")
            || digitCount > Limits.maxInputDigits
            || requiresScientificNotationForSmallMagnitude(in: numericRaw)
    }

    private func significantDigitCount(in raw: String) -> Int {
        var working = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        if let exponentRange = working.range(of: "e", options: [.caseInsensitive]) {
            working = String(working[..<exponentRange.lowerBound])
        }

        working = working
            .replacingOccurrences(of: numberFormatStyle.decimalSeparator, with: ".")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+", with: "")

        let digits = working.drop(while: { $0 == "0" })
        return digits.isEmpty ? 0 : digits.count
    }

    private func formatScientific(_ value: Decimal) -> String {
        guard value != 0 else { return "0" }

        let plainText = formatter.string(from: NSDecimalNumber(decimal: value)) ?? decimalNumberString(from: value)
        return scientificString(fromRoundedDecimal: plainText)
    }

    private func formatScientific(_ value: Double) -> String {
        guard value != 0 else { return "0" }

        let plainText = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return scientificString(fromRoundedDecimal: plainText)
    }

    private func roundedDisplayString(fromStoredNumber raw: String, precision: Int) -> String {
        guard !shouldUseScientificNotation(for: raw),
              let value = parseStoredNumber(raw) else {
            return displayString(for: raw)
        }

        let rounded = roundedDecimal(from: value, precision: precision)
        let minimumCurrencyFractionDigits = effectiveCurrencySymbol(for: raw, useActiveCurrency: true) == nil
            ? 0
            : Self.minimumRoundedCurrencyFractionDigits
        let roundedText = roundedStoredNumberString(from: rounded, minimumCurrencyFractionDigits: minimumCurrencyFractionDigits)
        return displayString(for: roundedText, preserveTrailingZeros: minimumCurrencyFractionDigits > 0)
    }

    private func roundedValueString(precision: Int) -> String {
        guard !shouldUseScientificNotation(for: currentInput),
              let value = parseStoredNumber(currentInput) else {
            return currentInput
        }

        let rounded = roundedDecimal(from: value, precision: precision)
        let minimumCurrencyFractionDigits = effectiveCurrencySymbol(for: currentInput, useActiveCurrency: true) == nil
            ? 0
            : Self.minimumRoundedCurrencyFractionDigits
        return roundedStoredNumberString(from: rounded, minimumCurrencyFractionDigits: minimumCurrencyFractionDigits)
    }

    private func roundedStoredNumberString(from value: Decimal, minimumCurrencyFractionDigits: Int) -> String {
        let roundedText = decimalNumberString(from: value)
        guard minimumCurrencyFractionDigits > 0 else {
            return roundedText
        }

        let scale = currencyFractionScale(for: roundedText, minimumFractionDigits: minimumCurrencyFractionDigits)
        return canonicalFixedScaleString(from: value, scale: scale)
    }

    private func roundingRelationSymbol(fromStoredNumber raw: String, precision: Int) -> String {
        isRoundingApproximate(fromStoredNumber: raw, precision: precision) ? "≈" : "="
    }

    private func isRoundingApproximate(fromStoredNumber raw: String, precision: Int) -> Bool {
        guard !shouldUseScientificNotation(for: raw),
              let original = parseStoredNumber(raw) else { return false }
        let rounded = roundedDecimal(from: original, precision: precision)
        return rounded != original
    }

    private func roundedDecimal(from value: Decimal, precision: Int) -> Decimal {
        let normalizedPrecision = normalizedRoundingPrecision(precision)
        guard value != 0 else { return 0 }

        let availableDigits = max(1, significantDigitCount(in: decimalNumberString(from: value)))
        let effectiveLevels = min(normalizedPrecision, max(availableDigits - 1, 0))
        let retainedDigits = max(availableDigits - effectiveLevels, 1)

        let absoluteValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        guard absoluteValue.isFinite, absoluteValue > 0 else {
            return value
        }

        let magnitude = floor(log10(absoluteValue))
        let scale = retainedDigits - Int(magnitude) - 1
        var working = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &working, scale, .plain)
        return rounded
    }

    private func appendRoundedHistoryEventIfNeeded() {
        guard isResultRoundingEnabled, !isErrorState else { return }

        // Do not record rounded history while the user is still mid-expression.
        if shouldResetInputOnNextDigit && (pendingOperator != nil || isExpressionMode) {
            return
        }

        let header: String
        if isExpressionMode {
            header = expressionPreviewHeader()
        } else if let op = pendingOperator {
            let lhsText = accumulatorToken ?? currentToken
            let rhsText = shouldResetInputOnNextDigit ? nil : currentToken
            if let rhsText {
                header = "\(lhsText) \(op.symbol) \(rhsText)"
            } else {
                header = "\(lhsText) \(op.symbol)"
            }
        } else if !expression.isEmpty {
            header = expression
        } else {
            header = lastResultSummary
        }

        let baseExpression = baseExpressionForRounding(from: header)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseExpression.isEmpty else { return }

        let roundedResult = roundedDisplayString(fromStoredNumber: currentInput, precision: resultRoundingPrecision)
        let relationSymbol = roundingRelationSymbol(fromStoredNumber: currentInput, precision: resultRoundingPrecision)
        let roundedExpression: String
        if relationSymbol == "≈" {
            roundedExpression = "round(\(baseExpression)\(numberFormatStyle.spreadsheetArgumentSeparator) \(resultRoundingPrecision)) ≈"
        } else {
            roundedExpression = "round(\(baseExpression)\(numberFormatStyle.spreadsheetArgumentSeparator) \(resultRoundingPrecision))"
        }
        if let latest = history.first,
           latest.expression == roundedExpression,
           latest.result == roundedResult {
            return
        }

        appendHistory(expression: baseExpression, result: currentInput)
        lastResultSummary = "\(baseExpression) ="
    }

    private func baseExpressionForRounding(from header: String) -> String {
        if !isExpressionMode, pendingOperator == nil {
            let standaloneValue = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !standaloneValue.isEmpty {
                return standaloneValue
            }
        }

        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return currentToken
        }

        if let rounded = parseRoundedOperation(trimmed) {
            return rounded.baseExpression
        }

        if trimmed.hasSuffix("=") {
            return String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func normalizedRoundingPrecision(_ precision: Int) -> Int {
        min(max(precision, 1), Limits.maxInputDigits)
    }

    private func parseRoundedOperation(_ raw: String) -> (baseExpression: String, precision: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDisplayRoundOperation = trimmed.hasPrefix("=round(")
        let normalized = isDisplayRoundOperation ? String(trimmed.dropFirst()) : trimmed
        guard normalized.hasPrefix("round(") else { return nil }

        guard let closeIndex = roundedOperationClosingParenthesis(in: normalized) else {
            return nil
        }

        let argumentRange = normalized.index(normalized.startIndex, offsetBy: 6)..<closeIndex
        let arguments = String(normalized[argumentRange])
        guard let (expressionPart, precisionPart) = splitRoundedOperationArguments(arguments) else {
            return nil
        }

        guard !expressionPart.isEmpty, let parsedPrecision = Int(precisionPart) else {
            return nil
        }

        if isDisplayRoundOperation {
            return (
                expressionPart,
                roundingPrecision(fromDisplayedScale: parsedPrecision, baseExpression: expressionPart)
            )
        }

        return (expressionPart, normalizedRoundingPrecision(parsedPrecision))
    }

    private func roundedOperationDisplayString(baseExpression: String, sourceValue: String, precision: Int, relationSymbol: String) -> String {
        let displayExpression = ungroupedExpressionString(completedOperationDisplayExpression(baseExpression))
        let scale = spreadsheetRoundScale(fromStoredNumber: sourceValue, precision: precision)
        let prefix = "=round(\(displayExpression)\(numberFormatStyle.spreadsheetArgumentSeparator) \(scale))"
        return relationSymbol == "≈" ? "\(prefix) ≈" : prefix
    }

    private func spreadsheetRoundScale(fromStoredNumber raw: String, precision: Int) -> Int {
        guard let value = parseStoredNumber(raw) else { return 0 }
        return spreadsheetRoundScale(from: value, precision: precision)
    }

    private func spreadsheetRoundScale(from value: Decimal, precision: Int) -> Int {
        guard value != 0 else { return 0 }

        let normalizedPrecision = normalizedRoundingPrecision(precision)
        let availableDigits = max(1, significantDigitCount(in: decimalNumberString(from: value)))
        let effectiveLevels = min(normalizedPrecision, max(availableDigits - 1, 0))
        let retainedDigits = max(availableDigits - effectiveLevels, 1)

        let absoluteValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        guard absoluteValue.isFinite, absoluteValue > 0 else { return 0 }

        let magnitude = floor(log10(absoluteValue))
        return retainedDigits - Int(magnitude) - 1
    }

    private func roundingPrecision(fromDisplayedScale scale: Int, baseExpression: String) -> Int {
        guard let evaluated = evaluateExpressionString(baseExpression),
              let value = parseStoredNumber(evaluated),
              value != 0 else {
            return 1
        }

        let availableDigits = max(1, significantDigitCount(in: decimalNumberString(from: value)))
        let absoluteValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        guard absoluteValue.isFinite, absoluteValue > 0 else { return 1 }

        let magnitude = floor(log10(absoluteValue))
        let retainedDigits = max(scale + Int(magnitude) + 1, 1)
        let effectiveLevels = max(availableDigits - retainedDigits, 0)
        return normalizedRoundingPrecision(max(effectiveLevels, 1))
    }

    private func ungroupedExpressionString(_ expression: String) -> String {
        let groupingSeparators = numberFormatStyle.groupingSeparatorCharacters
        let characters = Array(expression)
        var result = String()
        result.reserveCapacity(characters.count)

        for index in characters.indices {
            let character = characters[index]
            if groupingSeparators.contains(character) {
                let previous = index > characters.startIndex ? characters[characters.index(before: index)] : nil
                let next = index < characters.index(before: characters.endIndex) ? characters[characters.index(after: index)] : nil
                if previous?.isNumber == true && next?.isNumber == true {
                    continue
                }
            }
            result.append(character)
        }

        return result
    }

    private func roundedOperationClosingParenthesis(in raw: String) -> String.Index? {
        var depth = 0
        for index in raw.indices {
            let character = raw[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }

    private func splitRoundedOperationArguments(_ raw: String) -> (String, String)? {
        var depth = 0
        var separatorCandidates: [String.Index] = []
        for index in raw.indices {
            let character = raw[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 && (character == "," || character == ";") {
                separatorCandidates.append(index)
            }
        }

        for candidate in separatorCandidates.reversed() {
            let expressionPart = String(raw[..<candidate]).trimmingCharacters(in: .whitespacesAndNewlines)
            let precisionPart = String(raw[raw.index(after: candidate)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !expressionPart.isEmpty, Int(precisionPart) != nil {
                return (expressionPart, precisionPart)
            }
        }

        return nil
    }

    private func evaluateExpressionString(_ expression: String) -> String? {
        guard let steps = parseReplaySteps(expression) else { return nil }
        let tempModel = CalculatorViewModel()
        tempModel.suppressHistoryTracking = true
        for step in steps + [.evaluate] {
            tempModel.applyPasteReplayStep(step)
            if tempModel.isErrorState {
                return nil
            }
        }
        return tempModel.currentInput
    }

    private func requiresScientificNotationForSmallMagnitude(in raw: String) -> Bool {
        var working = raw
        if working.range(of: "e", options: [.caseInsensitive]) != nil {
            return true
        }

        if working.hasPrefix("-") {
            working.removeFirst()
        }

        guard let decimalIndex = working.firstIndex(of: ".") else {
            return false
        }

        let integerPart = String(working[..<decimalIndex])
        guard integerPart == "0" else {
            return false
        }

        let fractionalPart = String(working[working.index(after: decimalIndex)...])
        guard let firstNonZeroIndex = fractionalPart.firstIndex(where: { $0 != "0" }) else {
            return false
        }

        return fractionalPart.distance(from: fractionalPart.startIndex, to: firstNonZeroIndex) + 1 > (Limits.maxInputDigits - 1)
    }

    private func decimalNumber(from raw: String) -> NSDecimalNumber? {
        guard let normalized = normalizeNumberString(raw, treatPercentAsMultiplier: false) else { return nil }
        let decimal = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        return decimal == .notANumber ? nil : decimal
    }

    private func decimalValue(fromCanonicalString raw: String) -> Decimal? {
        let decimal = NSDecimalNumber(string: raw, locale: Locale(identifier: "en_US_POSIX"))
        return decimal == .notANumber ? nil : decimal.decimalValue
    }

    private func decimalValue(fromDisplayText raw: String) -> Decimal? {
        guard let normalized = normalizeDisplayNumberToken(raw) else { return nil }
        return decimalValue(fromCanonicalString: normalized)
    }

    private func formattedPastedInput(fromCanonical canonical: String, value: Decimal) -> String {
        var formatted = format(value)

        let split = canonical.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard split.count == 2 else { return formatted }
        let desiredFractionLength = split[1].count
        guard desiredFractionLength > 0 else { return formatted }

        let decimalSeparator = numberFormatStyle.decimalSeparator
        let parts = formatted.components(separatedBy: decimalSeparator)
        if parts.count == 1 {
            formatted.append(contentsOf: decimalSeparator)
            formatted.append(String(repeating: "0", count: desiredFractionLength))
            return formatted
        }

        if parts.count == 2 {
            let currentFractionLength = parts[1].count
            if currentFractionLength < desiredFractionLength {
                formatted.append(String(repeating: "0", count: desiredFractionLength - currentFractionLength))
            }
        }

        return formatted
    }

    private func decimalNumberString(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func scientificString(fromRoundedDecimal raw: String) -> String {
        let scientificParts = scientificParts(fromRoundedDecimal: raw)
        var mantissaText = scientificParts.mantissa
        let exponent = scientificParts.exponent

        if numberFormatStyle.decimalSeparator != "." {
            mantissaText = mantissaText.replacingOccurrences(of: ".", with: numberFormatStyle.decimalSeparator)
        }

        let exponentSign = exponent >= 0 ? "+" : "-"
        return "\(mantissaText)e\(exponentSign)\(abs(exponent))"
    }

    private func scientificParts(fromRoundedDecimal raw: String) -> (mantissa: String, exponent: Int) {
        var working = raw
        var sign = ""

        if working.hasPrefix("-") {
            sign = "-"
            working.removeFirst()
        }

        if let decimalIndex = working.firstIndex(of: ".") {
            let integerPart = String(working[..<decimalIndex])
            let fractionalPart = String(working[working.index(after: decimalIndex)...])

            if integerPart != "0" {
                let digits = integerPart + fractionalPart
                let mantissaDigits = trimTrailingZeros(in: String(digits.dropFirst()))
                let mantissa = mantissaDigits.isEmpty ? sign + String(digits.prefix(1)) : sign + String(digits.prefix(1)) + "." + mantissaDigits
                return (mantissa, integerPart.count - 1)
            }

            let fractionalDigits = Array(fractionalPart)
            guard let firstNonZeroIndex = fractionalDigits.firstIndex(where: { $0 != "0" }) else {
                return ("0", 0)
            }

            let leadingDigit = String(fractionalDigits[firstNonZeroIndex])
            let trailingDigits = trimTrailingZeros(in: String(fractionalDigits[(firstNonZeroIndex + 1)...]))
            let mantissa = trailingDigits.isEmpty ? sign + leadingDigit : sign + leadingDigit + "." + trailingDigits
            return (mantissa, -(firstNonZeroIndex + 1))
        }

        let mantissaDigits = trimTrailingZeros(in: String(working.dropFirst()))
        let mantissa = mantissaDigits.isEmpty ? sign + String(working.prefix(1)) : sign + String(working.prefix(1)) + "." + mantissaDigits
        return (mantissa, working.count - 1)
    }

    private func trimTrailingZeros(in digits: String) -> String {
        var trimmed = digits
        while trimmed.last == "0" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func normalizeDisplayNumberToken(_ token: String) -> String? {
        normalizeNumberString(token, treatPercentAsMultiplier: false)
            ?? normalizeNumberStringUsingAnyStyle(token, treatPercentAsMultiplier: false, excluding: numberFormatStyle)
    }

    private func shouldTreatSingleSeparatorAsGrouping(_ filtered: String, separator: Character) -> Bool { false }

    private func normalizeNumberString(_ raw: String, treatPercentAsMultiplier: Bool, style: NumberFormatStyle? = nil) -> String? {
        let activeStyle = style ?? numberFormatStyle
        guard let currencyContext = currencyInputContext(from: raw) else { return nil }
        let trimmed = currencyContext.rawNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowed = CharacterSet(charactersIn: "0123456789.,-−+eE %'\u{00A0}\u{202F}")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }

        var working = trimmed
        let hasPercent = working.contains("%")
        if hasPercent {
            working = working.replacingOccurrences(of: "%", with: "")
        }

        if let exponentRange = working.range(of: "e", options: [.caseInsensitive]) {
            let mantissa = String(working[..<exponentRange.lowerBound])
            let exponent = String(working[exponentRange.upperBound...])
            guard exponent.range(of: "^[+-]?\\d+$", options: .regularExpression) != nil else {
                return nil
            }
            guard let normalizedMantissa = normalizeNumberString(
                mantissa,
                treatPercentAsMultiplier: false,
                style: activeStyle
            ) else {
                return nil
            }
            return normalizedMantissa + "e" + exponent.lowercased()
        }

        var sign = ""
        if working.hasPrefix("+") {
            working.removeFirst()
        } else if working.hasPrefix("-") || working.hasPrefix("−") {
            sign = "-"
            working.removeFirst()
        }

        if activeStyle == .french {
            working = working
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }

        guard let decimalSeparator = activeStyle.decimalSeparator.first else { return nil }
        let groupingSeparators = activeStyle.groupingSeparatorCharacters
        let decimalPieces = working.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        guard decimalPieces.count <= 2 else { return nil }

        let integerPart = String(decimalPieces.first ?? "")
        let fractionPart = decimalPieces.count == 2 ? String(decimalPieces[1]) : ""
        guard !integerPart.isEmpty || !fractionPart.isEmpty else { return nil }

        guard let normalizedInteger = normalizeIntegerPart(integerPart, groupingSeparators: groupingSeparators, style: activeStyle) else {
            return nil
        }
        guard fractionPart.allSatisfy({ $0.isNumber }) else { return nil }

        var normalized = sign + normalizedInteger
        if decimalPieces.count == 2 {
            normalized.append(".")
            normalized.append(fractionPart)
        }

        if hasPercent, treatPercentAsMultiplier {
            guard let percentValue = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX")).decimalValue as Decimal? else {
                return nil
            }
            return decimalNumberString(from: percentValue / 100)
        }

        if currencyContext.treatAsCents {
            let centsValue = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
            guard centsValue != .notANumber else { return nil }
            return decimalNumberString(from: centsValue.decimalValue / 100)
        }

        return normalized
    }

    private static func isSupportedCurrencySymbol(_ value: String) -> Bool {
        value.count == 1 && value.allSatisfy { supportedCurrencySymbolCharacters.contains($0) }
    }

    private func explicitCurrencySymbol(in raw: String) -> String? {
        for character in raw {
            if character == "¢" {
                return "$"
            }
            if Self.supportedCurrencySymbolCharacters.contains(character) {
                return String(character)
            }
        }
        return nil
    }

    private func effectiveCurrencySymbol(for raw: String, useActiveCurrency: Bool) -> String? {
        explicitCurrencySymbol(in: raw) ?? (useActiveCurrency ? activeCurrencySymbol : nil)
    }

    private func currencyInputContext(from raw: String) -> (symbol: String?, rawNumber: String, treatAsCents: Bool)? {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        var sign = ""
        if working.hasPrefix("+") {
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if working.hasPrefix("-") || working.hasPrefix("−") {
            sign = "-"
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var symbol: String?
        while let first = working.first, Self.supportedCurrencySymbolCharacters.contains(first), first != "¢" {
            symbol = symbol ?? String(first)
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if sign.isEmpty, working.hasPrefix("+") {
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if sign.isEmpty, working.hasPrefix("-") || working.hasPrefix("−") {
            sign = "-"
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var treatAsCents = false
        if working.hasSuffix("¢") {
            working.removeLast()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
            symbol = "$"
            treatAsCents = true
        } else if let last = working.last, Self.supportedCurrencySymbolCharacters.contains(last) {
            return nil
        }

        return (symbol, sign + working, treatAsCents)
    }

    private func normalizeNumberStringUsingAnyStyle(
        _ raw: String,
        treatPercentAsMultiplier: Bool,
        excluding excludedStyle: NumberFormatStyle? = nil
    ) -> String? {
        for style in NumberFormatStyle.allCases where style != excludedStyle {
            if let normalized = normalizeNumberString(raw, treatPercentAsMultiplier: treatPercentAsMultiplier, style: style) {
                return normalized
            }
        }
        return nil
    }

    private func normalizeIntegerPart(_ integerPart: String, groupingSeparators: Set<Character>, style: NumberFormatStyle) -> String? {
        if integerPart.isEmpty { return "" }

        let hasGrouping = integerPart.contains { groupingSeparators.contains($0) }
        if !hasGrouping {
            return integerPart.allSatisfy({ $0.isNumber }) ? integerPart : nil
        }

        let segments = integerPart.split(omittingEmptySubsequences: false, whereSeparator: { groupingSeparators.contains($0) })
        guard !segments.isEmpty, segments.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isNumber }) }) else {
            return nil
        }

        switch style {
        case .indian:
            guard let last = segments.last, last.count == 3 else { return nil }
            guard let first = segments.first, (1...3).contains(first.count) else { return nil }
            if segments.count > 2 {
                guard segments.dropFirst().dropLast().allSatisfy({ $0.count == 2 }) else { return nil }
            }
        default:
            guard let first = segments.first, (1...3).contains(first.count) else { return nil }
            guard segments.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }

        return segments.joined()
    }

    private func trimToNewestEntries<T>(_ entries: inout [T], maxCount: Int) {
        guard entries.count > maxCount else { return }
        entries.removeSubrange(maxCount...)
    }

    private func trimToRecentSnapshots(_ snapshots: inout [CalculatorSnapshot], maxCount: Int) {
        guard snapshots.count > maxCount else { return }
        snapshots.removeFirst(snapshots.count - maxCount)
    }

}
