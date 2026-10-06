import SwiftUI

/// Live state of one hold-and-drag reassignment.
///
/// The gesture is a single continuous motion: press and hold a configurable
/// key, keep the finger down while the chooser appears, drag over the option
/// you want, release to commit. The owning view holds this, the key that
/// started the gesture feeds it drag locations, and the chooser reports back
/// which option the finger is over.
public struct FunctionKeyChooserSession: Equatable {
    /// The key being reassigned.
    public var slot: CalculatorFunctionSlot
    /// Global frame of that key, so the panel can sit next to it.
    public var anchor: CGRect
    /// Latest drag location in global coordinates, or `nil` when the chooser
    /// was opened without a drag (VoiceOver's "Change function" action).
    public var dragLocation: CGPoint?
    /// Option the finger is currently over.
    public var highlighted: CalculatorFunctionKey?

    public init(
        slot: CalculatorFunctionSlot,
        anchor: CGRect,
        dragLocation: CGPoint? = nil,
        highlighted: CalculatorFunctionKey? = nil
    ) {
        self.slot = slot
        self.anchor = anchor
        self.dragLocation = dragLocation
        self.highlighted = highlighted
    }
}

/// Collects each option's global frame so the drag can be hit-tested without
/// SwiftUI's own hit testing, which a single continuous gesture cannot use.
private struct FunctionOptionFramesKey: PreferenceKey {
    static var defaultValue: [CalculatorFunctionKey: CGRect] { [:] }

    static func reduce(value: inout [CalculatorFunctionKey: CGRect], nextValue: () -> [CalculatorFunctionKey: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Grid of candidate functions shown during a hold-and-drag reassignment.
public struct CalculatorFunctionKeyChooser: View {
    public static let columns: Int = 4
    private static let cellSize: CGFloat = 56
    private static let cellSpacing: CGFloat = 8
    private static let panelPadding: CGFloat = 12
    private static let anchorGap: CGFloat = 12
    private static let screenMargin: CGFloat = 8

    private let session: FunctionKeyChooserSession
    private let assignments: CalculatorFunctionKeyAssignments
    private let palette: Palette
    private let currencySymbol: String
    private let title: String
    private let label: (CalculatorFunctionKey) -> String
    private let onHighlight: (CalculatorFunctionKey?) -> Void
    private let onCommit: (CalculatorFunctionKey) -> Void

    @State private var optionFrames: [CalculatorFunctionKey: CGRect] = [:]

    public init(
        session: FunctionKeyChooserSession,
        assignments: CalculatorFunctionKeyAssignments,
        palette: Palette,
        currencySymbol: String,
        title: String,
        label: @escaping (CalculatorFunctionKey) -> String,
        onHighlight: @escaping (CalculatorFunctionKey?) -> Void,
        onCommit: @escaping (CalculatorFunctionKey) -> Void
    ) {
        self.session = session
        self.assignments = assignments
        self.palette = palette
        self.currencySymbol = currencySymbol
        self.title = title
        self.label = label
        self.onHighlight = onHighlight
        self.onCommit = onCommit
    }

    private var options: [CalculatorFunctionKey] { CalculatorFunctionKey.chooserOrder }

    private var rowCount: Int {
        Int(ceil(Double(options.count) / Double(Self.columns)))
    }

    private var panelSize: CGSize {
        let width = CGFloat(Self.columns) * Self.cellSize
            + CGFloat(Self.columns - 1) * Self.cellSpacing
            + Self.panelPadding * 2
        let gridHeight = CGFloat(rowCount) * Self.cellSize + CGFloat(rowCount - 1) * Self.cellSpacing
        return CGSize(width: width, height: gridHeight + Self.panelPadding * 2 + titleHeight)
    }

    private var titleHeight: CGFloat { 22 }

    public var body: some View {
        GeometryReader { geometry in
            let origin = panelOrigin(in: geometry)

            panel
                .frame(width: panelSize.width, height: panelSize.height)
                .position(x: origin.x + panelSize.width / 2, y: origin.y + panelSize.height / 2)
        }
        .ignoresSafeArea()
        .onPreferenceChange(FunctionOptionFramesKey.self) { frames in
            optionFrames = frames
            updateHighlight()
        }
        .onChange(of: session.dragLocation) { _, _ in
            updateHighlight()
        }
    }

    private var panel: some View {
        VStack(spacing: Self.cellSpacing) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(height: titleHeight)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Self.cellSpacing) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: Self.cellSpacing) {
                        ForEach(0..<Self.columns, id: \.self) { column in
                            let index = row * Self.columns + column
                            if index < options.count {
                                cell(for: options[index])
                            } else {
                                Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
                            }
                        }
                    }
                }
            }
        }
        .padding(Self.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.panel)
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.buttonBorder, lineWidth: 1)
        )
    }

    private func cell(for function: CalculatorFunctionKey) -> some View {
        let isHighlighted = session.highlighted == function
        let isCurrent = assignments[session.slot] == function

        return Button {
            onCommit(function)
        } label: {
            FunctionKeyGlyph(
                function: function,
                currencySymbol: currencySymbol,
                fontSize: 20,
                color: palette.textPrimary
            )
            .frame(width: Self.cellSize, height: Self.cellSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? palette.accent.opacity(0.28) : palette.buttonFunction)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? palette.accent : (isCurrent ? palette.textSecondary : Color.clear), lineWidth: isHighlighted ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(Text(label(function)))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FunctionOptionFramesKey.self,
                    value: [function: proxy.frame(in: .global)]
                )
            }
        )
    }

    /// Hit-tests the live drag against the collected option frames. The frames
    /// are grown by half the spacing so the gaps between cells do not blink the
    /// highlight off mid-drag.
    private func updateHighlight() {
        guard let location = session.dragLocation else { return }

        let slop = Self.cellSpacing / 2
        let hit = optionFrames.first { _, frame in
            frame.insetBy(dx: -slop, dy: -slop).contains(location)
        }?.key

        guard hit != session.highlighted else { return }
        onHighlight(hit)
    }

    /// Prefers sitting above the key that started the gesture, flips below when
    /// there is no room, and always stays inside the container.
    private func panelOrigin(in geometry: GeometryProxy) -> CGPoint {
        let container = geometry.frame(in: .global)
        let size = panelSize

        var x = session.anchor.midX - size.width / 2
        x = min(max(x, container.minX + Self.screenMargin), max(container.maxX - size.width - Self.screenMargin, container.minX + Self.screenMargin))

        var y = session.anchor.minY - Self.anchorGap - size.height
        if y < container.minY + Self.screenMargin {
            let below = session.anchor.maxY + Self.anchorGap
            y = below + size.height + Self.screenMargin <= container.maxY
                ? below
                : max(container.minY + Self.screenMargin, container.midY - size.height / 2)
        }

        return CGPoint(x: x - container.minX, y: y - container.minY)
    }
}

/// Draws a function's glyph, whichever form it takes.
public struct FunctionKeyGlyph: View {
    private let function: CalculatorFunctionKey
    private let currencySymbol: String
    private let fontSize: CGFloat
    private let color: Color

    public init(function: CalculatorFunctionKey, currencySymbol: String, fontSize: CGFloat, color: Color) {
        self.function = function
        self.currencySymbol = currencySymbol
        self.fontSize = fontSize
        self.color = color
    }

    public var body: some View {
        Group {
            switch function.presentation {
            case .symbol(let name):
                Image(systemName: name)
            case .text(let glyph):
                Text(glyph)
            case .currencySymbol:
                Text(currencySymbol)
            }
        }
        .font(EnterCalcFont.appFont(size: fontSize))
        .foregroundStyle(color)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
}

// MARK: - Hold-and-drag gesture

/// Turns a key into a configurable one on touch: press and hold opens the
/// chooser, which then stays on screen so the option can simply be tapped.
/// Dragging straight onto an option without lifting works too and commits on
/// release, but lifting anywhere else leaves the chooser open rather than
/// cancelling.
///
/// The hold is tracked manually rather than with `LongPressGesture.sequenced`
/// because the drag has to keep reporting *global* locations after the press
/// succeeds — the chooser is a sibling overlay, not a child of the key — and a
/// sequenced gesture reports locations relative to the key instead.
///
/// macOS uses `secondaryClickToOpenFunctionChooser` instead; holding a mouse
/// button down is not how a desktop opens a contextual chooser.
public struct FunctionKeyHoldModifier: ViewModifier {
    /// How long the finger has to stay down before the chooser appears.
    public static let holdDuration: TimeInterval = 0.4
    /// Movement past this cancels the hold, so a swipe across the keypad is
    /// still a swipe.
    public static let moveCancelDistance: CGFloat = 12

    private let slot: CalculatorFunctionSlot
    private let isEnabled: Bool
    private let onOpen: (CalculatorFunctionSlot, CGRect) -> Void
    private let onDrag: (CGPoint) -> Void
    private let onRelease: () -> Void
    @Binding private var suppressesTap: Bool

    @State private var globalFrame: CGRect = .zero
    @State private var isChoosing: Bool = false
    @State private var pendingHold: DispatchWorkItem?
    /// Start point of the press being tracked. A hold cancelled by movement
    /// must not be rescheduled by the next event of the *same* press, or a
    /// swipe that paused mid-way would open the chooser — but a genuinely new
    /// press must start a new hold. The gesture's own `startLocation`
    /// distinguishes the two, and unlike a flag it cannot stay stuck if the
    /// gesture is ever cancelled without ending.
    @State private var trackedPressStart: CGPoint? = nil

    public init(
        slot: CalculatorFunctionSlot,
        isEnabled: Bool = true,
        suppressesTap: Binding<Bool>,
        onOpen: @escaping (CalculatorFunctionSlot, CGRect) -> Void,
        onDrag: @escaping (CGPoint) -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.slot = slot
        self.isEnabled = isEnabled
        self._suppressesTap = suppressesTap
        self.onOpen = onOpen
        self.onDrag = onDrag
        self.onRelease = onRelease
    }

    public func body(content: Content) -> some View {
        content
            .background(frameReader)
            .simultaneousGesture(holdGesture, including: isEnabled ? .all : .subviews)
    }

    private var frameReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { globalFrame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, updated in
                    globalFrame = updated
                }
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if isChoosing {
                    onDrag(value.location)
                    return
                }

                if trackedPressStart != value.startLocation {
                    trackedPressStart = value.startLocation
                    // A fresh press: clear any suppression left behind by a
                    // gesture that was cancelled rather than ended.
                    suppressesTap = false
                    scheduleHold()
                }

                if hypot(value.translation.width, value.translation.height) > Self.moveCancelDistance {
                    cancelHold()
                }
            }
            .onEnded { _ in
                cancelHold()
                trackedPressStart = nil
                guard isChoosing else { return }
                isChoosing = false
                onRelease()
                // Released on the key itself, so the key's own tap would fire
                // next. Clear the flag only once that has passed.
                DispatchQueue.main.async { suppressesTap = false }
            }
    }

    private func scheduleHold() {
        let work = DispatchWorkItem {
            guard pendingHold != nil else { return }
            isChoosing = true
            suppressesTap = true
            onOpen(slot, globalFrame)
        }
        pendingHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: work)
    }

    private func cancelHold() {
        pendingHold?.cancel()
        pendingHold = nil
    }
}

extension View {
    /// Makes this key reassignable by press-and-hold, then drag, then release.
    public func functionKeyHold(
        slot: CalculatorFunctionSlot,
        isEnabled: Bool = true,
        suppressesTap: Binding<Bool>,
        onOpen: @escaping (CalculatorFunctionSlot, CGRect) -> Void,
        onDrag: @escaping (CGPoint) -> Void,
        onRelease: @escaping () -> Void
    ) -> some View {
        modifier(
            FunctionKeyHoldModifier(
                slot: slot,
                isEnabled: isEnabled,
                suppressesTap: suppressesTap,
                onOpen: onOpen,
                onDrag: onDrag,
                onRelease: onRelease
            )
        )
    }
}

/// Applies `FunctionKeyHoldModifier` only when the key actually occupies a
/// configurable slot, so a fixed key carries no extra gesture at all.
public struct OptionalFunctionKeyHold: ViewModifier {
    private let slot: CalculatorFunctionSlot?
    private let onOpen: (CalculatorFunctionSlot, CGRect) -> Void
    private let onDrag: (CGPoint) -> Void
    private let onRelease: () -> Void
    @Binding private var suppressesTap: Bool

    public init(
        slot: CalculatorFunctionSlot?,
        suppressesTap: Binding<Bool>,
        onOpen: @escaping (CalculatorFunctionSlot, CGRect) -> Void,
        onDrag: @escaping (CGPoint) -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.slot = slot
        self._suppressesTap = suppressesTap
        self.onOpen = onOpen
        self.onDrag = onDrag
        self.onRelease = onRelease
    }

    public func body(content: Content) -> some View {
        if let slot {
            content.functionKeyHold(
                slot: slot,
                suppressesTap: $suppressesTap,
                onOpen: onOpen,
                onDrag: onDrag,
                onRelease: onRelease
            )
        } else {
            content
        }
    }
}

#if os(macOS)
import AppKit

/// Opens the function chooser on a secondary click — right-click, or
/// Control-click, which macOS treats the same way.
///
/// SwiftUI has no secondary-click gesture, and `.contextMenu` would draw an
/// AppKit menu rather than the chooser panel. The capture view therefore
/// hit-tests itself *only* for secondary-click events, so ordinary left clicks
/// pass straight through to the button underneath and keep working.
private struct SecondaryClickCatcher: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    final class CatcherView: NSView {
        var onSecondaryClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }

            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                // Control-click is a secondary click on macOS.
                return event.modifierFlags.contains(.control) ? super.hitTest(point) : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onSecondaryClick?()
        }

        override func mouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else {
                super.mouseDown(with: event)
                return
            }

            onSecondaryClick?()
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }
}

extension View {
    /// Makes this key reassignable by right-clicking (or Control-clicking) it.
    /// The key's frame is not derived from AppKit here: the caller already
    /// tracks it through SwiftUI's own `.global` space, which is the space the
    /// chooser positions itself in. Converting an `NSView` frame instead would
    /// mean matching AppKit's flipped origin to SwiftUI's by hand.
    @ViewBuilder
    public func secondaryClickToOpenFunctionChooser(
        slot: CalculatorFunctionSlot?,
        onOpen: @escaping (CalculatorFunctionSlot) -> Void
    ) -> some View {
        if let slot {
            overlay(SecondaryClickCatcher { onOpen(slot) })
        } else {
            self
        }
    }
}
#endif
