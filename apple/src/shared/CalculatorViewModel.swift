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

public enum BinaryOperator: String {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"

    var symbol: String { rawValue }

    func apply(_ lhs: Double, _ rhs: Double) -> Double {
        switch self {
        case .add: return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide: return rhs == 0 ? Double.infinity : lhs / rhs
        }
    }

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
    enum Limits {
        static let maxInputDigits = 16
        static let maxStoredHistoryEntries = 64
        static let maxStoredMemoryEntries = 64
        static let maxUndoDepth = 64
        static let maxRedoDepth = 64
        static let maxPasteCharacters = 512
        static let maxPasteReplaySteps = 256
        static let maxPasteNestingDepth = 32
        static let maxDisplayTokenLength = 160
    }

    private enum ParsedPasteContent {
        case value(String)
        case replay([PasteReplayStep])
    }

    private enum ExpressionEvaluationError: Error {
        case invalidInput
        case divideByZero
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
    }

    @Published public private(set) var display: String = "0"
    @Published public private(set) var expressionDisplay: String = ""
    @Published public private(set) var expression: String = ""
    @Published public private(set) var history: [HistoryEntry] = []
    @Published public private(set) var lastResultSummary: String = ""
    @Published public private(set) var memoryEntries: [MemoryEntry] = []
    @Published public private(set) var isErrorState: Bool = false
    @Published public private(set) var usesScientificNotation: Bool = true
    @Published public private(set) var numberFormatStyle: NumberFormatStyle = .western
    @Published public private(set) var usesClassicPercentBehavior: Bool = false
    private var currentErrorKey: String? = nil

    private var currentInput: String = "0"
    private var accumulator: Decimal?
    private var pendingOperator: BinaryOperator?
    private var lastOperator: BinaryOperator?
    private var lastOperand: Decimal?
    private var shouldResetInputOnNextDigit = false
    private var justEvaluated = false
    private var undoStack: [CalculatorSnapshot] = []
    private var redoStack: [CalculatorSnapshot] = []
    private var suppressHistoryTracking = false

    public init(numberFormatStyle: NumberFormatStyle = .western, usesScientificNotation: Bool = true) {
        self.numberFormatStyle = numberFormatStyle
        self.usesScientificNotation = usesScientificNotation
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

    var undoDepth: Int {
        undoStack.count
    }

    var redoDepth: Int {
        redoStack.count
    }

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
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
        decimalNumber(from: currentInput)?.doubleValue ?? 0
    }

    // Human-readable token for the current input, including unary wrappers (e.g., "√(4)").
    private var currentToken: String = "0"
    private var accumulatorToken: String?
    private var lastOperandToken: String?
    private var expressionTokens: [String] = []
    private var openParenthesisCount: Int = 0
    private var isExpressionMode = false

    public func inputParentheses() {
        let symbol: Character = shouldInsertClosingParenthesisInExpressionMode() ? ")" : "("
        inputParenthesis(symbol)
    }

    public func inputParenthesis(_ symbol: Character) {
        guard symbol == "(" || symbol == ")" else { return }
        let snapshot = beginUndoableChange()
        if isErrorState {
            resetStateForNewEntry()
        }
        enterExpressionModeIfNeeded()

        if symbol == "(" {
            if !shouldResetInputOnNextDigit {
                appendCurrentTokenToExpressionIfNeeded()
            }
            if let last = expressionTokens.last,
               isExpressionNumberToken(last) || last == ")" {
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

    public func inputDigit(_ digit: String) {
        guard digit.count == 1, "0123456789".contains(digit) else { return }
        let snapshot = beginUndoableChange()
        if isErrorState { resetStateForNewEntry() }
        if justEvaluated {
            resetStateForNewEntry()
        } else if shouldResetInputOnNextDigit {
            currentInput = "0"
            shouldResetInputOnNextDigit = false
        }
        isErrorState = false
        if currentInput == "0" {
            currentInput = digit
        } else if currentInputDigitCount < Limits.maxInputDigits {
            currentInput.append(digit)
        }
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func inputDecimal() {
        let snapshot = beginUndoableChange()
        if isErrorState { resetStateForNewEntry() }
        if justEvaluated {
            resetStateForNewEntry()
        } else if shouldResetInputOnNextDigit {
            currentInput = "0"
            shouldResetInputOnNextDigit = false
        }
        isErrorState = false
        if !currentInput.contains("."), currentInputDigitCount < Limits.maxInputDigits {
            currentInput.append(".")
        }
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func toggleSign() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        if currentInput.hasPrefix("-") {
            currentInput.removeFirst()
        } else if currentInput != "0" {
            currentInput = "-" + currentInput
        }
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func applyPercent() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        let operandToken = currentToken
        let percentValue = resolvedPercentValue()
        currentInput = format(percentValue)
        if pendingOperator == nil {
            currentToken = boundedDisplayToken("\(operandToken)%", fallback: groupedNumberString(currentInput))
            if !isExpressionMode {
                expression = currentToken
            }
        } else if pendingOperandShouldKeepPercentToken {
            currentToken = boundedDisplayToken("\(operandToken)%", fallback: groupedNumberString(currentInput))
        } else {
            currentToken = displayString(for: currentInput)
        }
        justEvaluated = false
        shouldResetInputOnNextDigit = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func clearEntry() {
        let snapshot = beginUndoableChange()
        currentInput = "0"
        isErrorState = false
        currentErrorKey = nil
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func clearAll() {
        let snapshot = beginUndoableChange()
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
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func backspace() {
        let snapshot = beginUndoableChange()
        if isErrorState {
            clearAll()
            completeUndoableChange(from: snapshot)
            return
        }
        if isExpressionMode, shouldResetInputOnNextDigit {
            if let removed = expressionTokens.popLast() {
                if removed == "(" {
                    openParenthesisCount = max(0, openParenthesisCount - 1)
                } else if removed == ")" {
                    openParenthesisCount += 1
                }
                if isExpressionNumberToken(removed),
                   let normalized = normalizeDisplayNumberToken(removed) {
                    currentInput = normalized
                    currentToken = removed
                    shouldResetInputOnNextDigit = false
                }
            }
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }
        if shouldResetInputOnNextDigit {
            currentInput = "0"
            shouldResetInputOnNextDigit = false
        } else if currentInput.count > 1 {
            currentInput.removeLast()
        } else {
            currentInput = "0"
        }
        setCurrentTokenToCurrentInput()
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func setOperator(_ op: BinaryOperator) {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
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

            if isExpressionOperatorToken(last) {
                expressionTokens.removeLast()
            }

            expressionTokens.append(op.symbol)
            shouldResetInputOnNextDigit = true
            justEvaluated = false
            updateDisplay()
            completeUndoableChange(from: snapshot)
            return
        }

        if let _ = pendingOperator, !shouldResetInputOnNextDigit {
            performPendingOperation(addToHistory: false)
        } else if accumulator == nil {
            accumulator = currentValue
            accumulatorToken = currentToken
        }
        pendingOperator = op
        expression = makeExpressionPreview()
        shouldResetInputOnNextDigit = true
        justEvaluated = false
        updateDisplay()
        completeUndoableChange(from: snapshot)
    }

    public func evaluate() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
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
                appendHistory(expression: evaluatedExpression, result: resultText)
                lastResultSummary = evaluatedExpression + " ="
                currentInput = resultText
                currentToken = displayString(for: resultText)
                accumulator = result
                accumulatorToken = displayString(for: resultText)
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
            }
            completeUndoableChange(from: snapshot)
            return
        }

        if pendingOperator != nil {
            performPendingOperation(addToHistory: true)
        } else if let lastOp = lastOperator, let lastOperand = lastOperand {
            let lhs = currentValue
            let result = lastOp.apply(lhs, lastOperand)
            let resultText = format(result)
            let lhsToken = currentToken
            let rhsToken = lastOperandToken ?? displayString(for: format(lastOperand))
            let exp = "\(lhsToken) \(lastOp.symbol) \(rhsToken)"
            appendHistory(expression: exp, result: resultText)
            lastResultSummary = exp + " ="
            accumulator = result
            currentInput = resultText
            currentToken = displayString(for: resultText)
            accumulatorToken = displayString(for: resultText)
            expression = ""
            shouldResetInputOnNextDigit = true
            justEvaluated = true
            updateDisplay()
        } else {
            accumulator = currentValue
            accumulatorToken = displayString(for: currentInput)
            lastResultSummary = "\(currentToken) ="
            shouldResetInputOnNextDigit = true
            justEvaluated = true
            updateDisplay()
        }
        completeUndoableChange(from: snapshot)
    }

    public func reciprocal() {
        let snapshot = beginUndoableChange()
        let value = currentValue
        guard value != 0 else {
            setError("error.divideByZero")
            completeUndoableChange(from: snapshot)
            return
        }
        let operandToken = currentToken
        currentInput = format(Decimal(1) / value)
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

    public func square() {
        guard !isErrorState else { return }
        let snapshot = beginUndoableChange()
        let operandToken = currentToken
        currentInput = format(currentValue * currentValue)
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

    public func squareRoot() {
        let snapshot = beginUndoableChange()
        let value = currentDoubleValue
        if value < 0 {
            setError("error.invalidInput")
        } else {
            let operandToken = currentToken
            currentInput = format(sqrt(value))
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
        writeStringToPasteboard(currentInput)
    }

    public func copyOperationToPasteboard() {
        guard let operation = currentOperationCopyString() else { return }
        writeStringToPasteboard(operation)
    }

    public func copyOperationToPasteboard(_ entry: HistoryEntry) {
        writeStringToPasteboard(operationCopyString(expression: entry.expression, result: entry.result))
    }

    public func copyResultToPasteboard(_ entry: HistoryEntry) {
        writeStringToPasteboard(entry.result)
    }

    public func pasteFromPasteboard() {
        let snapshot = beginUndoableChange()
        let string: String?
        #if os(macOS)
        string = NSPasteboard.general.string(forType: .string)
        #else
        string = UIPasteboard.general.string
        #endif
        guard let string = string else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Limits.maxPasteCharacters else {
            completeUndoableChange(from: snapshot)
            return
        }
        switch parsePastedContent(trimmed) {
        case .value(let rawValue):
            guard let normalized = normalizePastedNumber(rawValue), let value = parseStoredNumber(normalized) else { return }
            currentInput = format(value)
            expression = ""
            lastOperator = nil
            lastOperand = nil
            pendingOperator = nil
            accumulator = nil
            currentToken = displayString(for: currentInput)
            accumulatorToken = nil
            lastOperandToken = nil
            lastResultSummary = ""
            shouldResetInputOnNextDigit = false
            justEvaluated = false
            isErrorState = false
            currentErrorKey = nil
            updateDisplay()
        case .replay(let steps):
            let tempModel = CalculatorViewModel()
            tempModel.suppressHistoryTracking = true
            tempModel.setClassicPercentBehaviorEnabled(usesClassicPercentBehavior)
            for step in steps {
                tempModel.applyPasteReplayStep(step)
                if tempModel.isErrorState {
                    break
                }
            }
            adoptPastedState(from: tempModel)
        }
        completeUndoableChange(from: snapshot)
    }

    public func reuse(_ entry: HistoryEntry) {
        let snapshot = beginUndoableChange()
        currentInput = entry.result
        accumulator = nil
        pendingOperator = nil
        lastOperator = nil
        lastOperand = nil
        lastResultSummary = "\(entry.expression) ="
        expression = ""
        currentToken = entry.displayResult
        accumulatorToken = nil
        lastOperandToken = nil
        shouldResetInputOnNextDigit = true
        justEvaluated = true
        isErrorState = false
        currentErrorKey = nil
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
        let value = decimalValue(fromDisplayText: entry.displayValue) ?? Decimal(entry.value)
        if isErrorState {
            resetStateForNewEntry()
        }
        let formatted = format(value)
        currentInput = formatted
        currentToken = displayString(for: formatted)
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
        let allowed = CharacterSet(charactersIn: "0123456789.")
        guard working.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return raw
        }

        let components = working.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = String(components.first ?? "")
        let fracPart = components.count > 1 ? String(components[1]) : ""
        let keepTrailingDot = working.hasSuffix(".") && fracPart.isEmpty

        let groupedInt = groupDigits(intPart)
        var result = prefix + groupedInt
        if keepTrailingDot {
            result.append(contentsOf: numberFormatStyle.decimalSeparator)
        } else if !fracPart.isEmpty {
            result.append(contentsOf: numberFormatStyle.decimalSeparator)
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

    private func enterExpressionModeIfNeeded() {
        guard !isExpressionMode else { return }
        isExpressionMode = true
        expressionTokens.removeAll()
        openParenthesisCount = 0
        lastOperator = nil
        lastOperand = nil
        lastOperandToken = nil

        if let pending = pendingOperator {
            let lhs = accumulatorToken ?? currentToken
            expressionTokens.append(lhs)
            expressionTokens.append(pending.symbol)
        } else if currentToken != "0" {
            expressionTokens.append(currentToken)
        }

        pendingOperator = nil
        accumulator = nil
        accumulatorToken = nil
        shouldResetInputOnNextDigit = true
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
        guard let normalized = normalizeDisplayNumberToken(currentToken) else { return }
        let displayToken = displayString(for: normalized)
        if let last = expressionTokens.last, isExpressionNumberToken(last) {
            expressionTokens[expressionTokens.count - 1] = displayToken
        } else {
            expressionTokens.append(displayToken)
        }
    }

    private func expressionPreviewHeader() -> String {
        var previewTokens = expressionTokens
        if !shouldResetInputOnNextDigit,
           let normalized = normalizeDisplayNumberToken(currentToken) {
            let displayToken = displayString(for: normalized)
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
        if let normalized = normalizeDisplayNumberToken(token),
           let value = parseStoredNumber(normalized) {
            return .success(value)
        }

        if let inner = wrappedExpressionOperand(token, prefix: "sqr(") {
            switch expressionTokenValue(inner) {
            case .success(let value):
                return .success(value * value)
            case .failure(let error):
                return .failure(error)
            }
        }

        if let inner = wrappedExpressionOperand(token, prefix: "√(") {
            switch expressionTokenValue(inner) {
            case .success(let value):
                let root = sqrt(NSDecimalNumber(decimal: value).doubleValue)
                return .success(Decimal(root))
            case .failure(let error):
                return .failure(error)
            }
        }

        if let inner = wrappedExpressionOperand(token, prefix: "1/(") {
            switch expressionTokenValue(inner) {
            case .success(let value):
                if value == 0 {
                    return .failure(.divideByZero)
                }
                return .success(Decimal(1) / value)
            case .failure(let error):
                return .failure(error)
            }
        }

        return .failure(.invalidInput)
    }

    private func formatExpressionTokenForDisplay(_ token: String) -> String {
        if let normalized = normalizeDisplayNumberToken(token) {
            if let value = parseStoredNumber(normalized) {
                return displayString(for: format(value))
            }
            return displayString(for: normalized)
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
                result = lhs * rhs
            case BinaryOperator.divide.symbol:
                if rhs == 0 { return .divideByZero }
                result = lhs / rhs
            default:
                return .invalidInput
            }
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

    private func performPendingOperation(addToHistory: Bool) {
        guard let pending = pendingOperator else { return }
        let lhs = accumulator ?? currentValue
        let rhs = currentValue
        let lhsToken = accumulatorToken ?? currentToken
        let rhsToken = currentToken
        if pending == .divide && rhs == 0 {
            setError("error.divideByZero")
            return
        }
        let result = pending.apply(lhs, rhs)
        let resultText = format(result)

        if addToHistory {
            let exp = "\(lhsToken) \(pending.symbol) \(rhsToken)"
            appendHistory(expression: exp, result: resultText)
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
            accumulatorToken = displayString(for: resultText)
            currentToken = accumulatorToken ?? displayString(for: resultText)
            expression = "\(accumulatorToken ?? displayString(for: resultText)) \(pending.symbol)"
            lastOperator = nil
            lastOperand = nil
            shouldResetInputOnNextDigit = true
            justEvaluated = false
        }

        currentInput = resultText
        accumulator = result
        accumulatorToken = displayString(for: resultText)
        currentToken = displayString(for: resultText)
        updateDisplay()
    }

    private func appendHistory(expression: String, result: String) {
        let displayExpression = groupedExpressionString(expression)
        let displayResult = displayString(for: result)
        history.insert(
            HistoryEntry(
                expression: expression,
                result: result,
                displayExpression: displayExpression,
                displayResult: displayResult
            ),
            at: 0
        )
        trimToNewestEntries(&history, maxCount: Limits.maxStoredHistoryEntries)
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
            isExpressionMode: isExpressionMode
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
        trimToNewestEntries(&history, maxCount: Limits.maxStoredHistoryEntries)
        trimToNewestEntries(&memoryEntries, maxCount: Limits.maxStoredMemoryEntries)
        trimToRecentSnapshots(&undoStack, maxCount: Limits.maxUndoDepth)
        trimToRecentSnapshots(&redoStack, maxCount: Limits.maxRedoDepth)
    }

    private func currentOperationCopyString() -> String? {
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
        "\(expression) = \(result)"
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
    }

    private func makeExpressionPreview() -> String {
        guard let op = pendingOperator else { return "" }
        let lhsText = accumulatorToken ?? currentToken
        return "\(lhsText) \(op.symbol)"
    }

    private func updateDisplay() {
        display = displayString(for: currentInput)
        let header: String
        if isExpressionMode {
            header = expressionPreviewHeader()
            expression = header
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
        expressionDisplay = groupedExpressionString(header)
    }

    /// Attempt to extract a numeric string from pasted content, tolerating currency symbols and separators.
    private func normalizePastedNumber(_ raw: String) -> String? {
        if raw.isEmpty { return nil }

        // Keep only digits, separators, minus signs, and optional percent.
        let allowed = CharacterSet(charactersIn: "0123456789.,-% '\u{00A0}\u{202F}")
        var filtered = raw.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()

        if filtered.isEmpty { return nil }

        let digitCount = filtered.unicodeScalars.filter(CharacterSet.decimalDigits.contains).count
        guard digitCount <= Limits.maxInputDigits else { return nil }

        let hasPercent = filtered.contains("%")
        filtered = filtered.replacingOccurrences(of: "%", with: "")

        // Collapse multiple minus signs to a single leading one.
        if let firstMinus = filtered.firstIndex(of: "-") {
            filtered = "-" + filtered[filtered.index(after: firstMinus)...].replacingOccurrences(of: "-", with: "")
        } else {
            filtered = filtered.replacingOccurrences(of: "-", with: "")
        }

        // Decide decimal separator (last separator wins).
        let dotCount = filtered.filter { $0 == "." }.count
        let commaCount = filtered.filter { $0 == "," }.count
        let lastDot = filtered.lastIndex(of: ".")
        let lastComma = filtered.lastIndex(of: ",")

        if let lastComma = lastComma, let lastDot = lastDot {
            if lastComma > lastDot {
                // Comma likely decimal, dots as thousands.
                filtered = filtered.replacingOccurrences(of: ".", with: "")
                if let idx = filtered.lastIndex(of: ",") {
                    filtered.replaceSubrange(idx...idx, with: ".")
                }
            } else {
                // Dot likely decimal, commas as thousands.
                filtered = filtered.replacingOccurrences(of: ",", with: "")
            }
        } else if lastComma != nil {
            filtered = filtered.replacingOccurrences(of: ".", with: "")
            if commaCount > 1 || shouldTreatSingleSeparatorAsGrouping(filtered, separator: ",") {
                filtered = filtered.replacingOccurrences(of: ",", with: "")
            } else {
                filtered = filtered.replacingOccurrences(of: ",", with: ".")
            }
        } else if lastDot != nil {
            filtered = filtered.replacingOccurrences(of: ",", with: "")
            if dotCount > 1 || shouldTreatSingleSeparatorAsGrouping(filtered, separator: ".") {
                filtered = filtered.replacingOccurrences(of: ".", with: "")
            }
        } else {
            // Only dots or no separators: strip stray commas.
            filtered = filtered.replacingOccurrences(of: ",", with: "")
        }

        // Ensure only one decimal point remains.
        if let firstDot = filtered.firstIndex(of: ".") {
            let after = filtered[filtered.index(after: firstDot)...].replacingOccurrences(of: ".", with: "")
            filtered = String(filtered[..<filtered.index(after: firstDot)]) + after
        }

        // Validate
        guard var numericValue = parseStoredNumber(filtered) else { return nil }

        // Convert percent to decimal value.
        if hasPercent {
            numericValue = numericValue / 100
        }
        return decimalNumberString(from: numericValue)
    }

    private func parsePastedContent(_ raw: String) -> ParsedPasteContent {
        guard raw.count <= Limits.maxPasteCharacters else {
            return .value("")
        }
        let parts = raw.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let lhs = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if let steps = parseReplaySteps(lhs) {
                return .replay(steps + [.evaluate])
            }

            let rhs = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return .value(rhs.isEmpty ? lhs : rhs)
        }

        if let steps = parseReplaySteps(raw) {
            return .replay(steps)
        }

        return .value(raw)
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

        while index < raw.endIndex {
            let character = raw[index]
            if character.isNumber {
                hasDigits = true
                index = raw.index(after: index)
            } else if character == "." || character == "," || character == "'" || character.isWhitespace {
                index = raw.index(after: index)
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
              let value = parseStoredNumber(normalized) else {
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

        for character in unsignedFormatted {
            if character == "." {
                steps.append(.decimal)
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
        return roundedDecimal
    }

    private func format(_ value: Double) -> String {
        if value.isNaN { return "Error" }
        if value.isInfinite { return "∞" }
        if abs(value) < pow(10, Double(-Limits.maxInputDigits)) { return "0" }
        let roundedDecimal = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        if shouldUseScientificNotation(for: roundedDecimal) {
            return scientificString(fromRoundedDecimal: roundedDecimal)
        }
        return roundedDecimal
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
        shouldResetInputOnNextDigit = false
        justEvaluated = false
        isErrorState = false
        currentErrorKey = nil
        accumulatorToken = nil
        lastOperandToken = nil
        expressionTokens.removeAll()
        openParenthesisCount = 0
        isExpressionMode = false
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
    }

    private func setCurrentTokenToCurrentInput() {
        let formatted = displayString(for: currentInput)
        currentToken = boundedDisplayToken(formatted, fallback: formatted)
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
        numberFormatStyle = style
        refreshFormattedState()
    }

    public func setClassicPercentBehaviorEnabled(_ enabled: Bool) {
        usesClassicPercentBehavior = enabled
    }

    private var currentInputDigitCount: Int {
        significantDigitCount(in: currentInput)
    }

    private var pendingOperandShouldKeepPercentToken: Bool {
        pendingOperator != nil && accumulatorUsesStandalonePercentToken
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

        if usesClassicPercentBehavior {
            if justEvaluated {
                return currentValue * currentValue / 100
            }
            return 0
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
            setCurrentTokenToCurrentInput()
        }

        if let accumulator {
            accumulatorToken = displayString(for: format(accumulator))
        }

        if let lastOperand {
            lastOperandToken = displayString(for: format(lastOperand))
        }

        expressionTokens = expressionTokens.map { token in
            guard let normalized = normalizeDisplayNumberToken(token) else { return token }
            return displayString(for: normalized)
        }

        memoryEntries = memoryEntries.map {
            MemoryEntry(id: $0.id, value: $0.value, displayValue: displayString(for: format($0.value)))
        }

        history = history.map {
            HistoryEntry(
                expression: $0.expression,
                result: $0.result,
                displayExpression: groupedExpressionString($0.expression),
                displayResult: displayString(for: $0.result)
            )
        }

        updateDisplay()
    }

    private func boundedDisplayToken(_ proposed: String, fallback: String) -> String {
        proposed.count <= Limits.maxDisplayTokenLength ? proposed : fallback
    }

    private func parseStoredNumber(_ raw: String) -> Decimal? {
        decimalNumber(from: raw)?.decimalValue
    }

    private func displayString(for raw: String) -> String {
        guard let value = parseStoredNumber(raw) else { return raw }
        if shouldUseScientificNotation(for: raw) {
            return formatScientific(value)
        }
        let normalizedRaw: String
        if raw.localizedCaseInsensitiveContains("e") {
            normalizedRaw = formatter.string(from: NSDecimalNumber(decimal: value)) ?? raw
        } else {
            normalizedRaw = raw
        }
        return groupedNumberString(normalizedRaw)
    }

    private func shouldUseScientificNotation(for raw: String) -> Bool {
        guard usesScientificNotation else { return false }
        if raw == "0" { return false }
        let digitCount = significantDigitCount(in: raw)
        return raw.localizedCaseInsensitiveContains("e")
            || digitCount > Limits.maxInputDigits
            || requiresScientificNotationForSmallMagnitude(in: raw)
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
        let normalized = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")

        let decimal = NSDecimalNumber(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        return decimal == .notANumber ? nil : decimal
    }

    private func decimalValue(fromDisplayText raw: String) -> Decimal? {
        guard let normalized = normalizeDisplayNumberToken(raw) else { return nil }
        return parseStoredNumber(normalized)
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
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let numericTokenCharacters = CharacterSet(charactersIn: "0123456789.,-−+eE '\u{00A0}\u{202F}")
        guard trimmed.unicodeScalars.allSatisfy({ numericTokenCharacters.contains($0) }) else {
            return nil
        }

        if let exponentRange = trimmed.range(of: "e", options: [.caseInsensitive]) {
            let mantissa = String(trimmed[..<exponentRange.lowerBound])
            let exponent = String(trimmed[exponentRange.upperBound...])
            guard let normalizedMantissa = normalizePastedNumber(mantissa),
                  exponent.range(of: "^[+-]?\\d+$", options: .regularExpression) != nil else {
                return nil
            }
            return normalizedMantissa + "e" + exponent.lowercased()
        }

        return normalizePastedNumber(trimmed)
    }

    private func shouldTreatSingleSeparatorAsGrouping(_ filtered: String, separator: Character) -> Bool {
        guard let separatorIndex = filtered.firstIndex(of: separator), filtered.filter({ $0 == separator }).count == 1 else {
            return false
        }

        let digitsAfterSeparator = filtered[filtered.index(after: separatorIndex)...].unicodeScalars.filter(CharacterSet.decimalDigits.contains).count
        let totalDigits = filtered.unicodeScalars.filter(CharacterSet.decimalDigits.contains).count
        return digitsAfterSeparator == 3 && totalDigits > 3
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
