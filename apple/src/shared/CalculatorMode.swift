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
    /// Fades a mode's controls in and out as the mode is entered and left.
    ///
    /// The controls stay mounted and only their opacity changes, so they stop
    /// taking clicks, keyboard focus and VoiceOver focus the moment the mode
    /// is left, rather than lingering as a removed view while it fades out.
    func modeControl(visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .disabled(!visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .modeControlsAnimation(value: visible)
    }

    /// Animates changes to `value` with the mode-controls fade.
    ///
    /// Under Reduce Motion the iOS app disables animations for its whole
    /// window, which would turn this fade back into a pop. A dissolve has no
    /// movement, so this re-enables it, scoped to changes of `value` alone.
    func modeControlsAnimation<Value: Equatable>(value: Value) -> some View {
        transaction(value: value) { transaction in
            transaction.disablesAnimations = false
            transaction.animation = ModeControlsTransition.animation
        }
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
