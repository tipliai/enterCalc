import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Speaking to VoiceOver from shared code (#145).
public enum VoiceOver {
    public static var isRunning: Bool {
        #if canImport(UIKit)
        UIAccessibility.isVoiceOverRunning
        #elseif canImport(AppKit)
        NSWorkspace.shared.isVoiceOverEnabled
        #else
        false
        #endif
    }

    /// Speaks `text` if VoiceOver is running. On iOS it waits for whatever
    /// VoiceOver is saying; on the Mac it is high priority.
    @MainActor
    public static func announce(_ text: String) {
        guard isRunning, !text.isEmpty else { return }
        #if canImport(UIKit)
        let message = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: message)
        #elseif canImport(AppKit)
        guard let element = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        #endif
    }

    /// Tells VoiceOver a pane has taken over: its name is spoken and, on iOS,
    /// focus moves into it.
    @MainActor
    static func announcePaneOpened(_ title: String) {
        guard isRunning else { return }
        #if canImport(UIKit)
        UIAccessibility.post(notification: .screenChanged, argument: title)
        #else
        announce(title)
        #endif
    }
}

/// A pane over the calculator (History, Rounding, VAT, Tip, Settings, the
/// function-key chooser) as VoiceOver and the keyboard should treat it
/// (#145):
///
/// - one named group that is modal, so VoiceOver can't wander onto the
///   calculator behind it;
/// - its name spoken when it opens, with VoiceOver's focus moved into it,
///   and "… closed" when it closes;
/// - the VoiceOver escape gesture (two-finger scrub) closes it.
struct AccessiblePane: ViewModifier {
    let title: String
    let closedAnnouncement: String?
    let onClose: () -> Void

    @AccessibilityFocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { onClose() }
            .accessibilityFocused($isFocused)
            .onAppear {
                // After the opening animation, so focus lands on the pane in
                // its final place.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    VoiceOver.announcePaneOpened(title)
                    #if !canImport(UIKit)
                    if VoiceOver.isRunning { isFocused = true }
                    #endif
                }
            }
            .onDisappear {
                if let closedAnnouncement {
                    VoiceOver.announce(closedAnnouncement)
                }
            }
    }
}

extension View {
    /// Marks this view as a pane over the calculator. See `AccessiblePane`.
    public func accessibilityPane(
        title: String,
        closedAnnouncement: String? = nil,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(AccessiblePane(title: title, closedAnnouncement: closedAnnouncement, onClose: onClose))
    }
}
