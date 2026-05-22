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

    public init(
        copy: @escaping () -> Void,
        copyOperation: @escaping () -> Void,
        canCopyOperation: Bool,
        paste: @escaping () -> Void,
        undo: @escaping () -> Void,
        redo: @escaping () -> Void,
        canUndo: Bool,
        canRedo: Bool,
        clear: @escaping () -> Void
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
    }
}

public struct CalculatorActionContextKey: FocusedValueKey {
    public typealias Value = CalculatorActionContext
}

public extension FocusedValues {
    var calculatorActions: CalculatorActionContext? {
        get { self[CalculatorActionContextKey.self] }
        set { self[CalculatorActionContextKey.self] = newValue }
    }
}