import Foundation
import Combine

// MARK: - Saved preset edits

/// The preset buttons a person has changed by long-pressing them (#124).
///
/// Stored per slot, on top of whatever the defaults are (the region's VAT rates,
/// or the tip presets), so an untouched slot still follows its default if the
/// defaults change. Serialised as `slot=rate` pairs, e.g. `"0=8.1;2=12"`.
public struct RatePresetOverrides: Equatable, Sendable {
    public private(set) var rates: [Int: Decimal]

    public init(rates: [Int: Decimal] = [:]) {
        self.rates = rates
    }

    /// Parses a stored value, skipping anything malformed rather than failing.
    public init(serialized: String?) {
        var rates: [Int: Decimal] = [:]
        for pair in (serialized ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let slot = Int(parts[0]), slot >= 0,
                  let rate = RateEntry.strictDecimal(String(parts[1])),
                  rate >= 0, rate < RateEntry.limit else { continue }
            rates[slot] = rate
        }
        self.rates = rates
    }

    public var serialized: String {
        rates.keys.sorted()
            .map { "\($0)=\(RateEntry.canonicalText(for: rates[$0]!))" }
            .joined(separator: ";")
    }

    /// The presets to show: the defaults with each edited slot replaced. Edits
    /// for slots the defaults no longer have are ignored.
    public func applied(to defaults: [Decimal]) -> [Decimal] {
        defaults.enumerated().map { rates[$0.offset] ?? $0.element }
    }

    public func isEdited(_ slot: Int) -> Bool {
        rates[slot] != nil
    }

    /// Sets a slot, or restores its default when `rate` is `nil` or equal to it.
    public mutating func set(_ rate: Decimal?, forSlot slot: Int, default defaultRate: Decimal?) {
        if let rate, rate != defaultRate {
            rates[slot] = rate
        } else {
            rates.removeValue(forKey: slot)
        }
    }
}

/// What a VAT or Tip panel shows in its preset row: the defaults, any slots
/// the person has changed, and the separator to type with.
public struct RatePresets: Equatable, Sendable {
    public let defaults: [Decimal]
    public let overrides: RatePresetOverrides
    public let decimalSeparator: String

    public init(defaults: [Decimal], overrides: RatePresetOverrides, decimalSeparator: String) {
        self.defaults = defaults
        self.overrides = overrides
        self.decimalSeparator = decimalSeparator
    }

    public var rates: [Decimal] { overrides.applied(to: defaults) }
}

// MARK: - Editing session

/// Drives typing a rate on the VAT and Tip panels' number pad (#124).
///
/// The platform owns one and passes it to the panel, so its hardware-keyboard
/// handling can forward keys here while an edit is open instead of typing into
/// the calculator. The panel starts an edit with the closures that apply it;
/// the editor keeps the entry valid and reports each keystroke live.
@MainActor
public final class RateEditor: ObservableObject {
    public enum Target: Equatable, Sendable {
        /// The rate in use, from tapping it.
        case rate
        /// A preset button, from long-pressing it.
        case preset(Int)
    }

    public enum Key: Equatable, Sendable {
        case digit(Int)
        case decimalSeparator
        case backspace
        case done
        case cancel
    }

    @Published public private(set) var target: Target?
    @Published public private(set) var entry = RateEntry(editing: 0)

    private var onLive: ((Decimal) -> Void)?
    private var onCommit: ((Decimal) -> Void)?
    private var onCancel: (() -> Void)?

    public init() {}

    public var isEditing: Bool { target != nil }

    /// Opens an edit of `value`. `onLive` runs on every keystroke that leaves a
    /// number, `onCommit` with the final rate on Done, and `onCancel` when the
    /// edit is abandoned (Escape, or Done with nothing typed).
    public func begin(
        _ target: Target,
        value: Decimal,
        onLive: @escaping (Decimal) -> Void,
        onCommit: @escaping (Decimal) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        entry = RateEntry(editing: value)
        self.onLive = onLive
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public func press(_ key: Key) {
        guard isEditing else { return }

        switch key {
        case .digit(let digit):
            guard entry.appendDigit(digit) else { return }
        case .decimalSeparator:
            guard entry.appendDecimalSeparator() else { return }
        case .backspace:
            entry.backspace()
        case .done:
            if let value = entry.value {
                let commit = onCommit
                close()
                commit?(value)
            } else {
                cancel()
            }
            return
        case .cancel:
            cancel()
            return
        }

        if let value = entry.value {
            onLive?(value)
        }
    }

    /// Takes the text of the rate field. Returns `false`, changing nothing, when
    /// the text is not a valid rate, so the field can put back what it had.
    @discardableResult
    public func setTypedText(_ raw: String, decimalSeparator: String, notifyingLive: Bool = true) -> Bool {
        guard isEditing, let typed = RateEntry(typed: raw, decimalSeparator: decimalSeparator) else { return false }
        entry = typed
        if notifyingLive, let value = typed.value {
            onLive?(value)
        }
        return true
    }

    /// Abandons the edit without applying it, e.g. when the panel closes.
    public func cancel() {
        guard isEditing else { return }
        let cancel = onCancel
        close()
        cancel?()
    }

    private func close() {
        target = nil
        onLive = nil
        onCommit = nil
        onCancel = nil
    }
}

// MARK: - Stored preferences

/// Where the VAT and Tip panels keep their rates and edited presets, shared by
/// iOS and macOS so both read and write the same values (#124).
public enum RateToolPreferences {
    public static let vatRateKey = "settings.vat.rate"
    public static let vatPresetOverridesKey = "settings.vat.presetOverrides"
    public static let tipRateKey = "settings.tip.rate"
    public static let tipPresetOverridesKey = "settings.tip.presetOverrides"

    /// The stored rate, or `fallback` while none has been chosen yet.
    public static func rate(fromStored text: String, fallback: Decimal) -> Decimal {
        guard !text.isEmpty,
              let rate = RateEntry.strictDecimal(text),
              rate >= 0, rate < RateEntry.limit else { return fallback }
        return rate
    }

    public static func storedText(for rate: Decimal) -> String {
        RateEntry.canonicalText(for: rate)
    }

    /// The default tip rate, as before #124.
    public static let defaultTipRate: Decimal = 18
}
