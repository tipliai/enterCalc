// Sources/KeyCaptureView.swift
import SwiftUI
import AppKit
import EnterCalcCore

private let debugKeyCapture = DebugLog.isEnabled

/// Invisible NSView that claims first responder so we can intercept keyboard input immediately.
struct KeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        if debugKeyCapture { print("[KeyCapture] makeNSView") }
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onKeyDown = onKeyDown
        if debugKeyCapture { print("[KeyCapture] updateNSView window:\(String(describing: nsView.window)) active:\(NSApp.isActive)") }
    }
}

final class KeyCatcherView: NSView {
    var onKeyDown: (NSEvent) -> Void = { _ in }
    private var observers: [Any] = []

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // never intercept mouse events

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if debugKeyCapture { print("[KeyCapture] moved to window key:\(window?.isKeyWindow ?? false) main:\(window?.isMainWindow ?? false) active:\(NSApp.isActive)") }
        window?.initialFirstResponder = self
        installObservers()
        ensureFocus()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        removeObservers()
    }

    deinit {
        removeObservers()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if debugKeyCapture { print("[KeyCapture] becomeFirstResponder -> \(result)") }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if debugKeyCapture { print("[KeyCapture] resignFirstResponder -> \(result)") }
        return result
    }

    func ensureFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let window {
                guard window.isKeyWindow else {
                    if debugKeyCapture { print("[KeyCapture] ensureFocus skipped (not key) for window#\(window.windowNumber)") }
                    return
                }
                if let event = NSApp.currentEvent, event.type.isMouseInteraction {
                    if debugKeyCapture { print("[KeyCapture] ensureFocus skipped (mouse interaction) for window#\(window.windowNumber)") }
                    return
                }
                if let responder = window.firstResponder, responder !== self {
                    if responder is NSControl || responder is NSTextView || responder is NSText {
                        if debugKeyCapture { print("[KeyCapture] ensureFocus skipped (respect responder \(type(of: responder))) for window#\(window.windowNumber)") }
                        return
                    }
                }
                let made = window.makeFirstResponder(self)
                if debugKeyCapture { print("[KeyCapture] ensureFocus window#\(window.windowNumber) key:\(window.isKeyWindow) active:\(NSApp.isActive) firstResponder:\(String(describing: window.firstResponder)) made:\(made)") }
            } else {
                if debugKeyCapture { print("[KeyCapture] ensureFocus failed - no window yet") }
            }
        }
    }

    private func installObservers() {
        guard let window else { return }
        removeObservers()
        let center = NotificationCenter.default
        let keyObs = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.ensureFocus()
        }
        let mainObs = center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { [weak self] _ in
            self?.ensureFocus()
        }
        observers = [keyObs, mainObs]
    }

    private func removeObservers() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
    }

    override func keyDown(with event: NSEvent) {
        if debugKeyCapture { print("[KeyCapture] keyDown keyCode:\(event.keyCode) chars:\(event.charactersIgnoringModifiers ?? "<nil>") command:\(event.modifierFlags.contains(.command))") }
        onKeyDown(event)
    }
}

// MARK: - Local key monitor (fallback when first responder chain misbehaves)

struct KeyEventMonitor: ViewModifier {
    let onKeyDown: (NSEvent) -> Bool
    @State private var monitor: Any?
    @State private var windowNumber: Int?

    func body(content: Content) -> some View {
        content
            .background(WindowResolver { window in
                if let number = window?.windowNumber {
                    windowNumber = number
                }
            })
            .onAppear {
                if windowNumber == nil {
                    windowNumber = NSApp.keyWindow?.windowNumber
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let eventWindow = event.windowNumber
                    if let targetNumber = windowNumber,
                       targetNumber != eventWindow {
                        return event // different window
                    }
                    if let keyNumber = NSApp.keyWindow?.windowNumber,
                       keyNumber != eventWindow {
                        return event // not our active window
                    }
                    let handled = onKeyDown(event)
                    if handled {
                        if debugKeyCapture { print("[KeyCapture] local monitor handled keyCode:\(event.keyCode) chars:\(event.charactersIgnoringModifiers ?? "<nil>")") }
                        return nil // swallow
                    }
                    return event // let others handle
                }
                if debugKeyCapture { print("[KeyCapture] local monitor installed") }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                    if debugKeyCapture { print("[KeyCapture] local monitor removed") }
                }
                windowNumber = nil
            }
    }
}

extension View {
    func keyEventMonitor(onKeyDown: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyEventMonitor(onKeyDown: onKeyDown))
    }
}

private extension NSEvent.EventType {
    var isMouseInteraction: Bool {
        switch self {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

// Resolves the containing window so we can scope key event monitoring to the correct window.
private struct WindowResolver: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            onResolve(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            onResolve(nsView?.window)
        }
    }
}
