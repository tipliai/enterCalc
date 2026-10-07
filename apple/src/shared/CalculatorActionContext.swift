import SwiftUI

public struct CalculatorActionContext {
    public let copy: () -> Void
    public let copyOperation: () -> Void
    public let canCopyOperation: Bool
    public let paste: () -> Void
    public let undo: () -> Void
    public let redo: () -> Void
    public let canUndo: Bool
    public let canRedo: Bool
    public let clear: () -> Void
    public let clearAll: () -> Void
    // iPad-only View menu actions. Routed through the focused scene so a
    // keyboard shortcut acts only on the focused window; nil where the
    // platform does not offer them (macOS).
    public let toggleHistoryPanel: (() -> Void)?
    public let toggleRoundingPanel: (() -> Void)?
    public let growDisplayArea: (() -> Void)?
    public let shrinkDisplayArea: (() -> Void)?
    public let goToNextScreen: (() -> Void)?
    public let goToPreviousScreen: (() -> Void)?

    public init(
        copy: @escaping () -> Void,
        copyOperation: @escaping () -> Void,
        canCopyOperation: Bool,
        paste: @escaping () -> Void,
        undo: @escaping () -> Void,
        redo: @escaping () -> Void,
        canUndo: Bool,
        canRedo: Bool,
        clear: @escaping () -> Void,
        clearAll: @escaping () -> Void,
        toggleHistoryPanel: (() -> Void)? = nil,
        toggleRoundingPanel: (() -> Void)? = nil,
        growDisplayArea: (() -> Void)? = nil,
        shrinkDisplayArea: (() -> Void)? = nil,
        goToNextScreen: (() -> Void)? = nil,
        goToPreviousScreen: (() -> Void)? = nil
    ) {
        self.copy = copy
        self.copyOperation = copyOperation
        self.canCopyOperation = canCopyOperation
        self.paste = paste
        self.undo = undo
        self.redo = redo
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.clear = clear
        self.clearAll = clearAll
        self.toggleHistoryPanel = toggleHistoryPanel
        self.toggleRoundingPanel = toggleRoundingPanel
        self.growDisplayArea = growDisplayArea
        self.shrinkDisplayArea = shrinkDisplayArea
        self.goToNextScreen = goToNextScreen
        self.goToPreviousScreen = goToPreviousScreen
    }
}

private struct CalculatorActionContextKey: FocusedValueKey {
    typealias Value = CalculatorActionContext
}

public extension FocusedValues {
    var calculatorActions: CalculatorActionContext? {
        get { self[CalculatorActionContextKey.self] }
        set { self[CalculatorActionContextKey.self] = newValue }
    }
}