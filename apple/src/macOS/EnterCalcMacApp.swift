// apple/src/macOS/EnterCalcMacApp.swift
import SwiftUI
import AppKit
import EnterCalcCore

struct CalculatorActionContext {
    let copy: () -> Void
    let copyOperation: () -> Void
    let canCopyOperation: Bool
    let paste: () -> Void
    let undo: () -> Void
    let redo: () -> Void
    let canUndo: Bool
    let canRedo: Bool
    let clear: () -> Void
}

struct CalculatorActionContextKey: FocusedValueKey {
    typealias Value = CalculatorActionContext
}

extension FocusedValues {
    var calculatorActions: CalculatorActionContext? {
        get { self[CalculatorActionContextKey.self] }
        set { self[CalculatorActionContextKey.self] = newValue }
    }
}

@main
struct EnterCalcMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.calculatorActions) private var actionContext
    @AppStorage("settings.language") private var storedLanguageCode: String = defaultLocalizationSelectionCode

    init() {
        EnterCalcFont.registerIfNeeded()
    }

    private var storedLocalizationBundle: Bundle? {
        isDefaultLocalizationSelection(storedLanguageCode) ? nil : localizationBundle(for: storedLanguageCode)
    }

    private var aboutWindowTitle: String {
        MacAboutContent.aboutWindowTitle(bundle: storedLocalizationBundle)
    }

    var body: some Scene {
        WindowGroup("EnterCalc", id: "main") {
            CalculatorWindowView(viewModel: CalculatorViewModel())
                .frame(minWidth: 280, minHeight: 452)
        }
        .defaultSize(width: 280, height: 452)

        Window(aboutWindowTitle, id: "about") {
            MacAboutView()
                .environment(\.macLocalizationBundle, storedLocalizationBundle)
        }
        .defaultSize(width: 460, height: 320)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(aboutWindowTitle) {
                    openWindow(id: "about")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n")
            }

            CommandGroup(replacing: .pasteboard) {
                Button(localized("copy")) {
                    actionContext?.copy()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(actionContext == nil)

                Button(localized("paste")) {
                    actionContext?.paste()
                }
                .keyboardShortcut("v", modifiers: [.command])
                .disabled(actionContext == nil)
            }

            CommandGroup(after: .pasteboard) {
                Button(localized("history.copyOperation")) {
                    actionContext?.copyOperation()
                }
                .disabled(actionContext?.canCopyOperation != true)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    actionContext?.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(actionContext?.canUndo != true)

                Button("Redo") {
                    actionContext?.redo()
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
                .disabled(actionContext?.canRedo != true)
            }

            CommandGroup(after: .undoRedo) {
                Button("Clear") {
                    actionContext?.clear()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(actionContext == nil)

                Button("Clear (Cmd+Backspace)") {
                    actionContext?.clear()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(actionContext == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we behave as a regular app and become frontmost so key events route here.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let policy = NSApp.activationPolicy()
        DebugLog.emit("AppDelegate", "activationPolicy:\(policy.rawValue) isActive:\(NSApp.isActive)")
    }
}
