import SwiftUI

/// The plain button style, made reachable from the keyboard on the Mac (#164).
///
/// SwiftUI only lets a button take Tab focus when the system's Keyboard
/// navigation setting is on, and a plain-style button never draws a focus
/// ring. This style makes the button focusable whatever that setting, draws
/// the system's focus colour around it while it has focus, and presses it on
/// Space. Return is left alone: in EnterCalc it is always =.
///
/// On iPhone and iPad it is the plain style unchanged; Full Keyboard Access
/// draws its own focus and presses buttons itself.
public struct KeyboardPlainButtonStyle: PrimitiveButtonStyle {
    let cornerRadius: CGFloat
    /// The borderless style underneath rather than plain, for the panes'
    /// header buttons.
    let isBorderless: Bool

    public init(cornerRadius: CGFloat = 6, borderless: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isBorderless = borderless
    }

    public func makeBody(configuration: Configuration) -> some View {
        Group {
            if isBorderless {
                Button(configuration).buttonStyle(.borderless)
            } else {
                Button(configuration).buttonStyle(.plain)
            }
        }
        .modifier(KeyboardFocusRing(cornerRadius: cornerRadius, press: configuration.trigger))
    }
}

/// The focus ring and Space handling behind `KeyboardPlainButtonStyle`.
struct KeyboardFocusRing: ViewModifier {
    @Environment(\.keyboardNavigable) private var isNavigable
    let cornerRadius: CGFloat
    let press: () -> Void
    /// ← and →, for a slider.
    var decrement: (() -> Void)? = nil
    var increment: (() -> Void)? = nil

    #if os(macOS)
    @FocusState private var isFocused: Bool
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .focusable(isNavigable)
            // The ring below is the only focus indicator; a borderless
            // button would otherwise also fill itself.
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(.space) {
                press()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard let decrement else { return .ignored }
                decrement()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard let increment else { return .ignored }
                increment()
                return .handled
            }
            .overlay {
                // Inside the control's edge: keys clip themselves to their
                // shape, which would cut away a ring drawn outside it.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        #else
        content
        #endif
    }
}

extension View {
    /// Makes a control that is not a plain button, such as a menu, reachable
    /// with Tab on the Mac: it draws the focus ring and runs `action` on
    /// Space (#164). Does nothing on iPhone and iPad.
    public func keyboardPressable(cornerRadius: CGFloat = 6, action: @escaping () -> Void) -> some View {
        modifier(KeyboardFocusRing(cornerRadius: cornerRadius, press: action))
    }
}

extension View {
    /// Makes a slider reachable with Tab on the Mac, adjusted with ← and →
    /// (#164). Does nothing on iPhone and iPad.
    public func keyboardAdjustable(
        cornerRadius: CGFloat = 6,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardFocusRing(cornerRadius: cornerRadius, press: {}, decrement: decrement, increment: increment))
    }
}

/// The option after `value` in `options`, wrapping round: what Space chooses
/// on a pop-up menu reached with Tab (#164).
public func nextOption<T: Equatable>(after value: T, in options: [T]) -> T {
    guard let index = options.firstIndex(of: value), !options.isEmpty else { return options.first ?? value }
    return options[(index + 1) % options.count]
}

private struct KeyboardNavigableKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the keyboard-reachable controls inside can take Tab focus.
    public var keyboardNavigable: Bool {
        get { self[KeyboardNavigableKey.self] }
        set { self[KeyboardNavigableKey.self] = newValue }
    }
}

extension View {
    /// Takes the controls inside out of the Tab order, leaving them
    /// clickable: those outside an open pane (#145, #164).
    public func keyboardNavigable(_ isNavigable: Bool) -> some View {
        environment(\.keyboardNavigable, isNavigable)
    }
}
