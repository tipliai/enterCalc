import Foundation

// MARK: - Functions

/// A function that can be assigned to one of the configurable keys.
///
/// The set is deliberately open-ended: adding a case here, a presentation and
/// an accessibility label is all a new function needs to appear in the chooser.
/// Serialization is by `rawValue`, and unknown raw values are ignored on read,
/// so a build that does not know a newer function falls back to the slot
/// default rather than failing to load the whole assignment set.
public enum CalculatorFunctionKey: String, CaseIterable, Identifiable, Sendable {
    case undo
    case redo
    case toggleSign
    case currency
    case rounding
    case backspace
    case squareRoot
    case square
    case reciprocal
    case parentheses
    case percent

    public var id: String { rawValue }

    /// How a key draws itself. A function is either an SF Symbol or a literal
    /// glyph — never both — so the same function looks the same in the compact
    /// action row and on a full-size keypad key.
    public enum Presentation: Equatable, Sendable {
        /// SF Symbol name.
        case symbol(String)
        /// Literal glyph drawn as text.
        case text(String)
        /// The user's configured currency symbol, which is not known statically.
        case currencySymbol
    }

    public var presentation: Presentation {
        switch self {
        case .undo: return .symbol("arrow.uturn.backward")
        case .redo: return .symbol("arrow.uturn.forward")
        case .toggleSign: return .symbol("plusminus")
        case .currency: return .currencySymbol
        case .rounding: return .symbol("slider.horizontal.below.rectangle")
        case .backspace: return .symbol("delete.left")
        case .squareRoot: return .text("√x")
        case .square: return .text("x²")
        case .reciprocal: return .text("1/x")
        case .parentheses: return .text("( )")
        case .percent: return .text("%")
        }
    }

    /// Localization key for the VoiceOver label. The first six reuse the keys
    /// the action row already shipped with, so existing translations carry over.
    public var accessibilityLabelKey: String {
        switch self {
        case .undo: return "undo"
        case .redo: return "redo"
        case .toggleSign: return "toggleSign"
        case .currency: return "calculator.currency.toggle"
        case .rounding: return "rounding.toggle"
        case .backspace: return "backspace"
        case .squareRoot: return "function.squareRoot"
        case .square: return "function.square"
        case .reciprocal: return "function.reciprocal"
        case .parentheses: return "function.parentheses"
        case .percent: return "function.percent"
        }
    }

    /// Whether the key stays usable while the calculator is showing an error.
    /// Mirrors the existing keypad rule: only clearing, editing and grouping
    /// keys survive an error; anything that would compute does not.
    public var isEnabledInErrorState: Bool {
        switch self {
        case .undo, .redo, .backspace, .parentheses:
            return true
        case .toggleSign, .currency, .rounding, .squareRoot, .square, .reciprocal, .percent:
            return false
        }
    }

    /// Order the chooser presents. Kept explicit rather than relying on
    /// declaration order so the grid can be rearranged without touching
    /// persistence.
    public static let chooserOrder: [CalculatorFunctionKey] = [
        .undo, .redo, .toggleSign, .currency,
        .rounding, .backspace, .parentheses, .percent,
        .squareRoot, .square, .reciprocal
    ]
}

// MARK: - Slots

/// A key whose function the user can reassign.
///
/// `action1`–`action6` are the compact action row above the keypad;
/// `parenthesesKey` and `percentKey` are the two large keypad keys called out
/// in the issue. Raw values are the persistence identifiers.
public enum CalculatorFunctionSlot: String, CaseIterable, Identifiable, Sendable {
    case action1
    case action2
    case action3
    case action4
    case action5
    case action6
    case parenthesesKey
    case percentKey

    public var id: String { rawValue }

    public var defaultFunction: CalculatorFunctionKey {
        switch self {
        case .action1: return .undo
        case .action2: return .redo
        case .action3: return .toggleSign
        case .action4: return .currency
        case .action5: return .rounding
        case .action6: return .backspace
        case .parenthesesKey: return .parentheses
        case .percentKey: return .percent
        }
    }

    /// The compact row, in display order.
    public static let actionRowSlots: [CalculatorFunctionSlot] = [
        .action1, .action2, .action3, .action4, .action5, .action6
    ]
}

// MARK: - Assignments

/// Which function sits in each configurable slot, for one calculator page.
///
/// Only slots that differ from their default are stored, so changing a default
/// in a later release reaches users who never customised that slot.
public struct CalculatorFunctionKeyAssignments: Equatable, Sendable {
    private var overrides: [CalculatorFunctionSlot: CalculatorFunctionKey]

    public static let `default` = CalculatorFunctionKeyAssignments()

    public init() {
        self.overrides = [:]
    }

    public init(overrides: [CalculatorFunctionSlot: CalculatorFunctionKey]) {
        self.overrides = overrides.filter { $0.key.defaultFunction != $0.value }
    }

    public subscript(slot: CalculatorFunctionSlot) -> CalculatorFunctionKey {
        overrides[slot] ?? slot.defaultFunction
    }

    public var isDefault: Bool { overrides.isEmpty }

    /// The slot currently holding `function`, if any.
    public func slot(for function: CalculatorFunctionKey) -> CalculatorFunctionSlot? {
        CalculatorFunctionSlot.allCases.first { self[$0] == function }
    }

    /// Puts `function` in `slot`. If it already occupies another slot the two
    /// trade places, so a function is never duplicated and never silently lost
    /// — the displaced one lands where the chosen one came from.
    public mutating func assign(_ function: CalculatorFunctionKey, to slot: CalculatorFunctionSlot) {
        let displaced = self[slot]
        guard displaced != function else { return }

        if let occupied = self.slot(for: function) {
            setFunction(displaced, for: occupied)
        }

        setFunction(function, for: slot)
    }

    public mutating func reset() {
        overrides.removeAll()
    }

    private mutating func setFunction(_ function: CalculatorFunctionKey, for slot: CalculatorFunctionSlot) {
        if slot.defaultFunction == function {
            overrides.removeValue(forKey: slot)
        } else {
            overrides[slot] = function
        }
    }
}

// MARK: - Serialization

extension CalculatorFunctionKeyAssignments {
    /// `slot=function` pairs joined by `;`, sorted so the stored string is
    /// stable and settings comparisons do not churn.
    public var serialized: String {
        overrides
            .map { "\($0.key.rawValue)=\($0.value.rawValue)" }
            .sorted()
            .joined(separator: ";")
    }

    /// Parses `serialized`. Malformed, unknown or duplicated entries are
    /// dropped rather than rejected, so a stored value written by a newer
    /// build still yields a usable set here.
    public init(serialized: String?) {
        guard let serialized, !serialized.isEmpty else {
            self.init()
            return
        }

        var parsed: [CalculatorFunctionSlot: CalculatorFunctionKey] = [:]
        var claimed: Set<CalculatorFunctionKey> = []

        for entry in serialized.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let slot = CalculatorFunctionSlot(rawValue: String(parts[0])),
                  let function = CalculatorFunctionKey(rawValue: String(parts[1])),
                  parsed[slot] == nil,
                  !claimed.contains(function) else { continue }

            parsed[slot] = function
            claimed.insert(function)
        }

        // A stored override can collide with another slot's *default* — e.g.
        // `action1=backspace` while action6 still defaults to backspace. Push
        // the defaulted slot out of the way so the invariant "no function
        // appears twice" holds for what is actually shown.
        for slot in CalculatorFunctionSlot.allCases where parsed[slot] == nil {
            if claimed.contains(slot.defaultFunction) {
                let replacement = CalculatorFunctionSlot.allCases
                    .map(\.defaultFunction)
                    .first { !claimed.contains($0) }
                if let replacement {
                    parsed[slot] = replacement
                    claimed.insert(replacement)
                }
            } else {
                claimed.insert(slot.defaultFunction)
            }
        }

        self.init(overrides: parsed)
    }
}
