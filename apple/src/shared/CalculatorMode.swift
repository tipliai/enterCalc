import SwiftUI

/// The calculator's modes, chosen from the mode name in the display (#142).
///
/// Currency mode is still derived state: the calculator is in it exactly when
/// a currency symbol is showing. Choosing a mode just enters or leaves that
/// state through the same undoable view-model calls the currency key uses.
/// New modes (Scientific, #135) add a case here and appear in every picker and
/// menu automatically.
public enum CalculatorMode: String, CaseIterable, Identifiable, Sendable {
    case basic
    case currency

    public var id: String { rawValue }

    public static func current(for viewModel: CalculatorViewModel) -> CalculatorMode {
        viewModel.activeCurrencySymbol == nil ? .basic : .currency
    }

    public var localizationKey: String {
        switch self {
        case .basic: return "calculator.mode.basic"
        case .currency: return "calculator.mode.currency"
        }
    }

    public var systemImage: String {
        switch self {
        case .basic: return "plus.forwardslash.minus"
        case .currency: return "banknote"
        }
    }

    /// The ⌘-number that selects this mode from the menu bar or an iPad keyboard.
    public var shortcutNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// Switches `viewModel` into this mode. `currencySymbol` is the page's
    /// configured symbol, used when entering Currency mode. Choosing the mode
    /// already showing does nothing.
    public func select(on viewModel: CalculatorViewModel, currencySymbol: String) {
        guard Self.current(for: viewModel) != self else { return }
        switch self {
        case .basic:
            viewModel.clearCurrencySymbol()
        case .currency:
            viewModel.inputCurrencySymbol(currencySymbol)
        }
    }
}

/// How a mode's controls (VAT and TIP today; Deg/Rad and the like later)
/// appear and disappear: a short fade rather than a pop (#150). A plain dissolve
/// is fine under Reduce Motion, so it is kept there too.
public enum ModeControlsTransition {
    public static let animation: Animation = .easeInOut(duration: 0.2)
}

public extension View {
    /// Fades this mode control in and out as its mode is entered and left.
    func modeControlTransition() -> some View {
        transition(.opacity)
    }
}

/// The Mode submenu's items for the menu bar (macOS) and the iPad View menu:
/// one checkable item per mode, ⌘1, ⌘2, …, acting on the focused page.
public struct ModeMenuItems: View {
    private let context: CalculatorActionContext?
    private let title: (CalculatorMode) -> String

    public init(context: CalculatorActionContext?, title: @escaping (CalculatorMode) -> String) {
        self.context = context
        self.title = title
    }

    public var body: some View {
        ForEach(CalculatorMode.allCases) { mode in
            Toggle(isOn: Binding(
                get: { context?.currentMode == mode },
                set: { _ in context?.selectMode?(mode) }
            )) {
                Label(title(mode), systemImage: mode.systemImage)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(mode.shortcutNumber))), modifiers: .command)
            .disabled(context?.selectMode == nil)
        }
    }
}
