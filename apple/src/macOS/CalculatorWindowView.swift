// src/macOS/CalculatorWindowView.swift
import SwiftUI
import AppKit
import EnterCalcCore

// Scales a baseline point size by the user's Dynamic Type preference for the
// given text style, never shrinking below the baseline (returns >= 1.0).
private func macPreferredTextScale(for style: NSFont.TextStyle, baseline: CGFloat) -> CGFloat {
    let preferredSize = NSFont.preferredFont(forTextStyle: style).pointSize
    guard preferredSize.isFinite, baseline > 0 else { return 1.0 }
    return max(1.0, preferredSize / baseline)
}

// Plays the button click sound, but only for genuine mouse clicks. Keyboard and
// programmatic activations are filtered out so typing stays silent.
@MainActor
private enum MacButtonSoundFeedback {
    static func playIfNeeded(disabled: Bool, isEnterKey: Bool = false) {
        guard !disabled else { return }
        guard let eventType = NSApp.currentEvent?.type, eventType.isButtonSoundMouseInteraction else {
            return
        }

        if isEnterKey {
            CalculatorButtonSound.playEnterClick()
        } else {
            CalculatorButtonSound.playClick()
        }
    }
}

private extension NSEvent.EventType {
    var isButtonSoundMouseInteraction: Bool {
        switch self {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }
}

// Main macOS calculator window. Hosts the display, keypad, and the history /
// rounding / settings overlays, and owns per-window settings and sizing. Each
// window gets its own view model, so windows are independent.
struct CalculatorWindowView: View {
    // Only one overlay pane is visible at a time; nil means none.
    private enum OverlayPane {
        case history
        case rounding
        case settings
    }

    @ObservedObject var viewModel: CalculatorViewModel
    @ObservedObject private var systemAppearance = SystemAppearanceMonitor.shared
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnabled
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var displayDynamicTypeScale: CGFloat = 1.0
    @State private var showHistory: Bool = false
    @State private var userToggledHistory: Bool = false
    @State private var flashCopy: Bool = false
    @State private var currentWidth: CGFloat = 0
    @State private var appliedStoredSize: Bool = false
    @State private var menuHover: Bool = false
    @State private var newWindowHover: Bool = false
    @State private var historyHover: Bool = false
    @State private var activeOverlay: OverlayPane? = nil
    @State private var historyTrashHover: Bool = false
    @State private var historyCloseHover: Bool = false
    @State private var historyResizeHover: Bool = false
    @State private var didClearHistoryOverlay: Bool = false
    @State private var displayHover: Bool = false
    @State private var windowReference: NSWindow? = nil
    @State private var showCopyToast: Bool = false
    @State private var copyToastDismissWorkItem: DispatchWorkItem?
    @State private var operatorRevealProgress: Double = 0.0
    @State private var operatorAnimFadeOpacity: Double = 1.0
    @State private var historyOverlayHeight: CGFloat? = nil
    @State private var historyOverlayResizeStartHeight: CGFloat = 0
    @State private var isResizingHistoryOverlay: Bool = false
    @State private var keypadResizeHover: Bool = false
    @State private var isResizingKeypadHeight: Bool = false
    @State private var keypadResizeGestureStartMultiplier: Double = 1.0
    @State private var liveKeypadHeightMultiplier: Double? = nil
    @State private var operationTextMeasuredHeight: CGFloat = 0

    private let minimumWindowWidthPoints: CGFloat = 280
    private let minimumWindowHeightPoints: CGFloat = 452
    private let fallbackBackingScaleFactor: CGFloat = 2
    private let outerHorizontalPadding: CGFloat = 8 * 2
    private let historyPanelWidth: CGFloat = 240
    private let historySpacing: CGFloat = 6
    private let calculatorContentCoordinateSpace = "calculatorContent"
    @State private var windowSettings: CalculatorScreenSettings
    @AppStorage("window.width") private var storedWindowWidth: Double = 0
    @AppStorage("window.height") private var storedWindowHeight: Double = 0
    @AppStorage("window.historyOpen") private var storedHistoryOpen: Bool = false
    @AppStorage("window.historyOverlayHeight") private var storedHistoryOverlayHeight: Double = 0

    init(viewModel: CalculatorViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _windowSettings = State(initialValue: Self.loadStoredSettings())
    }

    private func verticalLockedTranslation(_ value: DragGesture.Value) -> CGFloat {
        value.location.y - value.startLocation.y
    }

    private var palette: Palette { currentTheme.palette(using: colorScheme, increasedContrast: colorSchemeContrast == .increased) }

    // Color scheme this window is actually drawing in. Resolved from the theme
    // itself rather than the ambient environment so that selecting `system`
    // repaints the SwiftUI content in step with the native window chrome instead
    // of waiting for the next event that happens to re-resolve the environment.
    private var colorScheme: ColorScheme {
        currentTheme.preferredColorScheme ?? systemAppearance.colorScheme
    }

    private var currentTheme: AppTheme {
        AppTheme(rawValue: windowSettings.themeRawValue) ?? .system
    }

    // "Enter" is an English word; every other language uses the symbol, as does
    // the alternative keypad regardless of language.
    private var equalsButtonTitle: String {
        let usesEnterWord = EqualsKeyLabel.usesEnterWord(
            usesAlternativeKeypad: windowSettings.usesAlternativeKeypad,
            resolvedLocalizationCode: resolvedLocalizationCode(for: windowSettings.languageCode)
        )
        return usesEnterWord
            ? macLocalized("key.enter", bundle: currentLocalizationBundle)
            : EqualsKeyLabel.symbol
    }

    private var currentNumberFormatStyle: NumberFormatStyle {
        NumberFormatStyle(rawValue: windowSettings.numberFormatStyleRawValue) ?? NumberFormatStyle.detected()
    }

    private var effectiveHistoryTextScale: CGFloat {
        macPreferredTextScale(for: .body, baseline: 13)
    }

    private var currentLocalizationBundle: Bundle? {
        isDefaultLocalizationSelection(windowSettings.languageCode)
            ? nil
            : localizationBundle(for: windowSettings.languageCode)
    }

    private func logUI(_ message: String) {
        DebugLog.emit("UI", message)
    }

    private func debugKeyCharacters(_ text: String?) -> String {
        guard let text else { return "nil" }
        if text.isEmpty { return "\"\"[]" }
        let scalarList = text.unicodeScalars
            .map { "U+\(String($0.value, radix: 16, uppercase: true))" }
            .joined(separator: ",")
        return "\"\(text)\"[\(scalarList)]"
    }

    // Bridges this window's calculator actions to the menu bar (Copy, Paste,
    // Undo, etc.) via FocusedValues so the active window drives the menus.
    private var actionContext: CalculatorActionContext {
        CalculatorActionContext(
            copy: { copyCurrentResultToPasteboard() },
            copyOperation: { copyCurrentOperationToPasteboard() },
            canCopyOperation: viewModel.hasOperationToCopy,
            paste: { viewModel.pasteFromPasteboard() },
            undo: { viewModel.undo() },
            redo: { viewModel.redo() },
            canUndo: viewModel.canUndo,
            canRedo: viewModel.canRedo,
            clear: { viewModel.clearEntry() },
            clearAll: { viewModel.clearAll() }
        )
    }

    private var keypadColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    }

    private var compactHistoryWidthThreshold: CGFloat {
        minimumCalculatorPaneWidth + historyPanelWidth + historySpacing + outerHorizontalPadding
    }

    private var minimumCalculatorPaneWidth: CGFloat {
        let minimumContentWidth = minimumContentSize(window: currentWindow()).width
        return max(280, minimumContentWidth - outerHorizontalPadding)
    }

    private func headerHoverBackground(_ hovering: Bool) -> Color {
        guard hovering else { return .clear }
        return palette.headerHover
    }

    private var usesCompactHistoryOverlay: Bool {
        currentWidth <= compactHistoryWidthThreshold
    }

    private var showHistoryOverlay: Bool {
        activeOverlay == .history
    }

    private var showRoundingOverlay: Bool {
        activeOverlay == .rounding
    }

    private var showSettingsOverlay: Bool {
        activeOverlay == .settings
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 6) {
                calculatorPane

                if showHistory && !usesCompactHistoryOverlay {
                    HistoryPanel(
                        entries: viewModel.history,
                        onSelect: { entry in viewModel.reuse(entry) },
                        onClear: { viewModel.clearHistory() },
                        onCopyOperation: { entry in copyHistoryEntryOperationToPasteboard(entry) },
                        palette: palette,
                        textScale: effectiveHistoryTextScale
                    )
                    .frame(width: historyPanelWidth)
                }
            }
            .padding(8)
            .background(surfaceColor)
            .environment(\.macLocalizationBundle, currentLocalizationBundle)
            // Always an explicit scheme (never nil) so nested views that read
            // `@Environment(\.colorScheme)` — the settings sheet and overlays —
            // resolve to the same appearance this window computed.
            .preferredColorScheme(colorScheme)
            .background(CalculatorWindowResolver { window in
                guard windowReference !== window else {
                    return
                }

                windowReference = window
            })
            .focusedSceneValue(\.calculatorActions, actionContext)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
                normalizeWindowLanguageIfNeeded()
                applyCurrentWindowSettings()
                currentWidth = geo.size.width
                historyOverlayHeight = loadStoredHistoryOverlayHeight()
                DispatchQueue.main.async {
                    updateWindowMinSize()
                    applyStoredWindowSizeIfNeeded()
                    updateHistoryVisibility(for: currentWidth)
                }
                startOperatorIntroAnimation()
            }
            .onChange(of: windowReference?.windowNumber) {
                guard windowReference != nil else {
                    return
                }

                applyCurrentWindowSettings()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, isDefaultLocalizationSelection(windowSettings.languageCode) else {
                    return
                }

                applyCurrentWindowSettings()
                startOperatorIntroAnimation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      window === windowReference else {
                    return
                }

                applyCurrentWindowSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .enterCalcToggleHistoryPanel)) { _ in
                let isFocusedWindow = windowReference?.isKeyWindow == true || windowReference?.isMainWindow == true
                guard isFocusedWindow else { return }
                toggleHistoryVisibility()
            }
            .onReceive(NotificationCenter.default.publisher(for: .enterCalcToggleRoundingPanel)) { _ in
                let isFocusedWindow = windowReference?.isKeyWindow == true || windowReference?.isMainWindow == true
                guard isFocusedWindow else { return }
                toggleRoundingOverlay()
            }
            .onChange(of: geo.size.width) { _, width in
                currentWidth = width
                updateHistoryVisibility(for: width)
            }
            .background(
                KeyCaptureView { event in
                    _ = handleKey(event)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            )
            .overlay(alignment: .top) {
                if showCopyToast {
                    copiedToast
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
            .keyEventMonitor { event in
                handleKey(event)
            }
            .onChange(of: showHistory) {
                updateWindowMinSize()
                logUI("showHistory changed -> \(showHistory) keyWindow#\(NSApp.keyWindow?.windowNumber ?? -1)")
            }
        }
    }

    private var calculatorPane: some View {
        let headerToDisplaySpacing: CGFloat = 8
        let separatorHeight: CGFloat = 32
        let minimumDisplayHeight: CGFloat = 108
        let minimumKeypadHeight: CGFloat = 140
        let multiplier = activeKeypadHeightMultiplier()
        // multiplier 1.0 = display shortest, 0.5 = display tallest
        let displayProgress = CGFloat((1.0 - multiplier) / 0.5)
        let keypadBottomPadding: CGFloat = outerHorizontalPadding / 2 - 1 + 3 * displayProgress

        return VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 6) {
                header
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, headerToDisplaySpacing)

            GeometryReader { geo in
                let availableHeight = max(geo.size.height - keypadBottomPadding, 1)
                let maximumKeypadHeight = max(minimumKeypadHeight, availableHeight - minimumDisplayHeight - separatorHeight)
                let defaultKeypadHeight = maximumKeypadHeight
                let proposedKeypadHeight = defaultKeypadHeight * CGFloat(multiplier)
                let keypadHeight = min(max(proposedKeypadHeight, minimumKeypadHeight), maximumKeypadHeight)
                let displayHeight = max(minimumDisplayHeight, availableHeight - separatorHeight - keypadHeight)

                VStack(spacing: 0) {
                    display
                        .frame(maxWidth: .infinity, minHeight: displayHeight, maxHeight: displayHeight, alignment: .top)

                    keypadResizeHandle(defaultKeypadHeight: defaultKeypadHeight, height: separatorHeight)

                    keypadArea
                        .frame(maxWidth: .infinity, minHeight: keypadHeight, maxHeight: keypadHeight, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .padding(.bottom, keypadBottomPadding)
        .coordinateSpace(name: calculatorContentCoordinateSpace)
        .overlayPreferenceValue(MemoryControlsBoundsKey.self) { anchor in
            GeometryReader { geo in
                if let anchor {
                    let controlsRect = geo[anchor]
                    let overlayTop = showSettingsOverlay
                        ? CGFloat.zero
                        : max(0, min(controlsRect.maxY, geo.size.height))
                    let defaultHistoryHeight = max(0, geo.size.height - overlayTop)
                    let overlayHeight = showSettingsOverlay
                        ? geo.size.height
                        : max(0, geo.size.height - overlayTop)
                    let historyHeight = resolvedHistoryOverlayHeight(
                        defaultHeight: defaultHistoryHeight,
                        windowHeight: geo.size.height
                    )

                    ZStack(alignment: .top) {
                        Color.black.opacity(activeOverlay == nil ? 0 : overlayScrimOpacity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if activeOverlay != nil {
                                    closeActiveOverlay()
                                }
                            }
                            .allowsHitTesting(activeOverlay != nil)
                            .animation(reduceMotionEnabled ? nil : .easeInOut, value: activeOverlay)
                            .padding(.horizontal, -8)
                            .padding(.top, -8)
                            .padding(.bottom, -8)

                        if showHistoryOverlay {
                            historyOverlay(defaultHeight: defaultHistoryHeight, windowHeight: geo.size.height, panelHeight: historyHeight)
                                .frame(width: geo.size.width, alignment: .top)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .allowsHitTesting(activeOverlay == .history)
                                .transition(.opacity)
                        } else if showRoundingOverlay {
                            roundingOverlay()
                                .frame(width: geo.size.width, alignment: .top)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .allowsHitTesting(activeOverlay == .rounding)
                                .transition(.opacity)
                        } else if showSettingsOverlay {
                            settingsOverlay
                                .frame(width: geo.size.width, height: overlayHeight, alignment: .top)
                                .offset(y: overlayTop)
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(activeOverlay != nil)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                Button {
                    copyCurrentResultToPasteboard()
                } label: {
                    Label(macLocalized("copy", bundle: currentLocalizationBundle), systemImage: "doc.on.doc")
                }
                Button {
                    copyCurrentOperationToPasteboard()
                } label: {
                    Label(macLocalized("history.copyOperation", bundle: currentLocalizationBundle), systemImage: "doc.on.doc")
                }
                .disabled(!viewModel.hasOperationToCopy)
                Button {
                    viewModel.pasteFromPasteboard()
                } label: {
                    Label(macLocalized("paste", bundle: currentLocalizationBundle), systemImage: "doc.on.clipboard")
                }
                Divider()
                Button {
                    toggleSettingsOverlay()
                } label: {
                    Label(macLocalized("settings.title", bundle: currentLocalizationBundle), systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(EnterCalcFont.appFont(size: 16))
                    .foregroundStyle(primaryForeground)
                    .frame(width: 18, height: 18, alignment: .center)
                    .padding(6)
                    .background(headerHoverBackground(menuHover))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(Text(macLocalized("settings.title", bundle: currentLocalizationBundle)))
            .fixedSize()
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { hovering in
                menuHover = hovering
                hovering ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
            .onTapGesture { toggleSettingsOverlay() }

            Spacer()

            Button {
                toggleHistoryVisibility()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 18, height: 18, alignment: .center)
                    .padding(6)
                    .background(headerHoverBackground(historyHover))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryForeground)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onHover { hovering in
                historyHover = hovering
                hovering ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
            .help(macLocalized("history.toggle", bundle: currentLocalizationBundle))
            .accessibilityLabel(Text(macLocalized("history.toggle", bundle: currentLocalizationBundle)))

            Button {
                storeWindowSize()
                logUI("New window button tapped; keyWindow#\(NSApp.keyWindow?.windowNumber ?? -1)")
                openWindow(id: "main")
                focusNewestWindowSoon()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .frame(width: 18, height: 18, alignment: .center)
                    .padding(6)
                    .background(headerHoverBackground(newWindowHover))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryForeground)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onHover { hovering in
                newWindowHover = hovering
                hovering ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
            .help(macLocalized("window.new", bundle: currentLocalizationBundle))
            .accessibilityLabel(Text(macLocalized("window.new", bundle: currentLocalizationBundle)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var display: some View {
        let baseBasicFontSize: CGFloat = 12
        let baseResultFontSize: CGFloat = 48
        let displaySpacing: CGFloat = 4
        let baseBasicRowHeight: CGFloat = 16
        let basicBaseOpacity: Double = 0.15

        return GeometryReader { displayGeometry in
            let contentHeight = max(1, displayGeometry.size.height - 8 - 3)
            let effectiveDisplayScale = max(
                displayDynamicTypeScale,
                macPreferredTextScale(for: .largeTitle, baseline: 26)
            )
            let resultFontSize = boundedDynamicTypeSize(
                baseResultFontSize,
                scale: effectiveDisplayScale,
                maximum: max(baseResultFontSize, contentHeight * 0.78)
            )
            let basicFontSize = boundedDynamicTypeSize(
                baseBasicFontSize,
                scale: effectiveDisplayScale,
                maximum: max(baseBasicFontSize, resultFontSize * 0.34)
            )
            let resultLineHeight = resultFontSize * 1.12
            let basicRowHeight = max(baseBasicRowHeight, basicFontSize * 1.32)
            let measuredOperationHeight = max(operationTextMeasuredHeight, basicFontSize * 1.3)
            let operationOffsetY = operationContentOffsetY(
                operationHeight: measuredOperationHeight,
                resultLineHeight: resultLineHeight,
                spacing: displaySpacing,
                availableHeight: contentHeight
            )
            let resultBottom = measuredOperationHeight + displaySpacing + resultLineHeight + operationOffsetY
            let basicOpacity = basicLabelOpacity(
                baseOpacity: basicBaseOpacity,
                resultBottom: resultBottom,
                availableHeight: contentHeight,
                basicHeight: basicRowHeight
            )

            ZStack(alignment: .bottomLeading) {
                VStack(alignment: .trailing, spacing: displaySpacing) {
                    Text(viewModel.expressionDisplay)
                        .font(EnterCalcFont.appFont(size: basicFontSize))
                        .foregroundStyle(colorScheme == .dark ? fadedForeground : Color.black)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { operationGeometry in
                                Color.clear
                                    .onAppear {
                                        updateOperationTextMeasuredHeight(operationGeometry.size.height)
                                    }
                                    .onChange(of: operationGeometry.size.height) { _, newHeight in
                                        updateOperationTextMeasuredHeight(newHeight)
                                    }
                            }
                        )

                    if viewModel.canDirectlyEditDisplay {
                        EditableDisplayResultText(
                            text: viewModel.display,
                            fontSize: resultFontSize,
                            foregroundColor: colorScheme == .dark ? primaryForeground : Color.black,
                            minScaleFactor: 0.15,
                            caretBoundaryIndex: viewModel.displayEditCaretBoundaryIndex,
                            caretColor: colorScheme == .dark ? primaryForeground : Color.black,
                            onTapBoundary: { boundaryIndex in
                                viewModel.setDisplayEditCursor(displayBoundaryIndex: boundaryIndex)
                            }
                        )
                        .frame(maxWidth: .infinity, minHeight: resultLineHeight, maxHeight: resultLineHeight, alignment: .trailing)
                        .layoutPriority(1)
                    } else {
                        Text(viewModel.display)
                            .font(EnterCalcFont.appFont(size: resultFontSize))
                            .foregroundStyle(colorScheme == .dark ? primaryForeground : Color.black)
                            .frame(maxWidth: .infinity, minHeight: resultLineHeight, maxHeight: resultLineHeight, alignment: .trailing)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.15)
                            .layoutPriority(1)
                    }
                }
                .offset(y: operationOffsetY)
                .frame(maxWidth: .infinity, maxHeight: contentHeight, alignment: .topTrailing)
                .clipped()

                memoryControls(opacity: basicOpacity)
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
        }
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(displayHover ? panelColor : surfaceColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: colorScheme == .dark
                                    ? [
                                        .init(color: Color.white.opacity(0.10), location: 0.0),
                                        .init(color: Color.white.opacity(0.16), location: 0.5),
                                        .init(color: Color.white.opacity(0.10), location: 1.0)
                                    ]
                                    : [
                                        .init(color: Color.white.opacity(0.26), location: 0.0),
                                        .init(color: Color.white.opacity(0.56), location: 0.5),
                                        .init(color: Color.white.opacity(0.26), location: 1.0)
                                    ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    if colorScheme != .dark {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.0), location: 0.20),
                                        .init(color: Color.white.opacity(0.08), location: 0.31),
                                        .init(color: Color.white.opacity(0.42), location: 0.33),
                                        .init(color: Color.white.opacity(0.18), location: 0.338),
                                        .init(color: Color.white.opacity(0.06), location: 0.42),
                                        .init(color: Color.white.opacity(0.0), location: 0.56)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.buttonBorder, lineWidth: colorScheme == .dark ? 0 : 1)
        )
        .contextMenu {
            Button {
                copyCurrentResultToPasteboard()
            } label: {
                Label(macLocalized("copy", bundle: currentLocalizationBundle), systemImage: "doc.on.doc")
            }
            Button {
                copyCurrentOperationToPasteboard()
            } label: {
                Label(macLocalized("history.copyOperation", bundle: currentLocalizationBundle), systemImage: "doc.on.doc")
            }
            .disabled(!viewModel.hasOperationToCopy)
            Button {
                viewModel.pasteFromPasteboard()
            } label: {
                Label(macLocalized("paste", bundle: currentLocalizationBundle), systemImage: "doc.on.clipboard")
            }
        }
        .onHover { hovering in
              displayHover = hovering
              if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture {
            if viewModel.isDirectlyEditingDisplay {
                viewModel.clearDisplayEditCursor()
                return
            }
            copyDisplayToPasteboardWithFlash()
        }
        .overlay {
            if flashCopy {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private func copyDisplayToPasteboardWithFlash() {
        viewModel.clearDisplayEditCursor()
        viewModel.copyToPasteboard()
        showCopiedToast()
        if reduceMotionEnabled {
            flashCopy = true
        } else {
            withAnimation(.easeOut(duration: 0.1)) {
                flashCopy = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if reduceMotionEnabled {
                flashCopy = false
            } else {
                withAnimation(.easeOut(duration: 0.1)) {
                    flashCopy = false
                }
            }
        }
    }

    private func copyCurrentResultToPasteboard() {
        viewModel.clearDisplayEditCursor()
        viewModel.copyToPasteboard()
        showCopiedToast()
    }

    private func copyCurrentOperationToPasteboard() {
        guard viewModel.hasOperationToCopy else { return }
        viewModel.clearDisplayEditCursor()
        viewModel.copyOperationToPasteboard()
        showCopiedToast()
    }

    private func copyHistoryEntryOperationToPasteboard(_ entry: HistoryEntry) {
        viewModel.clearDisplayEditCursor()
        viewModel.copyOperationToPasteboard(entry)
        showCopiedToast()
    }

    private func showCopiedToast() {
        copyToastDismissWorkItem?.cancel()

        if !showCopyToast {
            if reduceMotionEnabled {
                showCopyToast = true
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    showCopyToast = true
                }
            }
        }

        let dismissWorkItem = DispatchWorkItem {
            if reduceMotionEnabled {
                showCopyToast = false
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    showCopyToast = false
                }
            }
            copyToastDismissWorkItem = nil
        }

        copyToastDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: dismissWorkItem)
    }

    private var copiedToast: some View {
        Text(macLocalized("copy.copied", bundle: currentLocalizationBundle))
            .font(EnterCalcFont.appFont(size: 14))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 12, y: 6)
            .allowsHitTesting(false)
    }

    private func memoryControls(opacity: Double) -> some View {
        return Text(macLocalized("calculator.mode.basic", bundle: currentLocalizationBundle))
            .font(EnterCalcFont.appFont(size: 12))
            .foregroundStyle(primaryForeground.opacity(opacity))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16, alignment: .leading)
            .lineLimit(1)
            .clipped()
            .animation(reduceMotionEnabled ? nil : .easeInOut(duration: 0.18), value: opacity)
            .anchorPreference(
                key: MemoryControlsBoundsKey.self,
                value: .bounds,
                transform: { $0 }
            )
    }

    private func updateOperationTextMeasuredHeight(_ height: CGFloat) {
        let normalizedHeight = max(0, height)
        guard abs(operationTextMeasuredHeight - normalizedHeight) > 0.5 else { return }
        operationTextMeasuredHeight = normalizedHeight
    }

    private func operationContentOffsetY(
        operationHeight: CGFloat,
        resultLineHeight: CGFloat,
        spacing: CGFloat,
        availableHeight: CGFloat
    ) -> CGFloat {
        min(0, availableHeight - (operationHeight + spacing + resultLineHeight))
    }

    private func basicLabelOpacity(
        baseOpacity: Double,
        resultBottom: CGFloat,
        availableHeight: CGFloat,
        basicHeight: CGFloat
    ) -> Double {
        let clampedBasicHeight = max(1, basicHeight)
        let basicTop = availableHeight - clampedBasicHeight
        let overlap = max(0, resultBottom - basicTop)
        let visibility = max(0, min(1, 1 - Double(overlap / clampedBasicHeight)))
        return baseOpacity * visibility
    }

    private func boundedDynamicTypeSize(_ baseSize: CGFloat, scale: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(baseSize, baseSize * scale), maximum)
    }

    private var keypadArea: some View {
        keypadGrid
    }

    private var keypadGrid: some View {
        GeometryReader { geo in
            let usesAlternativeKeypad = windowSettings.usesAlternativeKeypad
            let rows: CGFloat = usesAlternativeKeypad ? 6 : (5 + (1.0 / 3.0))
            let spacing: CGFloat = 4
            let availableHeight = max(geo.size.height, spacing * 5 + rows)
            let cellHeight = (availableHeight - spacing * (rows - 1)) / rows
            let buttons = keypadButtons()
            let compactActionHeight = max(16, cellHeight / 3)
            let compactButtons = compactActionRowButtons()

            VStack(spacing: spacing) {
                if !usesAlternativeKeypad {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 5), spacing: spacing) {
                        ForEach(compactButtons.indices, id: \.self) { index in
                            let button = compactButtons[index]
                            CompactActionButton(
                                symbol: button.symbol,
                                accessibilityLabel: button.accessibilityLabel,
                                isBare: button.isBare,
                                height: compactActionHeight,
                                disabled: button.action == nil,
                                palette: palette,
                                action: { button.action?() }
                            )
                        }
                    }
                    .padding(.bottom, spacing)
                }

                let buttonRows = groupedKeypadRows(from: buttons)
                let cellWidth = max(0, (geo.size.width - spacing * 3) / 4)

                VStack(spacing: spacing) {
                    ForEach(buttonRows.indices, id: \.self) { rowIndex in
                        let row = buttonRows[rowIndex]
                        HStack(spacing: spacing) {
                            ForEach(row.indices, id: \.self) { buttonIndex in
                                let button = row[buttonIndex]
                                CalculatorButton(title: button.title, kind: button.kind, height: cellHeight, disablesButtonSound: windowSettings.disablesButtonSound, action: button.action, enabled: button.enabled, palette: palette, operatorRevealProgress: operatorRevealProgress, operatorAnimFadeOpacity: operatorAnimFadeOpacity, reduceMotionEnabled: reduceMotionEnabled)
                                    .frame(width: cellWidth * CGFloat(button.columnSpan) + spacing * CGFloat(button.columnSpan - 1))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func groupedKeypadRows(from buttons: [ButtonItem], columns: Int = 4) -> [[ButtonItem]] {
        var rows: [[ButtonItem]] = []
        var currentRow: [ButtonItem] = []
        var usedColumns = 0

        for button in buttons {
            let span = max(1, min(columns, button.columnSpan))
            if usedColumns + span > columns && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                usedColumns = 0
            }

            currentRow.append(button)
            usedColumns += span

            if usedColumns == columns {
                rows.append(currentRow)
                currentRow = []
                usedColumns = 0
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private func keypadResizeHandle(defaultKeypadHeight: CGFloat, height: CGFloat) -> some View {
        let handleColor = palette.textSecondary.opacity(colorScheme == .dark ? 0.31 : 0.225)
        let lineColor = handleColor
        let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isResizingKeypadHeight {
                    keypadResizeGestureStartMultiplier = activeKeypadHeightMultiplier()
                    isResizingKeypadHeight = true
                }

                let delta = Double(verticalLockedTranslation(value) / max(defaultKeypadHeight, 1))
                let newMultiplier = min(max(keypadResizeGestureStartMultiplier - delta, 0.5), 1.0)
                liveKeypadHeightMultiplier = newMultiplier
            }
            .onEnded { _ in
                let finalMultiplier = activeKeypadHeightMultiplier()
                updateWindowSettings { $0.keypadHeightMultiplier = finalMultiplier }
                isResizingKeypadHeight = false
                liveKeypadHeightMultiplier = nil
            }

        return ZStack {
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(lineColor)
                .frame(height: isResizingKeypadHeight ? 2 : 1)
                .padding(.horizontal, outerHorizontalPadding + 24)

            Image(systemName: "arrow.up.arrow.down")
                .font(EnterCalcFont.appFont(size: 9))
                .foregroundStyle(handleColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                    .fill(surfaceColor)
                )
        }
        .offset(y: -2)
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 36))
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture)
        .onHover { hovering in
            keypadResizeHover = hovering
            if hovering || isResizingKeypadHeight {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onChange(of: isResizingKeypadHeight) { _, isResizing in
            if isResizing || keypadResizeHover {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .accessibilityLabel(Text("Resize keypad"))
        .accessibilityHint(Text("Drag up or down to resize the keypad"))
    }

    private func historyOverlay(defaultHeight: CGFloat, windowHeight: CGFloat, panelHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            historyOverlayHeader(defaultHeight: defaultHeight, windowHeight: windowHeight)

            if viewModel.history.isEmpty {
                if didClearHistoryOverlay {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(macLocalized("history.empty", bundle: currentLocalizationBundle))
                        .font(EnterCalcFont.appFont(size: 15 * effectiveHistoryTextScale))
                        .foregroundStyle(fadedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.history) { entry in
                            HistoryEntryRow(
                                entry: entry,
                                primaryForeground: primaryForeground,
                                fadedForeground: fadedForeground,
                                tileBackground: memoryOverlayRowHoverColor,
                                textScale: effectiveHistoryTextScale,
                                onSelect: {
                                    viewModel.reuse(entry)
                                    closeHistoryOverlay()
                                },
                                onCopyOperation: {
                                    copyHistoryEntryOperationToPasteboard(entry)
                                }
                            )
                        }
                    }
                    .padding(.top, 2)
                    .padding(.leading, 12)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 0)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(memoryOverlayBackgroundColor)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10,
                style: .continuous
            )
        )
        .padding(.horizontal, -8)
        .padding(.bottom, -8)
        .onChange(of: viewModel.history.isEmpty) { _, isEmpty in
            if !isEmpty {
                didClearHistoryOverlay = false
            }
        }
        .frame(height: panelHeight, alignment: .top)
    }

    private func historyOverlayHeader(defaultHeight: CGFloat, windowHeight: CGFloat) -> some View {
        let headerControlSize: CGFloat = 32

        return ZStack {
            historyOverlayResizeHandle(defaultHeight: defaultHeight, windowHeight: windowHeight)

            HStack(spacing: 0) {
                if !viewModel.history.isEmpty {
                    floatingHistoryActionButton
                } else {
                    Color.clear
                        .frame(width: headerControlSize, height: headerControlSize)
                }

                Spacer(minLength: 0)
                floatingHistoryCloseButton
            }
        }
        .frame(height: headerControlSize)
    }

    private var floatingHistoryCloseButton: some View {
        Button {
            closeHistoryOverlay()
        } label: {
            Image(systemName: "xmark")
                .frame(width: 16, height: 16, alignment: .center)
                .padding(8)
                .background(historyCloseHover ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(macLocalized("close", bundle: currentLocalizationBundle))
        .accessibilityLabel(Text(macLocalized("close", bundle: currentLocalizationBundle)))
        .onHover { hovering in
            historyCloseHover = hovering
        }
    }

    private var floatingHistoryActionButton: some View {
        Button {
            if viewModel.history.isEmpty {
                withAnimation {
                    if usesCompactHistoryOverlay {
                        toggleHistoryOverlay()
                    } else {
                        handleHistoryToggle()
                    }
                    storeWindowSize()
                }
            } else {
                if usesCompactHistoryOverlay {
                    clearHistoryAfterClosingOverlay()
                } else {
                    didClearHistoryOverlay = true
                    viewModel.clearHistory()
                }
            }
        } label: {
            Image(systemName: "trash")
                .frame(width: 16, height: 16, alignment: .center)
                .padding(8)
                .background(historyTrashHover ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(macLocalized("history.clear", bundle: currentLocalizationBundle))
        .accessibilityLabel(Text(macLocalized("history.clear", bundle: currentLocalizationBundle)))
        .onHover { hovering in
            historyTrashHover = hovering
            if hovering {
                NSCursor.disappearingItem.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private func historyOverlayResizeHandle(defaultHeight: CGFloat, windowHeight: CGFloat) -> some View {
        let accentColor = palette.accent
        let handleColor = isResizingHistoryOverlay ? accentColor : palette.textSecondary.opacity(colorScheme == .dark ? 0.7 : 0.42)
        let lineColor = handleColor
        let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let maximumHeight = maximumHistoryOverlayHeight(windowHeight: windowHeight)
                let minimumHeight = minimumHistoryOverlayHeight(maximumHeight: maximumHeight)

                if !isResizingHistoryOverlay {
                    historyOverlayResizeStartHeight = resolvedHistoryOverlayHeight(defaultHeight: defaultHeight, windowHeight: windowHeight)
                    isResizingHistoryOverlay = true
                }

                let proposedHeight = historyOverlayResizeStartHeight - verticalLockedTranslation(value)
                historyOverlayHeight = roundedHistoryOverlayHeight(min(max(proposedHeight, minimumHeight), maximumHeight))
            }
            .onEnded { _ in
                let maximumHeight = maximumHistoryOverlayHeight(windowHeight: windowHeight)
                let minimumHeight = minimumHistoryOverlayHeight(maximumHeight: maximumHeight)
                let resolvedHeight = resolvedHistoryOverlayHeight(defaultHeight: defaultHeight, windowHeight: windowHeight)
                if abs(resolvedHeight - minimumHeight) < 1 {
                    historyOverlayHeight = nil
                    persistHistoryOverlayHeight(nil)
                } else {
                    persistHistoryOverlayHeight(resolvedHeight)
                }
                isResizingHistoryOverlay = false
            }

        let handleBackground = memoryOverlayBackgroundColor
        let handleWidth: CGFloat = 116

        let handle = ZStack {
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(lineColor)
                .frame(width: handleWidth)
                .frame(height: isResizingHistoryOverlay ? 2 : 1)

            Image(systemName: "arrow.up.arrow.down")
                .font(EnterCalcFont.appFont(size: 9))
                .foregroundStyle(handleColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(handleBackground)
                )
        }
        .frame(width: handleWidth, height: 32)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture)
        .onHover { hovering in
            historyResizeHover = hovering
            if hovering || isResizingHistoryOverlay {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onChange(of: isResizingHistoryOverlay) { _, isResizing in
            if isResizing || historyResizeHover {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .accessibilityLabel(Text("Resize history"))
        .accessibilityHint(Text("Drag up or down to resize the history overlay"))

        return handle
    }

    private var settingsOverlay: some View {
        makeSettingsSheet()
            .environment(\.macLocalizationBundle, currentLocalizationBundle)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(memoryOverlayBackgroundColor)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .padding(.horizontal, -8)
            .padding(.top, -8)
            .padding(.bottom, -8)
    }

    private func roundingOverlay() -> some View {
        MacRoundingPanel(
            palette: palette,
            overlayBackgroundColor: memoryOverlayBackgroundColor,
            isEnabled: viewModel.isResultRoundingEnabled,
            precision: viewModel.resultRoundingPrecision,
            maxPrecision: viewModel.maxResultRoundingPrecision,
            localizationBundle: currentLocalizationBundle,
            onSelectionChanged: { digits in
                if let digits {
                    viewModel.setResultRoundingPrecision(digits)
                } else {
                    viewModel.removeResultRounding()
                }
            },
            onDisableAndDismiss: {
                viewModel.removeResultRounding()
                closeRoundingOverlay()
            },
            onDismiss: { closeRoundingOverlay() }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setActiveOverlay(_ overlay: OverlayPane?) {
        if activeOverlay == .rounding, overlay != .rounding {
            viewModel.commitResultRoundingInteraction()
        }

        if reduceMotionEnabled {
            activeOverlay = overlay
        } else {
            withAnimation(.easeInOut) {
                activeOverlay = overlay
            }
        }
        if overlay != .history {
            isResizingHistoryOverlay = false
            historyResizeHover = false
            historyTrashHover = false
            historyCloseHover = false
            storedHistoryOpen = showHistory
        }
    }

    private func resolvedHistoryOverlayHeight(defaultHeight: CGFloat, windowHeight: CGFloat) -> CGFloat {
        let maximumHeight = maximumHistoryOverlayHeight(windowHeight: windowHeight)
        let minimumHeight = minimumHistoryOverlayHeight(maximumHeight: maximumHeight)
        guard let historyOverlayHeight else {
            return defaultHistoryOverlayHeight(defaultHeight: defaultHeight, windowHeight: windowHeight)
        }

        return min(max(historyOverlayHeight, minimumHeight), maximumHeight)
    }

    private func defaultHistoryOverlayHeight(defaultHeight: CGFloat, windowHeight: CGFloat) -> CGFloat {
        let maximumHeight = maximumHistoryOverlayHeight(windowHeight: windowHeight)
        let minimumHeight = minimumHistoryOverlayHeight(maximumHeight: maximumHeight)
        return min(defaultHeight, min(maximumHeight, minimumHeight * 1.5))
    }

    private func minimumHistoryOverlayHeight(maximumHeight: CGFloat) -> CGFloat {
        min(maximumHeight, 208)
    }

    private func maximumHistoryOverlayHeight(windowHeight: CGFloat) -> CGFloat {
        max(0, windowHeight * 0.8)
    }

    private func roundedHistoryOverlayHeight(_ height: CGFloat) -> CGFloat {
        height.rounded(.toNearestOrAwayFromZero)
    }

    private func setHistoryOverlayVisible(_ visible: Bool) {
        storedHistoryOpen = visible
        setActiveOverlay(visible ? .history : nil)
    }

    private func setRoundingOverlayVisible(_ visible: Bool) {
        if visible {
            viewModel.beginResultRounding()
        } else {
            viewModel.commitResultRoundingInteraction()
        }
        setActiveOverlay(visible ? .rounding : nil)
    }

    private func toggleHistoryOverlay() {
        setHistoryOverlayVisible(!showHistoryOverlay)
    }

    private func closeHistoryOverlay() {
        setHistoryOverlayVisible(false)
    }

    private func clearHistoryAfterClosingOverlay() {
        didClearHistoryOverlay = false
        closeHistoryOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            viewModel.clearHistory()
        }
    }

    private func toggleRoundingOverlay() {
        setRoundingOverlayVisible(!showRoundingOverlay)
    }

    private func closeRoundingOverlay() {
        setRoundingOverlayVisible(false)
    }

    private func openRoundingOverlayFromKeyboard() {
        guard !showRoundingOverlay else { return }
        setRoundingOverlayVisible(true)
    }

    private func adjustRoundingSelectionFromKeyboard(delta: Int) -> Bool {
        guard showRoundingOverlay else { return false }

        let currentStep = viewModel.isResultRoundingEnabled ? viewModel.resultRoundingPrecision : 0
        let maximumStep = viewModel.maxResultRoundingPrecision
        let nextStep = min(max(currentStep + delta, 0), maximumStep)

        guard nextStep != currentStep else { return true }

        if nextStep == 0 {
            viewModel.removeResultRounding()
        } else {
            viewModel.setResultRoundingPrecision(nextStep)
        }

        return true
    }

    private func handleRoundingOverlayKey(_ event: NSEvent) -> Bool {
        guard showRoundingOverlay else { return false }

        switch event.keyCode {
        case 126, 36, 76:
            closeRoundingOverlay()
            return true
        case 119:
            closeRoundingOverlay()
            return true
        case 125:
            // Already in the rounding overlay; no additional down-arrow action.
            return true
        case 51, 53, 117:
            viewModel.removeResultRounding()
            closeRoundingOverlay()
            return true
        default:
            return false
        }
    }

    private func handleHistoryOverlayKey(_ event: NSEvent) -> Bool {
        guard showHistoryOverlay else { return false }

        switch event.keyCode {
        case 53, 51, 36, 76, 119:
            closeHistoryOverlay()
            return true
        case 117:
            clearHistoryAfterClosingOverlay()
            return true
        default:
            // Suppress calculator input while history overlay is active.
            return true
        }
    }

    private func toggleHistoryVisibility() {
        withAnimation {
            userToggledHistory = true
            logUI("History toggle tapped (before) showHistory=\(showHistory) keyWindow#\(NSApp.keyWindow?.windowNumber ?? -1)")
            if usesCompactHistoryOverlay {
                toggleHistoryOverlay()
            } else {
                handleHistoryToggle()
            }
            storeWindowSize()
            logUI("History toggle tapped (after) showHistory=\(showHistory) keyWindow#\(NSApp.keyWindow?.windowNumber ?? -1)")
        }
    }

    private func setSettingsOverlayVisible(_ visible: Bool) {
        setActiveOverlay(visible ? .settings : nil)
    }

    private func toggleSettingsOverlay() {
        setSettingsOverlayVisible(!showSettingsOverlay)
    }

    private func closeSettingsOverlay() {
        setSettingsOverlayVisible(false)
    }

    private func closeActiveOverlay() {
        switch activeOverlay {
        case .history:
            closeHistoryOverlay()
        case .rounding:
            closeRoundingOverlay()
        case .settings:
            closeSettingsOverlay()
        case nil:
            break
        }
    }

    // Routes a hardware-keyboard event to a calculator action. Returns true when
    // handled so the event is consumed. Active overlays get first refusal.
    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let inputChars = event.characters ?? chars
        let insertFunctionCharacter = Character(UnicodeScalar(NSInsertFunctionKey)!)
        let isInsertKey = event.keyCode == 114
            || chars.contains(insertFunctionCharacter)
            || inputChars.contains(insertFunctionCharacter)
        DebugLog.emit(
            "KEY",
            "macOS key route keyCode:\(event.keyCode) modifiers:\(event.modifierFlags.rawValue) chars:\(debugKeyCharacters(event.charactersIgnoringModifiers)) input:\(debugKeyCharacters(event.characters)) insert:\(isInsertKey) overlay:\(String(describing: activeOverlay)) canEdit:\(viewModel.canDirectlyEditDisplay)"
        )
        var handled = false
        let isCommand = event.modifierFlags.contains(.command)

        if isCommand {
            if event.keyCode == 51 || event.keyCode == 117 { // Cmd + Backspace/Delete = clear all
                viewModel.clearAll()
                return true
            }
            switch chars.lowercased() {
            case "c":
                copyCurrentResultToPasteboard()
                return true
            case "v":
                viewModel.pasteFromPasteboard()
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    viewModel.redo()
                } else {
                    viewModel.undo()
                }
                return true
            case "y":
                viewModel.redo()
                return true
            default:
                return false
            }
        }

        if handleHistoryOverlayKey(event) {
            return true
        }

        if handleRoundingOverlayKey(event) {
            return true
        }

        if activeOverlay == nil, isInsertKey {
            guard viewModel.canDirectlyEditDisplay else {
                DebugLog.emit("KEY", "macOS insert detected but direct display editing is unavailable")
                return true
            }
            let trailingBoundary = Array(viewModel.display).count
            viewModel.setDisplayEditCursor(displayBoundaryIndex: trailingBoundary)
            DebugLog.emit("KEY", "macOS insert enabled display editing at boundary:\(trailingBoundary)")
            return true
        }

        if isInsertKey {
            DebugLog.emit("KEY", "macOS insert detected but blocked by active overlay:\(String(describing: activeOverlay))")
        }

        // Keypad support by keyCode
        switch event.keyCode {
        case 123:
            if !showRoundingOverlay {
                return viewModel.moveDisplayEditCursorLeft()
            }
            return adjustRoundingSelectionFromKeyboard(delta: -1)
        case 124:
            if !showRoundingOverlay {
                return viewModel.moveDisplayEditCursorRight()
            }
            return adjustRoundingSelectionFromKeyboard(delta: 1)
        case 125:
            openRoundingOverlayFromKeyboard()
            return true
        case 82: viewModel.inputDigit("0"); return true
        case 83: viewModel.inputDigit("1"); return true
        case 84: viewModel.inputDigit("2"); return true
        case 85: viewModel.inputDigit("3"); return true
        case 86: viewModel.inputDigit("4"); return true
        case 87: viewModel.inputDigit("5"); return true
        case 88: viewModel.inputDigit("6"); return true
        case 89: viewModel.inputDigit("7"); return true
        case 91: viewModel.inputDigit("8"); return true
        case 92: viewModel.inputDigit("9"); return true
        case 65: viewModel.inputDecimal(); return true // keypad .
        case 67: viewModel.setOperator(.multiply); return true
        case 69: viewModel.setOperator(.add); return true
        case 75: viewModel.setOperator(.divide); return true
        case 78: viewModel.setOperator(.subtract); return true
        case 81, 76:
            playEnterButtonSoundIfEnabled()
            viewModel.evaluate()
            return true // keypad = / enter
        default:
            break
        }

        if event.keyCode == 53 { // Escape
            if viewModel.isDirectlyEditingDisplay {
                viewModel.clearDisplayEditCursor()
                return true
            }
            viewModel.clearAll()
            return true
        }
        if event.keyCode == 119 { // End
            if viewModel.isDirectlyEditingDisplay {
                viewModel.clearDisplayEditCursor()
                return true
            }
            viewModel.clearAll()
            return true
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Backspace/Delete
            viewModel.backspace()
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 || chars == "=" { // Return / Enter / =
            if (event.keyCode == 36 || event.keyCode == 76), viewModel.isDirectlyEditingDisplay {
                viewModel.clearDisplayEditCursor()
                return true
            }
            playEnterButtonSoundIfEnabled()
            viewModel.evaluate()
            return true
        }

        switch inputChars {
        case "(":
            viewModel.inputParenthesis("(")
            handled = true
        case ")":
            viewModel.inputParenthesis(")")
            handled = true
        case "0","1","2","3","4","5","6","7","8","9":
            viewModel.inputDigit(inputChars)
            handled = true
        case "+": viewModel.setOperator(.add)
            handled = true
        case "-": viewModel.setOperator(.subtract)
            handled = true
        case "*", "x", "X": viewModel.setOperator(.multiply)
            handled = true
        case "/": viewModel.setOperator(.divide)
            handled = true
        case ".": viewModel.inputDecimal()
            handled = true
        case "%": viewModel.applyPercent()
            handled = true
        case "$", "€", "£", "¥", "₹", "₩", "₽", "฿", "₺", "₫", "₴", "₪", "₦", "₱", "₲", "₡", "₵", "₭", "₮", "₤", "₳", "₸", "₼", "₾", "₣", "₠", "₧", "₯", "₿":
            viewModel.inputCurrencySymbol(inputChars)
            handled = true
        default:
            break
        }

        return handled
    }

    private func playEnterButtonSoundIfEnabled() {
        guard !windowSettings.disablesButtonSound else {
            return
        }

        CalculatorButtonSound.playEnterClick()
    }

    // MARK: - Button metadata

    private struct ButtonItem {
        let title: String
        let kind: CalculatorButton.Kind
        let action: () -> Void
        let enabled: Bool
        let columnSpan: Int

        init(
            title: String,
            kind: CalculatorButton.Kind,
            action: @escaping () -> Void,
            enabled: Bool,
            columnSpan: Int = 1
        ) {
            self.title = title
            self.kind = kind
            self.action = action
            self.enabled = enabled
            self.columnSpan = columnSpan
        }
    }

    private struct CompactActionItem {
        let symbol: String
        let accessibilityLabel: String
        let isBare: Bool
        let action: (() -> Void)?
    }

    // Selects the active keypad layout based on the user's preference.
    private func keypadButtons() -> [ButtonItem] {
        windowSettings.usesAlternativeKeypad ? legacyKeypadButtons() : basicKeypadButtons()
    }

    // Full keypad including scientific functions (1/x, x squared, square root).
    // In error state only digits and clear/parenthesis keys stay enabled.
    private func legacyKeypadButtons() -> [ButtonItem] {
        let errorMode = viewModel.isErrorState
        func isEnabled(title: String, kind: CalculatorButton.Kind) -> Bool {
            guard errorMode else { return true }
            let allowedTitles: Set<String> = ["C", "AC", "( )", "⌫", ".", "0","1","2","3","4","5","6","7","8","9"]
            if allowedTitles.contains(title) { return true }
            return kind == .number
        }

        let clearButtonTitle = viewModel.shouldShowAllClearButton ? "AC" : "C"

        return [
            ButtonItem(title: clearButtonTitle, kind: .function, action: { self.handleContextualClear() }, enabled: isEnabled(title: clearButtonTitle, kind: .function)),
            ButtonItem(title: "( )", kind: .function, action: { viewModel.inputParentheses() }, enabled: isEnabled(title: "( )", kind: .function)),
            ButtonItem(title: "%", kind: .function, action: { viewModel.applyPercent() }, enabled: isEnabled(title: "%", kind: .function)),
            ButtonItem(title: "⌫", kind: .function, action: { viewModel.backspace() }, enabled: isEnabled(title: "⌫", kind: .function)),
            ButtonItem(title: "1/x", kind: .function, action: { viewModel.reciprocal() }, enabled: isEnabled(title: "1/x", kind: .function)),
            ButtonItem(title: "x²", kind: .function, action: { viewModel.square() }, enabled: isEnabled(title: "x²", kind: .function)),
            ButtonItem(title: "√x", kind: .function, action: { viewModel.squareRoot() }, enabled: isEnabled(title: "√x", kind: .function)),
            ButtonItem(title: "÷", kind: .operation, action: { viewModel.setOperator(.divide) }, enabled: isEnabled(title: "÷", kind: .operation)),
            ButtonItem(title: "7", kind: .number, action: { viewModel.inputDigit("7") }, enabled: isEnabled(title: "7", kind: .number)),
            ButtonItem(title: "8", kind: .number, action: { viewModel.inputDigit("8") }, enabled: isEnabled(title: "8", kind: .number)),
            ButtonItem(title: "9", kind: .number, action: { viewModel.inputDigit("9") }, enabled: isEnabled(title: "9", kind: .number)),
            ButtonItem(title: "×", kind: .operation, action: { viewModel.setOperator(.multiply) }, enabled: isEnabled(title: "×", kind: .operation)),
            ButtonItem(title: "4", kind: .number, action: { viewModel.inputDigit("4") }, enabled: isEnabled(title: "4", kind: .number)),
            ButtonItem(title: "5", kind: .number, action: { viewModel.inputDigit("5") }, enabled: isEnabled(title: "5", kind: .number)),
            ButtonItem(title: "6", kind: .number, action: { viewModel.inputDigit("6") }, enabled: isEnabled(title: "6", kind: .number)),
            ButtonItem(title: "−", kind: .operation, action: { viewModel.setOperator(.subtract) }, enabled: isEnabled(title: "−", kind: .operation)),
            ButtonItem(title: "1", kind: .number, action: { viewModel.inputDigit("1") }, enabled: isEnabled(title: "1", kind: .number)),
            ButtonItem(title: "2", kind: .number, action: { viewModel.inputDigit("2") }, enabled: isEnabled(title: "2", kind: .number)),
            ButtonItem(title: "3", kind: .number, action: { viewModel.inputDigit("3") }, enabled: isEnabled(title: "3", kind: .number)),
            ButtonItem(title: "+", kind: .operation, action: { viewModel.setOperator(.add) }, enabled: isEnabled(title: "+", kind: .operation)),
            ButtonItem(title: "+/−", kind: .function, action: { viewModel.toggleSign() }, enabled: isEnabled(title: "+/−", kind: .function)),
            ButtonItem(title: "0", kind: .number, action: { viewModel.inputDigit("0") }, enabled: isEnabled(title: "0", kind: .number)),
            ButtonItem(title: ".", kind: .number, action: { viewModel.inputDecimal() }, enabled: isEnabled(title: ".", kind: .number)),
            ButtonItem(
                title: equalsButtonTitle,
                kind: .accent,
                action: { viewModel.evaluate() },
                enabled: isEnabled(title: equalsButtonTitle, kind: .accent)
            )
        ]
    }

    // Simplified keypad (the alternative layout) without the scientific row.
    private func basicKeypadButtons() -> [ButtonItem] {
        let errorMode = viewModel.isErrorState
        func isEnabled(title: String, kind: CalculatorButton.Kind) -> Bool {
            guard errorMode else { return true }
            let allowedTitles: Set<String> = ["C", "AC", "( )", ".", "0","1","2","3","4","5","6","7","8","9"]
            if allowedTitles.contains(title) { return true }
            return kind == .number
        }

        let clearButtonTitle = viewModel.shouldShowAllClearButton ? "AC" : "C"

        return [
            ButtonItem(title: clearButtonTitle, kind: .function, action: { self.handleContextualClear() }, enabled: isEnabled(title: clearButtonTitle, kind: .function)),
            ButtonItem(title: "( )", kind: .function, action: { viewModel.inputParentheses() }, enabled: isEnabled(title: "( )", kind: .function)),
            ButtonItem(title: "%", kind: .function, action: { viewModel.applyPercent() }, enabled: isEnabled(title: "%", kind: .function)),
            ButtonItem(title: "÷", kind: .operation, action: { viewModel.setOperator(.divide) }, enabled: isEnabled(title: "÷", kind: .operation)),
            ButtonItem(title: "7", kind: .number, action: { viewModel.inputDigit("7") }, enabled: isEnabled(title: "7", kind: .number)),
            ButtonItem(title: "8", kind: .number, action: { viewModel.inputDigit("8") }, enabled: isEnabled(title: "8", kind: .number)),
            ButtonItem(title: "9", kind: .number, action: { viewModel.inputDigit("9") }, enabled: isEnabled(title: "9", kind: .number)),
            ButtonItem(title: "×", kind: .operation, action: { viewModel.setOperator(.multiply) }, enabled: isEnabled(title: "×", kind: .operation)),
            ButtonItem(title: "4", kind: .number, action: { viewModel.inputDigit("4") }, enabled: isEnabled(title: "4", kind: .number)),
            ButtonItem(title: "5", kind: .number, action: { viewModel.inputDigit("5") }, enabled: isEnabled(title: "5", kind: .number)),
            ButtonItem(title: "6", kind: .number, action: { viewModel.inputDigit("6") }, enabled: isEnabled(title: "6", kind: .number)),
            ButtonItem(title: "−", kind: .operation, action: { viewModel.setOperator(.subtract) }, enabled: isEnabled(title: "−", kind: .operation)),
            ButtonItem(title: "1", kind: .number, action: { viewModel.inputDigit("1") }, enabled: isEnabled(title: "1", kind: .number)),
            ButtonItem(title: "2", kind: .number, action: { viewModel.inputDigit("2") }, enabled: isEnabled(title: "2", kind: .number)),
            ButtonItem(title: "3", kind: .number, action: { viewModel.inputDigit("3") }, enabled: isEnabled(title: "3", kind: .number)),
            ButtonItem(title: "+", kind: .operation, action: { viewModel.setOperator(.add) }, enabled: isEnabled(title: "+", kind: .operation)),
            ButtonItem(title: ".", kind: .number, action: { viewModel.inputDecimal() }, enabled: isEnabled(title: ".", kind: .number)),
            ButtonItem(title: "0", kind: .number, action: { viewModel.inputDigit("0") }, enabled: isEnabled(title: "0", kind: .number)),
            ButtonItem(
                title: equalsButtonTitle,
                kind: .accent,
                action: { viewModel.evaluate() },
                enabled: isEnabled(title: equalsButtonTitle, kind: .accent),
                columnSpan: 2
            )
        ]
    }

    private func compactActionRowButtons() -> [CompactActionItem] {
        guard !windowSettings.usesAlternativeKeypad else { return [] }
        return [
            CompactActionItem(symbol: "arrow.uturn.backward", accessibilityLabel: macLocalized("undo", bundle: currentLocalizationBundle), isBare: false, action: { viewModel.undo() }),
            CompactActionItem(symbol: "arrow.uturn.forward", accessibilityLabel: macLocalized("redo", bundle: currentLocalizationBundle), isBare: false, action: { viewModel.redo() }),
            CompactActionItem(symbol: "plusminus", accessibilityLabel: macLocalized("toggleSign", bundle: currentLocalizationBundle), isBare: false, action: { viewModel.toggleSign() }),
            CompactActionItem(symbol: "slider.horizontal.below.rectangle", accessibilityLabel: macLocalized("rounding.toggle", bundle: currentLocalizationBundle), isBare: false, action: { toggleRoundingOverlay() }),
            CompactActionItem(symbol: "delete.left", accessibilityLabel: macLocalized("backspace", bundle: currentLocalizationBundle), isBare: false, action: { viewModel.backspace() })
        ]
    }

    private func handleContextualClear() {
        viewModel.clearEntry()
    }

    // MARK: - Colors

    private var surfaceColor: Color { palette.surface }
    private var panelColor: Color { palette.panel }
    private var fadedForeground: Color { palette.textSecondary }

    private var primaryForeground: Color { palette.textPrimary }
    private var memoryOverlayBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 29.0 / 255.0)
        }
        return Color(red: 241.0 / 255.0, green: 241.0 / 255.0, blue: 241.0 / 255.0)
    }

    private var memoryOverlayRowBackgroundColor: Color { palette.historyTileBackground }

    private var memoryOverlayRowHoverColor: Color {
        palette.historyTileBackground
    }

    private var overlayScrimOpacity: Double { 0.35 }
}

private struct MemoryControlsBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct CompactActionButton: View {
    let symbol: String
    let accessibilityLabel: String
    let isBare: Bool
    let height: CGFloat
    let disabled: Bool
    let palette: Palette
    let action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var controlDynamicTypeScale: CGFloat = 1.0
    @State private var hovering: Bool = false

    private var cornerRadius: CGFloat { min(max(height * 0.28, 5), 10) }

    var body: some View {
        Group {
            if disabled {
                Color.clear
            } else {
                Button(action: action) {
                    Image(systemName: symbol)
                        .font(EnterCalcFont.appFont(size: boundedIconFontSize))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(accessibilityLabel))
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.buttonHoverOverlay)
                        .opacity(hovering ? 1.0 : 0.0)
                        .allowsHitTesting(false)
                )
                .onHover { hovering in
                    self.hovering = hovering
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
            }
        }
        .frame(height: height)
    }

    private var boundedIconFontSize: CGFloat {
        let effectiveControlScale = max(
            controlDynamicTypeScale,
            macPreferredTextScale(for: .title2, baseline: 22)
        )
        let baseSize = min(max(height * 0.52, 11), 17)
        let maxSize = max(baseSize, height * 0.82)
        return min(max(baseSize, baseSize * effectiveControlScale), maxSize)
    }

    @ViewBuilder
    private var background: some View {
        if isBare {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.buttonOperation)
        }
    }
}

// MARK: - Button view

    private struct CalculatorButton: View {
        enum Kind {
            case number
            case function
            case operation
            case accent
        }

        let title: String
        let kind: Kind
        let height: CGFloat
        let disablesButtonSound: Bool
        let action: () -> Void
        let enabled: Bool
        let palette: Palette
        var operatorRevealProgress: Double = 0.0
        var operatorAnimFadeOpacity: Double = 1.0
        var reduceMotionEnabled: Bool = false
        @ScaledMetric(relativeTo: .title2) private var controlDynamicTypeScale: CGFloat = 1.0

        @State private var hovering: Bool = false
        @State private var shimmerProgress: CGFloat = 0
        @State private var shimmerVisible: Bool = false
        @State private var pressPopScale: CGFloat = 1.0
        @State private var pointerIsDown: Bool = false
        @State private var pressPopGeneration: Int = 0
        private static let popGrowDuration: TimeInterval = 0.05
        private static let popSpringResponse: Double = 0.18
        private static let popSpringDamping: Double = 0.62
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            Button(action: handleTap) {
                labelView
                    .scaleEffect(x: horizontalScale, y: 1.0, anchor: .center)
                    .scaleEffect(pressPopScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text(title))
            .background(buttonBackground)
            .foregroundStyle(foregroundColor)
            .opacity(enabled ? 1.0 : 0.35)
            .frame(height: max(height, 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hoverOverlay)
                    .opacity(hovering ? 1.0 : 0.0)
                    .allowsHitTesting(false)
            )
            .overlay {
                if kind == .accent && shimmerVisible {
                    GeometryReader { geo in
                        let diagonal = (geo.size.width * geo.size.width + geo.size.height * geo.size.height).squareRoot()
                        let travel = diagonal * 3.0
                        let offset = (0.5 - shimmerProgress) * travel

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0),
                                                Color.white.opacity(0.58),
                                                Color.white.opacity(0)
                                            ],
                                            startPoint: .bottomTrailing,
                                            endPoint: .topLeading
                                        )
                                    )
                                            .frame(width: max(diagonal * 2.2, 60), height: diagonal * 3.2)
                                    .rotationEffect(.degrees(-36))
                                    .offset(x: offset, y: offset)
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .zIndex(pressPopScale > 1.001 ? 1 : 0)
            .disabled(!enabled)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pointerIsDown else { return }
                        pointerIsDown = true
                        triggerPressPopAnimation()
                    }
                    .onEnded { _ in
                        pointerIsDown = false
                    }
            )
            .onHover { hovering in
                self.hovering = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }

        private func handleTap() {
            MacButtonSoundFeedback.playIfNeeded(disabled: disablesButtonSound, isEnterKey: kind == .accent)
            action()
            guard kind == .accent, !reduceMotionEnabled else { return }
            shimmerProgress = 0
            shimmerVisible = true
            withAnimation(.linear(duration: 0.17)) {
                shimmerProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                shimmerVisible = false
            }
        }

        private func triggerPressPopAnimation() {
            guard !reduceMotionEnabled else { return }
            pressPopGeneration += 1
            let currentGeneration = pressPopGeneration

            withAnimation(.easeOut(duration: Self.popGrowDuration)) {
                pressPopScale = 1.15
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.popGrowDuration) {
                guard currentGeneration == pressPopGeneration else { return }
                withAnimation(.spring(response: Self.popSpringResponse, dampingFraction: Self.popSpringDamping)) {
                    pressPopScale = 1.0
                }
            }
        }

        private var backgroundColor: Color {
            switch kind {
            case .accent:
                return palette.accent
            case .operation, .function:
                return palette.buttonOperation
            case .number:
                return palette.buttonNumber
            }
        }

        private var borderColor: Color {
            palette.buttonBorder
        }

        private var horizontalScale: CGFloat {
            kind == .accent ? 1.2 : 1.0
        }

        private var foregroundColor: Color {
            switch kind {
            case .accent:
                return palette.accentText
            default:
                return palette.textPrimary
            }
        }

        private static let operatorRevealOrder: [String: Int] = ["+": 0, "−": 1, "×": 2, "÷": 3]

        private var backgroundStyle: AnyShapeStyle {
            AnyShapeStyle(backgroundColor)
        }

        private var accentButtonGradient: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: palette.accentGradientStart, location: 0.0),
                    .init(color: palette.accentGradientMid, location: 0.42),
                    .init(color: palette.accentGradientEnd, location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        @ViewBuilder
        private var buttonBackground: some View {
            if kind == .accent {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accentButtonGradient)
            } else if let revealOrder = Self.operatorRevealOrder[title],
               let gradColor = palette.operatorColumnColor(for: title) {
                let overlayOpacity = min(1.0, max(0.0, operatorRevealProgress - Double(revealOrder))) * operatorAnimFadeOpacity
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundColor)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(gradColor)
                        .opacity(overlayOpacity)
                }
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundStyle)
            }
        }

        private var hoverOverlay: Color {
            palette.buttonHoverOverlay
        }

        private var primaryFontSize: CGFloat {
            let effectiveControlScale = max(
                controlDynamicTypeScale,
                macPreferredTextScale(for: .title2, baseline: 22)
            )
            let baseSize = min(max(height * 0.38, 14), 28)
            let maxSize = max(baseSize, height * 0.82)
            return min(max(baseSize, baseSize * effectiveControlScale), maxSize)
        }

        private var boundedIconSquareSize: CGFloat {
            min(max(primaryFontSize * 1.35, 22), height * 0.9)
        }

        private var enterKeyTextFontSize: CGFloat {
            let normalizedProgress = min(max((primaryFontSize - 14) / 14, 0), 1)
            return 10 + normalizedProgress * 18
        }

        private var isEnterKeyTextButton: Bool {
            kind == .accent && title != "="
        }

        @ViewBuilder
        private var labelView: some View {
            if title == "1/x" {
                let iconWidth = boundedIconSquareSize
                let iconHeight = boundedIconSquareSize
                let iconFrameWidth = iconWidth
                let iconFrameHeight = iconHeight
                let iconScaleX: CGFloat = 0.94
                let iconScaleY: CGFloat = 0.94
                let iconOffsetX: CGFloat = 0
                let iconOffsetY: CGFloat = -0.1

                Image("one-over-x", bundle: .enterCalcCore)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconWidth, height: iconHeight)
                    .frame(width: iconFrameWidth, height: iconFrameHeight)
                    .scaleEffect(x: iconScaleX, y: iconScaleY)
                    .offset(x: iconOffsetX, y: iconOffsetY)
            } else if title == "x²" {
                let iconWidth = boundedIconSquareSize
                let iconHeight = boundedIconSquareSize
                let iconFrameWidth = iconWidth
                let iconFrameHeight = iconHeight
                let iconScaleX: CGFloat = 0.9
                let iconScaleY: CGFloat = 0.9
                let iconOffsetX: CGFloat = 0
                let iconOffsetY: CGFloat = -0.15

                Image("x-squared", bundle: .enterCalcCore)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconWidth, height: iconHeight)
                    .frame(width: iconFrameWidth, height: iconFrameHeight)
                    .scaleEffect(x: iconScaleX, y: iconScaleY)
                    .offset(x: iconOffsetX, y: iconOffsetY)
            } else if title == "+/−" {
                let secondaryFontSize = min(max(primaryFontSize * 0.74, 10), height * 0.62)
                let slashFontSize = min(max(primaryFontSize * 0.95, 14), height * 0.78)

                HStack(spacing: 0) {
                    Text("+")
                        .font(EnterCalcFont.thinAppFont(size: secondaryFontSize * 0.9))
                        .offset(x: -0.2, y: -0.1)
                    Text("/")
                        .font(EnterCalcFont.thinAppFont(size: slashFontSize))
                        .offset(x: 0, y: -0.15)
                    Text("−")
                        .font(EnterCalcFont.thinAppFont(size: secondaryFontSize * 0.9))
                        .offset(x: 0.2, y: 0.1)
                }
                .offset(x: 0, y: -0.2)
            } else if title == "√x" {
                let iconWidth = boundedIconSquareSize
                let iconHeight = boundedIconSquareSize
                let iconFrameWidth = iconWidth
                let iconFrameHeight = iconHeight
                let iconScaleX: CGFloat = 0.92
                let iconScaleY: CGFloat = 0.92
                let iconOffsetX: CGFloat = 0.15
                let iconOffsetY: CGFloat = -0.05

                Image("square-root", bundle: .enterCalcCore)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconWidth, height: iconHeight)
                    .frame(width: iconFrameWidth, height: iconFrameHeight)
                    .scaleEffect(x: iconScaleX, y: iconScaleY)
                    .offset(x: iconOffsetX, y: iconOffsetY)
            } else {
                baseLabel
            }
        }

        private var baseLabel: some View {
            Text(title)
                .font(EnterCalcFont.thinAppFont(size: isEnterKeyTextButton ? enterKeyTextFontSize : primaryFontSize))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

// MARK: - History UI

// Scrollable list of past calculations shown in the history overlay. Tapping a
// row reuses that entry; the trash button clears all history.
private struct HistoryPanel: View {
    let entries: [HistoryEntry]
    let onSelect: (HistoryEntry) -> Void
    let onClear: () -> Void
    let onCopyOperation: (HistoryEntry) -> Void
    let palette: Palette
    let textScale: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macLocalizationBundle) private var localizationBundle
    @State private var hoverState: Bool = false
    @State private var didClearHistoryInPanel: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(macLocalized("history.title", bundle: localizationBundle))
                    .font(EnterCalcFont.appFont(size: 17 * textScale))
                    .foregroundStyle(primaryForeground)
                Spacer()
                if !entries.isEmpty {
                    Button {
                        DebugLog.emit("UI", "History clear tapped")
                        didClearHistoryInPanel = true
                        onClear()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 16, height: 16, alignment: .center)
                            .padding(6)
                            .background(hoverState ? hoverBackground : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(primaryForeground)
                    .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .onHover { hovering in
                        hoverState = hovering
                        hovering ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
                    }
                    .help(macLocalized("history.clear", bundle: localizationBundle))
                    .accessibilityLabel(Text(macLocalized("history.clear", bundle: localizationBundle)))
                }
            }

            if entries.isEmpty {
                let emptyHistoryMessage = macLocalized(didClearHistoryInPanel ? "history.emptyAfterClear" : "history.empty", bundle: localizationBundle)
                if emptyHistoryMessage.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(emptyHistoryMessage)
                        .font(EnterCalcFont.appFont(size: 15 * textScale))
                        .foregroundStyle(fadedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: didClearHistoryInPanel ? .top : .center)
                        .padding(.top, didClearHistoryInPanel ? 6 : 0)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            HistoryEntryRow(
                                entry: entry,
                                primaryForeground: primaryForeground,
                                fadedForeground: fadedForeground,
                                tileBackground: historyTileBackground,
                                textScale: textScale,
                                onSelect: { onSelect(entry) },
                                onCopyOperation: {
                                    onCopyOperation(entry)
                                }
                            )
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 12)
                }
            }
        }
        .onChange(of: entries.count) { _, count in
            if count > 0 {
                didClearHistoryInPanel = false
            }
        }
        .padding(6)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(historyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var primaryForeground: Color { palette.textPrimary }

    private var fadedForeground: Color { palette.textSecondary }

    private var historyBackground: Color { palette.historyBackground }

    private var historyTileBackground: Color { palette.historyTileBackground }

    private var hoverBackground: Color { palette.headerHover }
}

// A single history row: the operation on top, the result below. Right-click
// offers "Copy Operation".
private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let primaryForeground: Color
    let fadedForeground: Color
    let tileBackground: Color
    let textScale: CGFloat
    let onSelect: () -> Void
    let onCopyOperation: () -> Void
    @Environment(\.macLocalizationBundle) private var localizationBundle
    @State private var isHovering: Bool = false

    var body: some View {
        let expressionFontSize = 12 * textScale
        let resultFontSize = 16 * textScale

        VStack(alignment: .trailing, spacing: 3) {
            Text("\(entry.displayExpression)\(entry.displayExpression.contains("≈") ? "" : " =")")
                .font(EnterCalcFont.appFont(size: expressionFontSize))
                .foregroundStyle(fadedForeground)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(entry.displayResult)
                .font(EnterCalcFont.appFont(size: resultFontSize))
                .foregroundStyle(primaryForeground)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .background(isHovering ? tileBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture { onSelect() }
        .contextMenu {
            Button(action: onCopyOperation) {
                Label(macLocalized("history.copyOperation", bundle: localizationBundle), systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Settings Sheet and helpers

// Builds the localized strings shown in the macOS About window (title, version,
// and the credit/attribution text).
enum MacAboutContent {
    static func aboutWindowTitle(bundle: Bundle?) -> String {
        String(format: macLocalized("mac.about.windowTitle", bundle: bundle), appName)
    }

    static var appName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }

        return "EnterCalc"
    }

    static func creditAttributedString(bundle: Bundle?) -> AttributedString {
        let part1 = AttributedString(macLocalized("settings.credit.part1", bundle: bundle))
        var linkText = AttributedString(macLocalized("settings.credit.linkText", bundle: bundle))
        linkText.link = URL(string: "https://github.com/tipliai/enterCalc")!
        let middle = AttributedString(macLocalized("settings.credit.middle", bundle: bundle))

        return part1 + linkText + middle
    }

    static func appVersionText(bundle: Bundle?) -> String {
        String(format: macLocalized("settings.credits.version", bundle: bundle), versionString)
    }

    private static var versionString: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !version.isEmpty {
            return version
        }
        if let envVersion = ProcessInfo.processInfo.environment["WIN_CALC_VERSION"],
           !envVersion.isEmpty {
            return envVersion
        }
        return "Version unavailable"
    }

}

// Content of the separate About window opened from the app menu.
struct MacAboutView: View {
    @Environment(\.macLocalizationBundle) private var localizationBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(MacAboutContent.appName)
                        .font(.system(size: 22))
                    Text(MacAboutContent.appVersionText(bundle: localizationBundle))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(macLocalized("settings.credits", bundle: localizationBundle))
                    .font(.system(size: 17))
                Text(MacAboutContent.creditAttributedString(bundle: localizationBundle))
                    .font(.system(size: 15))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
    }
}

// Settings overlay form. Edits are bound back to the owning window's settings;
// the parent persists them and re-applies theme/language live.
private struct SettingsSheet: View {
    @Binding var selectedTheme: AppTheme
    @Binding var selectedLanguage: String
    @Binding var usesScientificNotation: Bool
    @Binding var selectedNumberFormat: NumberFormatStyle
    @Binding var usesAlternativeKeypad: Bool
    @Binding var disablesSwipeDownToRound: Bool
    @Binding var disablesButtonSound: Bool
    let availableLanguages: [LanguageOption]
    let onClose: () -> Void
    @Environment(\.macLocalizationBundle) private var localizationBundle

    private var settingsTextScale: CGFloat {
        macPreferredTextScale(for: .body, baseline: 13)
    }

    private var settingsTitleSize: CGFloat { (NSFont.systemFontSize + 1) * settingsTextScale }
    private var settingsSectionSize: CGFloat { NSFont.systemFontSize * settingsTextScale }
    private var settingsBodySize: CGFloat { NSFont.systemFontSize * settingsTextScale }
    private var settingsSecondarySize: CGFloat { NSFont.smallSystemFontSize * settingsTextScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(macLocalized("settings.title", bundle: localizationBundle))
                    .font(.system(size: settingsTitleSize))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: settingsBodySize))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(macLocalized("settings.close", bundle: localizationBundle)))
            }

            Divider()
                .padding(.top, 16)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(macLocalized("settings.appearance.label", bundle: localizationBundle), selection: $selectedTheme) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Text(theme.label(using: localizationBundle)).tag(theme)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: settingsBodySize))
                        .id(selectedLanguage) // force refresh of localized labels on change
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Picker(macLocalized("settings.language.label", bundle: localizationBundle), selection: $selectedLanguage) {
                            ForEach(availableLanguages, id: \.code) { lang in
                                Text(lang.displayName).tag(lang.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: settingsBodySize))

                        Picker(macLocalized("settings.numberFormat.style", bundle: localizationBundle), selection: $selectedNumberFormat) {
                            ForEach(NumberFormatStyle.allCases, id: \.self) { style in
                                Text(style.example).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: settingsBodySize))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(macLocalized("settings.userInterface", bundle: localizationBundle))
                            .font(.system(size: settingsSectionSize))
                        Toggle(macLocalized("settings.numberFormat.scientific", bundle: localizationBundle), isOn: $usesScientificNotation)
                            .font(.system(size: settingsBodySize))
                        Toggle(macLocalized("settings.percent.classicBehavior", bundle: localizationBundle), isOn: $usesAlternativeKeypad)
                            .font(.system(size: settingsBodySize))
                        Toggle(macLocalized("settings.buttonSound.disabled", bundle: localizationBundle), isOn: $disablesButtonSound)
                            .font(.system(size: settingsBodySize))
                        Toggle(macLocalized("settings.rounding.disableSwipeDown", bundle: localizationBundle), isOn: $disablesSwipeDownToRound)
                            .font(.system(size: settingsBodySize))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(macLocalized("settings.credits", bundle: localizationBundle))
                            .font(.system(size: settingsSectionSize))
                        // Version and the rating link share a row, matching iOS.
                        HStack(spacing: 12) {
                            Text(MacAboutContent.appVersionText(bundle: localizationBundle))
                                .font(.system(size: settingsBodySize))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            Link(
                                macLocalized("settings.feedback", bundle: localizationBundle),
                                destination: SupportLinks.supportURL
                            )
                            .font(.system(size: settingsBodySize))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Custom slider that selects result rounding precision (significant digits) or
// turns rounding off at the far end.
private struct MacRoundingPanel: View {
    let palette: Palette
    let overlayBackgroundColor: Color
    let isEnabled: Bool
    let precision: Int
    let maxPrecision: Int
    let localizationBundle: Bundle?
    let onSelectionChanged: (Int?) -> Void
    let onDisableAndDismiss: () -> Void
    let onDismiss: () -> Void
    @State private var sliderValue: Double
    @State private var isTrashHovering: Bool = false
    @State private var isCloseHovering: Bool = false

    private static let exponentialK: Double = -0.15234446585900155
    private static let exponentialDomainMax: Double = 16
    private static let offStepIndex: Int = 0

    private var maximumStepIndex: Int {
        min(maxPrecision, Int(Self.exponentialDomainMax))
    }

    private var allStepIndices: [Int] {
        Array(Self.offStepIndex...maximumStepIndex)
    }

    init(
        palette: Palette,
        overlayBackgroundColor: Color,
        isEnabled: Bool,
        precision: Int,
        maxPrecision: Int,
        localizationBundle: Bundle?,
        onSelectionChanged: @escaping (Int?) -> Void,
        onDisableAndDismiss: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.palette = palette
        self.overlayBackgroundColor = overlayBackgroundColor
        self.isEnabled = isEnabled
        self.precision = precision
        self.maxPrecision = max(0, maxPrecision)
        self.localizationBundle = localizationBundle
        self.onSelectionChanged = onSelectionChanged
        self.onDisableAndDismiss = onDisableAndDismiss
        self.onDismiss = onDismiss
        let initialPosition = MacRoundingPanel.sliderPosition(
            for: MacRoundingPanel.stepIndex(isEnabled: isEnabled, precision: precision, maxPrecision: max(0, maxPrecision))
        )
        _sliderValue = State(initialValue: initialPosition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundingOverlayHeader

            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { newValue in
                        let clamped = min(max(newValue, 0), 1)
                        let snappedStepIndex = stepIndex(for: clamped)
                        let snappedPosition = sliderPosition(for: snappedStepIndex)
                        guard snappedPosition != sliderValue else { return }
                        sliderValue = snappedPosition
                        onSelectionChanged(digits(for: snappedStepIndex))
                    }
                ),
                in: 0...1
            )

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(allStepIndices, id: \.self) { stepIndex in
                        if stepIndex == Self.offStepIndex {
                            Image(systemName: "power")
                                .font(.system(size: NSFont.smallSystemFontSize))
                                .foregroundStyle(.secondary)
                                .offset(x: offIconOffset(width: geometry.size.width), y: -3)
                        } else {
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 2, height: 5)
                                .offset(x: tickOffset(for: stepIndex, width: geometry.size.width))
                        }
                    }
                }
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 5)
        .padding(.top, 0)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(overlayBackgroundColor)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10,
                style: .continuous
            )
        )
        .padding(.horizontal, -8)
        .padding(.bottom, -8)
        .onChange(of: precision) { _, newValue in
            sliderValue = sliderPosition(for: Self.stepIndex(isEnabled: isEnabled, precision: newValue, maxPrecision: maxPrecision))
        }
        .onChange(of: isEnabled) { _, newValue in
            sliderValue = sliderPosition(for: Self.stepIndex(isEnabled: newValue, precision: precision, maxPrecision: maxPrecision))
        }
    }

    private var roundingOverlayHeader: some View {
        let headerControlSize: CGFloat = 32

        return ZStack {
            Text(macLocalized("rounding.title", bundle: localizationBundle))
                .font(EnterCalcFont.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 0) {
                disableAndDismissButton
                Spacer(minLength: 0)
                dismissButton
            }
        }
        .frame(height: headerControlSize)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .frame(width: 16, height: 16, alignment: .center)
                .padding(8)
                .background(isCloseHovering ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(macLocalized("close", bundle: localizationBundle))
        .accessibilityLabel(Text(macLocalized("close", bundle: localizationBundle)))
        .onHover { hovering in
            isCloseHovering = hovering
        }
    }

    private var disableAndDismissButton: some View {
        Button(action: onDisableAndDismiss) {
            Image(systemName: "trash")
                .frame(width: 16, height: 16, alignment: .center)
                .padding(8)
                .background(isTrashHovering ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(macLocalized("rounding.remove", bundle: localizationBundle))
        .accessibilityLabel(Text(macLocalized("rounding.remove", bundle: localizationBundle)))
        .onHover { hovering in
            isTrashHovering = hovering
            if hovering {
                NSCursor.disappearingItem.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private func sliderPosition(for stepIndex: Int) -> Double {
        Self.sliderPosition(for: stepIndex)
    }

    private func stepIndex(for normalizedPosition: Double) -> Int {
        let clamped = min(max(normalizedPosition, 0), 1)
        if allStepIndices.isEmpty {
            return Self.offStepIndex
        }

        var nearestStepIndex = allStepIndices[0]
        var nearestDistance = abs(clamped - sliderPosition(for: nearestStepIndex))

        for candidate in allStepIndices.dropFirst() {
            let candidateDistance = abs(clamped - sliderPosition(for: candidate))
            if candidateDistance < nearestDistance {
                nearestDistance = candidateDistance
                nearestStepIndex = candidate
            }
        }

        return nearestStepIndex
    }

    private func digits(for stepIndex: Int) -> Int? {
        guard stepIndex != Self.offStepIndex else { return nil }
        return min(stepIndex, min(maxPrecision, Int(Self.exponentialDomainMax)))
    }

    private func tickOffset(for stepIndex: Int, width: CGFloat) -> CGFloat {
        markerOffset(for: stepIndex, width: width, markerWidth: 2)
    }

    private static func stepIndex(isEnabled: Bool, precision: Int, maxPrecision: Int) -> Int {
        guard isEnabled else { return offStepIndex }
        return min(max(precision, 1), min(maxPrecision, Int(exponentialDomainMax)))
    }

    private func offIconOffset(width: CGFloat) -> CGFloat {
        markerOffset(for: Self.offStepIndex, width: width, markerWidth: 14)
    }

    private func markerOffset(for stepIndex: Int, width: CGFloat, markerWidth: CGFloat) -> CGFloat {
        let trackLeadingInset: CGFloat = 10
        let trackTrailingInset: CGFloat = 10
        let usableWidth = max(width - trackLeadingInset - trackTrailingInset, 0)
        let centerX = trackLeadingInset + CGFloat(sliderPosition(for: stepIndex)) * usableWidth
        return centerX - markerWidth * 0.5
    }

    // Maps a rounding step index to a 0...1 track position on an exponential
    // curve, so low-precision steps (the common cases) get more travel.
    private static func sliderPosition(for stepIndex: Int) -> Double {
        let boundedStepIndex = min(max(stepIndex, 0), Int(exponentialDomainMax))
        let value = Double(boundedStepIndex)
        let denominator = exp(exponentialK * exponentialDomainMax) - 1
        if denominator == 0 {
            return 0
        }

        let normalized = (exp(exponentialK * value) - 1) / denominator
        return min(max(normalized, 0), 1)
    }
}

// A selectable UI language: its locale code and the name shown in the picker.
private struct LanguageOption {
    let code: String
    let displayName: String
}

// User-selectable theme. `blue` is a dark-based custom palette, so it reports a
// dark color scheme to the system while supplying its own colors.
private enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
    case blue

    func label(using localizationBundle: Bundle?) -> String {
        switch self {
        case .system: return macLocalized("settings.theme.system", bundle: localizationBundle)
        case .light: return macLocalized("settings.theme.light", bundle: localizationBundle)
        case .dark: return macLocalized("settings.theme.dark", bundle: localizationBundle)
        case .blue: return macLocalized("settings.theme.blue", bundle: localizationBundle)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        case .blue:
            return .dark
        }
    }

    func palette(using systemColorScheme: ColorScheme, increasedContrast: Bool = false) -> Palette {
        let basePalette: Palette
        switch self {
        case .light:
            basePalette = .light
        case .dark:
            basePalette = .dark
        case .blue:
            basePalette = .blue
        case .system:
            basePalette = Palette.forScheme(systemColorScheme)
        }

        let isDarkLike = self == .dark || self == .blue || (self == .system && systemColorScheme == .dark)
        let isBlueLike = self == .blue
        return increasedContrast
            ? basePalette.adjustedForIncreasedContrast(isDarkLike: isDarkLike, isBlueLike: isBlueLike)
            : basePalette
    }
}

private extension CalculatorWindowView {
    static func loadStoredSettings(from defaults: UserDefaults = .standard) -> CalculatorScreenSettings {
        CalculatorScreenSettingsPersistence.load(from: defaults)
    }

    func currentWindow() -> NSWindow? {
        windowReference ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
    }

    func makeSettingsSheet() -> SettingsSheet {
        SettingsSheet(
            selectedTheme: Binding(
                get: { currentTheme },
                set: { newValue in
                    updateWindowSettings { $0.themeRawValue = newValue.rawValue }
                    applyTheme(newValue)
                }
            ),
            selectedLanguage: Binding(
                get: { windowSettings.languageCode },
                set: { newValue in
                    updateWindowSettings { $0.languageCode = newValue }
                    applyLanguage(newValue)
                }
            ),
            usesScientificNotation: Binding(
                get: { windowSettings.usesScientificNotation },
                set: { newValue in
                    updateWindowSettings { $0.usesScientificNotation = newValue }
                    viewModel.setScientificNotationEnabled(newValue)
                }
            ),
            selectedNumberFormat: Binding(
                get: { currentNumberFormatStyle },
                set: { newValue in
                    updateWindowSettings { $0.numberFormatStyleRawValue = newValue.rawValue }
                    viewModel.setNumberFormatStyle(newValue)
                }
            ),
            usesAlternativeKeypad: Binding(
                get: { windowSettings.usesAlternativeKeypad },
                set: { newValue in
                    updateWindowSettings { $0.usesAlternativeKeypad = newValue }
                }
            ),
            disablesSwipeDownToRound: Binding(
                get: { windowSettings.disablesSwipeDownToRound },
                set: { newValue in
                    updateWindowSettings { $0.disablesSwipeDownToRound = newValue }
                }
            ),
            disablesButtonSound: Binding(
                get: { windowSettings.disablesButtonSound },
                set: { newValue in
                    updateWindowSettings { $0.disablesButtonSound = newValue }
                }
            ),
            availableLanguages: availableLanguageOptions(),
            onClose: { closeSettingsOverlay() }
        )
    }

    func backingScaleFactor(for window: NSWindow?) -> CGFloat {
        let scale = window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? fallbackBackingScaleFactor
        return max(scale, 1)
    }

    func minimumWindowFrameSize() -> CGSize {
        CGSize(
            width: minimumWindowWidthPoints,
            height: minimumWindowHeightPoints
        )
    }

    func minimumContentSize(window: NSWindow?) -> CGSize {
        let minimumFrameSize = minimumWindowFrameSize()
        guard let window else { return minimumFrameSize }
        return window.contentRect(forFrameRect: NSRect(origin: .zero, size: minimumFrameSize)).size
    }

    func startOperatorIntroAnimation() {
        let revealDuration: Double = 0.46
        let fadeDelay: Double = 0.48
        let fadeDuration: Double = 0.22
        operatorRevealProgress = 0.0
        operatorAnimFadeOpacity = 1.0
        guard !reduceMotionEnabled else {
            operatorRevealProgress = 4.0
            operatorAnimFadeOpacity = 0.0
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.linear(duration: revealDuration)) {
                operatorRevealProgress = 4.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
                withAnimation(.easeIn(duration: fadeDuration)) {
                    operatorAnimFadeOpacity = 0.0
                }
            }
        }
    }

    func updateHistoryVisibility(for width: CGFloat) {
        let shouldUseCompactOverlay = width <= compactHistoryWidthThreshold

        if shouldUseCompactOverlay {
            if showHistory {
                showHistory = false
                setHistoryOverlayVisible(true)
            }
            return
        }

        if showHistoryOverlay {
            showHistory = true
            setHistoryOverlayVisible(false)
        }
    }

    func handleHistoryToggle() {
        logUI("handleHistoryToggle start showHistory=\(showHistory) width=\(currentWidth) keyWindow#\(NSApp.keyWindow?.windowNumber ?? -1)")
        if showHistory {
            showHistory = false
            storedHistoryOpen = showHistory
            logUI("handleHistoryToggle closing history; frame=\(NSApp.keyWindow?.frame.debugDescription ?? "<nil>")")
            return
        }

        showHistory = true
        storedHistoryOpen = showHistory
        logUI("handleHistoryToggle opening history; frame=\(NSApp.keyWindow?.frame.debugDescription ?? "<nil>")")
    }

    func storeWindowSize() {
        guard let window = currentWindow() else { return }
        storedWindowWidth = Double(window.frame.width)
        storedWindowHeight = Double(window.frame.height)
        storedHistoryOpen = showHistory
        storedHistoryOverlayHeight = historyOverlayHeight.map(Double.init) ?? 0
    }

    func applyStoredWindowSizeIfNeeded() {
        guard let window = currentWindow() else { return }
        guard !appliedStoredSize else { return }
        let minimumFrameSize = minimumWindowFrameSize()
        if storedWindowWidth > 0 && storedWindowHeight > 0 {
            var frame = window.frame
            frame.size.width = max(CGFloat(storedWindowWidth), minimumFrameSize.width)
            frame.size.height = max(CGFloat(storedWindowHeight), minimumFrameSize.height)
            window.setFrame(frame, display: true, animate: false)
            currentWidth = frame.size.width
        } else {
            var frame = window.frame
            let targetSize = minimumWindowFrameSize()
            if frame.size.width != targetSize.width || frame.size.height != targetSize.height {
                frame.size.width = targetSize.width
                frame.size.height = targetSize.height
                window.setFrame(frame, display: true, animate: false)
                currentWidth = frame.size.width
            }
        }
        showHistory = storedHistoryOpen
        userToggledHistory = storedHistoryOpen
        historyOverlayHeight = loadStoredHistoryOverlayHeight()
        appliedStoredSize = true
    }

    func loadStoredHistoryOverlayHeight() -> CGFloat? {
        guard storedHistoryOverlayHeight > 0 else { return nil }
        return CGFloat(storedHistoryOverlayHeight)
    }

    func persistHistoryOverlayHeight(_ height: CGFloat?) {
        storedHistoryOverlayHeight = height.map(Double.init) ?? 0
    }

    func updateWindowMinSize() {
        guard let window = currentWindow() else { return }
        let minimumFrameSize = minimumWindowFrameSize()
        let minimumContentSize = minimumContentSize(window: window)

        window.contentMinSize = minimumContentSize

        if window.frame.width < minimumFrameSize.width || window.frame.height < minimumFrameSize.height {
            var frame = window.frame
            frame.size.width = max(frame.size.width, minimumFrameSize.width)
            frame.size.height = max(frame.size.height, minimumFrameSize.height)
            window.setFrame(frame, display: true, animate: false)
            currentWidth = frame.size.width
        }
    }

    func focusCurrentWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func focusNewestWindowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.activate(ignoringOtherApps: true)
            let newest = NSApp.windows.max(by: { $0.windowNumber < $1.windowNumber })
            if let window = newest {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
            }
        }
    }

    func updateWindowSettings(_ update: (inout CalculatorScreenSettings) -> Void) {
        var updated = windowSettings
        update(&updated)
        guard updated != windowSettings else { return }
        windowSettings = updated
        persistWindowSettings(updated)
    }

    func activeKeypadHeightMultiplier() -> Double {
        let liveOrStored = liveKeypadHeightMultiplier ?? windowSettings.keypadHeightMultiplier
        return min(max(liveOrStored, 0.5), 1.0)
    }

    func persistWindowSettings(_ settings: CalculatorScreenSettings) {
        CalculatorScreenSettingsPersistence.persist(settings)
    }

    func applyCurrentWindowSettings() {
        // Re-read the system setting on the same triggers that reapply the rest
        // of the window state, so a missed appearance notification self-corrects
        // the next time the window appears or becomes key.
        systemAppearance.refresh()
        applyTheme(currentTheme)
        applyLanguage(windowSettings.languageCode)
        viewModel.setScientificNotationEnabled(windowSettings.usesScientificNotation)
        viewModel.setNumberFormatStyle(currentNumberFormatStyle)
    }

    func normalizeWindowLanguageIfNeeded() {
        guard !isDefaultLocalizationSelection(windowSettings.languageCode) else {
            return
        }

        let resolvedCode = resolvedLocalizationCode(for: windowSettings.languageCode)
        if windowSettings.languageCode != resolvedCode {
            updateWindowSettings { $0.languageCode = resolvedCode }
        }
    }

    func availableLanguageOptions() -> [LanguageOption] {
        let resolvedDefaultCode = resolvedLocalizationCode()
        let defaultOption = LanguageOption(
            code: defaultLocalizationSelectionCode,
            displayName: String(
                format: macLocalized("settings.language.defaultOption", bundle: currentLocalizationBundle),
                localizationDisplayName(for: resolvedDefaultCode)
            )
        )

        let explicitOptions = supportedLocalizationCodes().map { code in
            LanguageOption(code: code, displayName: localizationDisplayName(for: code).capitalized)
        }.sorted { $0.displayName < $1.displayName }

        return [defaultOption] + explicitOptions
    }

    func applyTheme(_ theme: AppTheme) {
        let appearance: NSAppearance?
        switch theme {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        case .blue:
            appearance = NSAppearance(named: .darkAqua)
        }

        windowReference?.appearance = appearance
    }

    func applyLanguage(_ code: String) {
        languageOverrideBundle = isDefaultLocalizationSelection(code) ? nil : localizationBundle(for: code)
        viewModel.refreshLocalization()
    }
}

// Publishes the system-wide Light/Dark setting so the `system` theme can resolve
// its palette without going through `@Environment(\.colorScheme)`.
//
// The environment value reflects the appearance actually applied to the window,
// which the other themes override directly (`applyTheme`). When that override is
// removed, AppKit does not necessarily re-resolve the hosting view's effective
// appearance before SwiftUI reads it again, so the ambient value can stay on the
// previous theme while native chrome has already moved to the system one.
// Reading the global-domain setting sidesteps that entirely: it is the user's
// system preference, so it cannot report back an override this app applied.
private final class SystemAppearanceMonitor: ObservableObject {
    // Every calculator window resolves the same system setting, so they share one
    // monitor rather than each registering its own notification observer.
    static let shared = SystemAppearanceMonitor()

    @Published private(set) var colorScheme: ColorScheme

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        colorScheme = Self.resolveColorScheme(from: defaults)

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The global domain is updated slightly after this notification is
            // delivered, so re-read on the next runloop pass.
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func refresh() {
        let resolved = Self.resolveColorScheme(from: defaults)
        guard resolved != colorScheme else { return }
        colorScheme = resolved
    }

    private static func resolveColorScheme(from defaults: UserDefaults) -> ColorScheme {
        // Read through the global domain rather than `string(forKey:)` so the
        // value is not served from this process's cached registration domain.
        let rawValue = defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String
        let resolved = SystemAppearance.colorScheme(forInterfaceStyle: rawValue)
        DebugLog.emit("Theme", "system appearance AppleInterfaceStyle=\(rawValue ?? "nil") resolved=\(resolved)")
        return resolved
    }
}

// Tiny representable view used purely to obtain the hosting NSWindow, which
// SwiftUI doesn't otherwise expose, for sizing and appearance updates.
private struct CalculatorWindowResolver: NSViewRepresentable {
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
