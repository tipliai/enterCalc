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
    #if os(macOS)
    // Compact enough to fit below a top-row key in the smallest window, so
    // the key being edited stays in view (#131). A pointer needs less room
    // than a finger.
    public static let columns: Int = 6
    private static let cellSize: CGFloat = 36
    private static let cellSpacing: CGFloat = 6
    private static let panelPadding: CGFloat = 9
    private static let anchorGap: CGFloat = 6
    private static let glyphSize: CGFloat = 16
    private static let headerHeight: CGFloat = 28
    #else
    public static let columns: Int = 4
    private static let cellSize: CGFloat = 56
    private static let cellSpacing: CGFloat = 8
    private static let panelPadding: CGFloat = 12
    private static let anchorGap: CGFloat = 12
    private static let glyphSize: CGFloat = 20
    private static let headerHeight: CGFloat = 36
    #endif
    private static let screenMargin: CGFloat = 8

    private let session: FunctionKeyChooserSession
    private let assignments: CalculatorFunctionKeyAssignments
    private let palette: Palette
    private let currencySymbol: String
    private let title: String
    private let closeLabel: String
    private let label: (CalculatorFunctionKey) -> String
    private let onHighlight: (CalculatorFunctionKey?) -> Void
    private let onCommit: (CalculatorFunctionKey) -> Void
    private let onClose: () -> Void

    @State private var optionFrames: [CalculatorFunctionKey: CGRect] = [:]
    #if os(macOS)
    @State private var isCloseHovering = false
    #endif

    public init(
        session: FunctionKeyChooserSession,
        assignments: CalculatorFunctionKeyAssignments,
        palette: Palette,
        currencySymbol: String,
        title: String,
        closeLabel: String,
        label: @escaping (CalculatorFunctionKey) -> String,
        onHighlight: @escaping (CalculatorFunctionKey?) -> Void,
        onCommit: @escaping (CalculatorFunctionKey) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.assignments = assignments
        self.palette = palette
        self.currencySymbol = currencySymbol
        self.title = title
        self.closeLabel = closeLabel
        self.label = label
        self.onHighlight = onHighlight
        self.onCommit = onCommit
        self.onClose = onClose
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
        return CGSize(width: width, height: gridHeight + Self.panelPadding * 2 + Self.headerHeight + Self.cellSpacing)
    }

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
            header

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

    /// The title centred, with a close button at the trailing edge like the
    /// rounding, VAT and Tip panes (#131). Closing leaves the key as it was.
    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                closeButton
            }
        }
        .frame(height: Self.headerHeight)
    }

    @ViewBuilder
    private var closeButton: some View {
        #if os(macOS)
        Button(action: onClose) {
            Image(systemName: "xmark")
                .frame(width: 16, height: 16, alignment: .center)
                .padding(6)
                .background(isCloseHovering ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(closeLabel)
        .accessibilityLabel(Text(closeLabel))
        .onHover { isCloseHovering = $0 }
        #else
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(EnterCalcFont.appFont(size: 16))
                .frame(width: 28, height: 28)
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: 44, height: Self.headerHeight)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel(Text(closeLabel))
        #endif
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
                fontSize: Self.glyphSize,
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

    /// Keeps the key being edited in view: on touch the panel prefers to sit
    /// above it, clear of the finger; with a pointer it opens below it, under
    /// the menu it came from (#131). Either way it flips to the other side
    /// when there is no room, and always stays inside the container.
    private func panelOrigin(in geometry: GeometryProxy) -> CGPoint {
        Self.panelOrigin(anchor: session.anchor, panelSize: panelSize, container: geometry.frame(in: .global))
    }

    static func panelOrigin(anchor: CGRect, panelSize size: CGSize, container: CGRect) -> CGPoint {
        var x = anchor.midX - size.width / 2
        x = min(max(x, container.minX + screenMargin), max(container.maxX - size.width - screenMargin, container.minX + screenMargin))

        let above = anchor.minY - anchorGap - size.height
        let below = anchor.maxY + anchorGap
        let fitsAbove = above >= container.minY + screenMargin
        let fitsBelow = below + size.height + screenMargin <= container.maxY
        #if os(macOS)
        let prefersBelow = true
        #else
        let prefersBelow = false
        #endif

        let y: CGFloat
        if prefersBelow ? fitsBelow : !fitsAbove && fitsBelow {
            y = below
        } else if fitsAbove {
            y = above
        } else if fitsBelow {
            y = below
        } else {
            // No room either side: as close to the preferred side as fits.
            let lowest = container.maxY - screenMargin - size.height
            y = prefersBelow
                ? max(container.minY + screenMargin, min(below, lowest))
                : max(container.minY + screenMargin, min(above, lowest))
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
/// macOS uses `functionKeyContextMenu` instead; holding a mouse button down
/// is not how a desktop opens a contextual chooser.
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
extension View {
    /// Makes this key reassignable from its context menu: right-click (or
    /// Control-click) shows the standard menu with one item, Edit, which
    /// opens the chooser (#131). Fixed keys get no menu.
    ///
    /// The key's frame comes from the caller, which tracks it in SwiftUI's own
    /// `.global` space: the space the chooser positions itself in.
    @ViewBuilder
    public func functionKeyContextMenu(
        slot: CalculatorFunctionSlot?,
        editLabel: String,
        onEdit: @escaping (CalculatorFunctionSlot) -> Void
    ) -> some View {
        if let slot {
            contextMenu {
                Button(editLabel) { onEdit(slot) }
            }
        } else {
            self
        }
    }
}
#endif
