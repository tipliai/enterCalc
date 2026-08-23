// apple/src/macOS/EnterCalcMacApp.swift
import SwiftUI
import AppKit
import EnterCalcCore

extension Notification.Name {
    static let enterCalcGrowDisplayArea = Notification.Name("EnterCalc.macOS.GrowDisplayArea")
    static let enterCalcShrinkDisplayArea = Notification.Name("EnterCalc.macOS.ShrinkDisplayArea")
    static let enterCalcToggleHistoryPanel = Notification.Name("EnterCalc.ToggleHistoryPanel")
    static let enterCalcToggleRoundingPanel = Notification.Name("EnterCalc.ToggleRoundingPanel")
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
                Button(localized("undo")) {
                    actionContext?.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(actionContext?.canUndo != true)

                Button(localized("redo")) {
                    actionContext?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(actionContext?.canRedo != true)
            }

            CommandGroup(after: .undoRedo) {
                Button(localized("clear")) {
                    actionContext?.clear()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(actionContext == nil)

                Button(localized("clear.all.command")) {
                    actionContext?.clearAll()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(actionContext == nil)
            }

            CommandGroup(after: .toolbar) {
                Button {
                    NotificationCenter.default.post(name: .enterCalcToggleHistoryPanel, object: nil)
                } label: {
                    Label(localized("history.toggle"), systemImage: "clock.arrow.circlepath")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button {
                    NotificationCenter.default.post(name: .enterCalcToggleRoundingPanel, object: nil)
                } label: {
                    Label(localized("rounding.toggle"), systemImage: "slider.horizontal.below.rectangle")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                // Also the only way to resize the display without a pointer:
                // the split between display and keypad is otherwise drag-only.
                Button {
                    NotificationCenter.default.post(name: .enterCalcGrowDisplayArea, object: nil)
                } label: {
                    Label(localized("display.grow"), systemImage: "arrow.up.and.down")
                }
                .keyboardShortcut(.upArrow, modifiers: [.shift])

                Button {
                    NotificationCenter.default.post(name: .enterCalcShrinkDisplayArea, object: nil)
                } label: {
                    Label(localized("display.shrink"), systemImage: "arrow.up.and.down")
                }
                .keyboardShortcut(.downArrow, modifiers: [.shift])
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
