import Foundation

/// What VoiceOver says for the calculator display, and what it announces when
/// the display changes (#145).
///
/// The display is one element: label "Result", value the number on screen and,
/// when there is one, the operation it came from or is part of. Operators are
/// spoken as words ("plus", "divided by") rather than left to the speech
/// engine's reading of the glyphs, which varies by voice and punctuation
/// setting. Numbers, grouping separators and currency symbols are left as they
/// are: VoiceOver already reads "$1,234.50" as an amount.
///
/// Everything here is plain text in, plain text out, so both apps share it and
/// it is unit tested. `localize` looks a key up in the language the window is
/// showing.
public enum DisplaySpeech {
    /// The parts of the display that speech and announcements depend on.
    public struct State: Equatable {
        public var display: String
        public var operation: String
        public var isError: Bool
        public var completedCalculations: Int
        /// The decimal separator the display uses ("." or ",").
        public var decimalSeparator: String
        /// The display is a result rounded to fit its 16 digits, so a closing
        /// run of one digit really does go on.
        public var isRoundedResult: Bool
        /// Bumped by AC, which is announced however little was on screen.
        public var allClearCount: Int

        public init(
            display: String,
            operation: String,
            isError: Bool,
            completedCalculations: Int,
            decimalSeparator: String = ".",
            isRoundedResult: Bool = false,
            allClearCount: Int = 0
        ) {
            self.display = display
            self.operation = operation
            self.isError = isError
            self.completedCalculations = completedCalculations
            self.decimalSeparator = decimalSeparator
            self.isRoundedResult = isRoundedResult
            self.allClearCount = allClearCount
        }
    }

    public enum Announcement: Equatable {
        /// A calculation finished; carries the spoken result.
        case result(String)
        /// The calculation ended in an error; carries the error message.
        case error(String)
        /// AC cleared a calculation.
        case cleared
    }

    public static let labelKey = "a11y.display.label"
    public static let hintKey = "a11y.display.hint"

    /// Operator glyphs and the keys for the words spoken in their place.
    /// Longest first is not needed: every glyph is one character.
    private static let operatorWords: [Character: String] = [
        "+": "a11y.operator.plus",
        "−": "a11y.operator.minus",
        "×": "a11y.operator.times",
        "÷": "a11y.operator.dividedBy",
        "=": "a11y.operator.equals",
        "≈": "a11y.operator.approximately",
        "%": "a11y.operator.percent",
        "√": "a11y.operator.squareRoot"
    ]

    /// The text with operator glyphs replaced by words, decimals read digit
    /// by digit, and spacing tidied.
    public static func spoken(
        _ text: String,
        decimalSeparator: String = ".",
        isRoundedResult: Bool = false,
        localize: (String) -> String
    ) -> String {
        var pieces: [String] = []
        var current = ""
        let characters = Array(text)
        // Amounts keep their currency reading ("$9.50" is dollars and cents),
        // wherever the symbol sits ("9,50 €" has it after a space), as long as
        // they have no more decimals than cents. "$81.2154789" is read digit
        // by digit like any other long decimal.
        let currencySymbol = text.first(where: \.isCurrencySymbol)
        let isAmount = currencySymbol != nil
        // Set once "$0.71" has become "71 cents", so a symbol standing on its
        // own ("0,71 €") is not read after it.
        var saidSubunits = false

        func flush() {
            if !current.isEmpty {
                if let currencySymbol,
                   let subunits = spokenSubunits(current, symbol: currencySymbol, decimalSeparator: decimalSeparator, localize: localize) {
                    pieces.append(subunits)
                    saidSubunits = true
                } else {
                    let keepsAmountReading = isAmount
                        && fractionDigitCount(of: current, decimalSeparator: decimalSeparator) <= maximumCentsDigits
                    pieces.append(keepsAmountReading ? current : spokenNumber(
                        current,
                        decimalSeparator: decimalSeparator,
                        isRoundedResult: isRoundedResult,
                        localize: localize
                    ))
                }
                current = ""
            }
        }

        for (index, character) in characters.enumerated() {
            if let key = operatorWords[character] {
                flush()
                pieces.append(localize(key))
            } else if character == "-", isMinusSign(at: index, in: characters) {
                flush()
                pieces.append(localize("a11y.operator.minus"))
            } else if character.isWhitespace, !isGroupingSpace(at: index, in: characters) {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()

        return pieces
            .filter { !$0.isEmpty && !(saidSubunits && $0.allSatisfy(\.isCurrencySymbol)) }
            .joined(separator: " ")
    }

    /// An amount from a currency panel ("$0.40", "1.234,56 €"), whose
    /// decimal separator is not passed along: it is the last "." or ","
    /// when one or two digits follow it.
    public static func spokenAmount(_ text: String, localize: (String) -> String) -> String {
        let separator: String
        if let index = text.lastIndex(where: { $0 == "." || $0 == "," }) {
            let digitsAfter = text[text.index(after: index)...].prefix { $0.isASCII && $0.isNumber }.count
            separator = digitsAfter <= maximumCentsDigits ? String(text[index]) : (text[index] == "." ? "," : ".")
        } else {
            separator = "."
        }
        return spoken(text, decimalSeparator: separator, localize: localize)
    }

    /// The keys for "71 cents" / "1 cent" by currency symbol. Currencies not
    /// listed keep the speech engine's own reading.
    private static let subunitKeys: [Character: (one: String, many: String)] = [
        "$": ("a11y.currency.cent", "a11y.currency.cents"),
        "€": ("a11y.currency.cent", "a11y.currency.cents"),
        "£": ("a11y.currency.penny", "a11y.currency.pence")
    ]

    /// An amount under one unit read as its cents, "$0.71" as "71 cents",
    /// rather than "zero dollars point seven one". Nil for anything else.
    static func spokenSubunits(
        _ token: String,
        symbol: Character,
        decimalSeparator: String,
        localize: (String) -> String
    ) -> String? {
        guard let keys = subunitKeys[symbol],
              let separator = decimalSeparator.first else {
            return nil
        }
        let body = token.filter { !$0.isCurrencySymbol }
        guard let separatorIndex = body.firstIndex(of: separator) else { return nil }
        let whole = body[..<separatorIndex]
        let fraction = body[body.index(after: separatorIndex)...]
        guard !whole.isEmpty, whole.allSatisfy({ $0 == "0" }),
              (1...maximumCentsDigits).contains(fraction.count),
              fraction.allSatisfy({ $0.isASCII && $0.isNumber }),
              let count = Int(fraction.padding(toLength: maximumCentsDigits, withPad: "0", startingAt: 0)),
              count > 0 else {
            return nil
        }
        return count == 1 ? localize(keys.one) : format(localize(keys.many), String(count))
    }

    /// The display's accessibility value.
    ///
    /// - A finished calculation: "12, from 5 plus 7".
    /// - One in progress: "7, after 5 plus".
    /// - Nothing pending, or an error: just what the display shows.
    public static func value(for state: State, localize: (String) -> String) -> String {
        let result = spokenDisplay(state, localize: localize)
        let operation = state.operation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !state.isError, !operation.isEmpty else {
            return result
        }

        if let last = operation.last, last == "=" || last == "≈" {
            let source = spoken(String(operation.dropLast()), decimalSeparator: state.decimalSeparator, localize: localize)
            guard !source.isEmpty else { return result }
            return format(localize("a11y.display.completed"), result, source)
        }

        return format(
            localize("a11y.display.pending"),
            result,
            spoken(operation, decimalSeparator: state.decimalSeparator, localize: localize)
        )
    }

    /// The number on the display, as VoiceOver should say it.
    public static func spokenDisplay(_ state: State, localize: (String) -> String) -> String {
        spoken(
            state.display,
            decimalSeparator: state.decimalSeparator,
            isRoundedResult: state.isRoundedResult,
            localize: localize
        )
    }

    /// What to announce when the display goes from `old` to `new`, if anything.
    ///
    /// Only changes someone using VoiceOver could miss are announced: their
    /// focus is on the key they pressed, not on the display.
    public static func announcement(from old: State, to new: State, localize: (String) -> String) -> Announcement? {
        if new.isError, !old.isError || old.display != new.display {
            return .error(new.display)
        }

        if new.completedCalculations > old.completedCalculations, !new.isError {
            return .result(spokenDisplay(new, localize: localize))
        }

        // AC says "Cleared" however little was on screen; backspacing to
        // zero is editing, not clearing.
        if new.allClearCount > old.allClearCount {
            return .cleared
        }

        return nil
    }

    /// The words for an announcement.
    public static func text(for announcement: Announcement, localize: (String) -> String) -> String {
        switch announcement {
        case .result(let spokenResult):
            return format(localize("a11y.announce.result"), spokenResult)
        case .error(let message):
            return message
        case .cleared:
            return localize("a11y.announce.cleared")
        }
    }

    /// What to say after an action key (Undo, Currency, ±...): its name and
    /// what the display now shows, "Undo, 2 displayed", since the action's
    /// effect is otherwise silent.
    public static func actionAnnouncement(_ actionName: String, state: State, localize: (String) -> String) -> String {
        let shown = state.isError ? state.display : spokenDisplay(state, localize: localize)
        return format(localize("a11y.announce.action"), actionName, shown)
    }

    /// What to say on arriving at another calculator, a screen on iPhone and
    /// iPad or a window on the Mac (#145): its number and what it shows.
    /// "Screen 2, 500 point 1 1 3 shown".
    public static func instanceAnnouncement(
        number: Int,
        isWindow: Bool,
        state: State,
        localize: (String) -> String
    ) -> String {
        let shown = state.isError ? state.display : spokenDisplay(state, localize: localize)
        return format(localize(isWindow ? "a11y.announce.window" : "a11y.announce.screen"), String(number), shown)
    }

    /// The word for a key that was just pressed, for speaking it on the Mac
    /// where VoiceOver's focus is not on the key (#145). `key` is a keypad
    /// key's title or a typed character.
    ///
    /// Enter and AC return nil: the result and "Cleared" are announced
    /// instead, so the key's own word would only be talked over.
    public static func spokenKey(_ key: String, localize: (String) -> String) -> String? {
        switch key {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return key
        case ".", ",":
            return localize("a11y.key.point")
        case "+":
            return localize("a11y.operator.plus")
        case "-", "−":
            return localize("a11y.operator.minus")
        case "*", "x", "X", "×":
            return localize("a11y.operator.times")
        case "/", "÷":
            return localize("a11y.operator.dividedBy")
        case "%":
            return localize("a11y.operator.percent")
        case "√":
            return localize("a11y.operator.squareRoot")
        case "(":
            return localize("a11y.key.openParenthesis")
        case ")":
            return localize("a11y.key.closeParenthesis")
        case "( )":
            return localize("a11y.key.parentheses")
        case "C":
            return localize("a11y.key.clear")
        default:
            return nil
        }
    }

    /// Amounts with up to this many decimals keep their currency reading.
    static let maximumCentsDigits = 2

    static func fractionDigitCount(of token: String, decimalSeparator: String) -> Int {
        guard let separator = decimalSeparator.first,
              let index = token.lastIndex(of: separator) else {
            return 0
        }
        return token[token.index(after: index)...].prefix { $0.isASCII && $0.isNumber }.count
    }

    /// How many times a repeating digit is read before "repeating".
    static let repeatedDigitReadCount = 3

    /// A decimal read the way people say one: the whole part as a number and
    /// each decimal digit on its own, so "3.1415" is "3 point 1 4 1 5" rather
    /// than "3 point 1 thousand 4 hundred...". When the decimals end in a run
    /// of one digit, it is read three times and then "repeating", the usual
    /// spoken form of a repeating decimal: "9.333333333333333" is "9 point
    /// 3 3 3 repeating". That is only for a number cut off at the display's
    /// precision; "3.2222225" is read digit by digit, since its 2s stop.
    ///
    /// Anything that is not a decimal is returned unchanged. (`spoken` leaves
    /// amounts with a currency symbol alone, so "$9.50" stays dollars and
    /// cents.)
    static func spokenNumber(
        _ token: String,
        decimalSeparator: String,
        isRoundedResult: Bool = false,
        localize: (String) -> String
    ) -> String {
        guard let separator = decimalSeparator.first,
              let separatorIndex = token.lastIndex(of: separator) else {
            return token
        }

        let whole = token[..<separatorIndex]
        let afterSeparator = token[token.index(after: separatorIndex)...]
        let fraction = Array(afterSeparator.prefix { $0.isASCII && $0.isNumber })
        let rest = afterSeparator.dropFirst(fraction.count)
        guard whole.contains(where: \.isNumber), !fraction.isEmpty else {
            return token
        }

        var words = [String(whole), localize("a11y.key.point")]
        let fillsDisplayPrecision = significantDigitCount(whole: whole, fraction: fraction) >= displayPrecisionDigits
        if isRoundedResult, fillsDisplayPrecision, let runStart = repeatingRunStart(in: fraction) {
            words += fraction[..<runStart].map(String.init)
            words += Array(repeating: String(fraction[runStart]), count: repeatedDigitReadCount)
            words.append(localize("a11y.number.repeating"))
        } else {
            words += fraction.map(String.init)
        }
        if !rest.isEmpty {
            words.append(String(rest))
        }
        return words.joined(separator: " ")
    }

    /// The calculator shows at most this many significant digits, so a
    /// repeating decimal is cut off there (#145). A number with fewer digits
    /// is exactly what it shows, however many of one digit it ends with.
    static let displayPrecisionDigits = 16

    static func significantDigitCount(whole: Substring, fraction: [Character]) -> Int {
        let digits = whole.filter { $0.isASCII && $0.isNumber } + String(fraction)
        return digits.drop { $0 == "0" }.count
    }

    /// Where the decimals' closing run of one digit starts, when that run is
    /// longer than the three digits that get read, so saying "repeating" leaves
    /// something out. Only called for a number cut off at the display's
    /// precision. Its last digit may have been rounded up, as in
    /// "0.6666666666666667", so it can be one more than the run's digit, but
    /// nothing else: "3.2222222222222225" does not repeat.
    static func repeatingRunStart(in fraction: [Character]) -> Int? {
        guard let lastDigit = fraction.last?.wholeNumberValue else { return nil }
        var digits = fraction
        if digits.count > 1,
           let runDigit = digits[digits.count - 2].wholeNumberValue,
           lastDigit == runDigit + 1 {
            digits.removeLast()
        }
        let last = digits[digits.count - 1]
        // A run of zeros is the end of the number, not a repetition, and
        // dropping a rounded last digit there would lose it: 1.000000000000001.
        guard last != "0" else { return nil }
        var start = digits.count - 1
        while start > 0, digits[start - 1] == last {
            start -= 1
        }
        return digits.count - start > repeatedDigitReadCount ? start : nil
    }

    // A space between two digits groups thousands ("1 000,50" in French), so
    // it belongs to the number rather than ending it.
    private static func isGroupingSpace(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0, index + 1 < characters.count else { return false }
        return characters[index - 1].isNumber && characters[index + 1].isNumber
    }

    // A hyphen is a minus sign when it starts a number: at the start, or after
    // a space or an opening parenthesis. Inside "1e-5" it is part of the number.
    private static func isMinusSign(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return previous.isWhitespace || previous == "("
    }

    private static func format(_ template: String, _ arguments: String...) -> String {
        String(format: template, arguments: arguments.map { $0 as CVarArg })
    }
}

extension CalculatorViewModel {
    /// The display as `DisplaySpeech` sees it.
    public var displaySpeechState: DisplaySpeech.State {
        DisplaySpeech.State(
            display: display,
            operation: expressionDisplay,
            isError: isErrorState,
            completedCalculations: completedCalculationCount,
            decimalSeparator: numberFormatStyle.decimalSeparator,
            isRoundedResult: isDisplayRoundedResult,
            allClearCount: allClearCount
        )
    }
}
