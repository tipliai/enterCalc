import SwiftUI
#if canImport(UIKit)
import UIKit
#if canImport(CoreMotion)
import CoreMotion
#endif

private enum IOSActionHaptics {
    static let keyPressImpact = UIImpactFeedbackGenerator(style: .light)
    static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    static let successNotification = UINotificationFeedbackGenerator()

    static func performKeyPress() {
        keyPressImpact.prepare()
        keyPressImpact.impactOccurred(intensity: 0.95)
    }

    static func perform(emphasized: Bool) {
        if emphasized {
            mediumImpact.prepare()
            mediumImpact.impactOccurred(intensity: 1)
            successNotification.prepare()
            successNotification.notificationOccurred(.success)
        } else {
            lightImpact.prepare()
            lightImpact.impactOccurred(intensity: 0.8)
        }
    }
}
#endif
import EnterCalcCore

@main
struct EnterCalcIOSApp: App {
    init() {
    EnterCalcFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            EnterCalcIOSView()
                .iPadWindowMinimumSize()
        }
        .defaultSize(
            width: IOSLayoutMetrics.defaultPadWindowSize.width,
            height: IOSLayoutMetrics.defaultPadWindowSize.height
        )
        .windowResizability(.contentSize)
    }
}

struct EnterCalcIOSView: View {
    @StateObject private var screenStore = CalculatorScreenStore(
        homeSettings: CalculatorScreenSettings(
            themeRawValue: AppTheme.system.rawValue,
            languageCode: defaultLocalizationSelectionCode,
            usesScientificNotation: true,
            numberFormatStyleRawValue: NumberFormatStyle.detected().rawValue,
            usesClassicPercentBehavior: false,
            usesEnterKeySymbol: true,
            keypadHeightMultiplier: 1.0
        )
    )
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeOverlay: IOSOverlayPane? = nil
    @State private var showSettingsSheet: Bool = false
    @State private var counterRotatesForUpsideDownPortrait: Bool = false
    @State private var flashCopy: Bool = false
    @State private var copyStreakActive: Bool = false
    @State private var copyStreakTravel: CGFloat = 1.35
    @State private var displayShimmerParallaxOffset: CGSize = .zero
    @State private var displayShimmerAngleDegrees: Double = -28
    @State private var displayShimmerIntroActive: Bool = false
    @State private var displayFallbackParallaxAnimating: Bool = false
#if canImport(CoreMotion)
    @State private var displayMotionManager = CMMotionManager()
#endif
    @State private var operatorRevealProgress: Double = 0.0
    @State private var operatorAnimFadeOpacity: Double = 1.0
    @State private var previousScreenCount: Int = 1
    @State private var keypadResizeGestureStartMultiplier: Double = 1.0
    @State private var isResizingKeypadHeight: Bool = false
    @AppStorage("settings.theme") private var preferredThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("settings.language") private var preferredLanguage: String = defaultLocalizationSelectionCode
    @AppStorage("settings.numberFormat.scientific") private var preferredScientificNotation: Bool = true
    @AppStorage("settings.numberFormat.style") private var preferredNumberFormatRaw: String = NumberFormatStyle.detected().rawValue
    @AppStorage("settings.percent.classic") private var preferredClassicPercentBehavior: Bool = false
    @AppStorage("settings.equals.enterKeySymbol") private var preferredUsesEnterKeySymbol: Bool = true
    @AppStorage("settings.keypadHeightMultiplier") private var preferredKeypadHeightMultiplier: Double = 1.0

    private var activeScreen: CalculatorScreenSession {
        screenStore.activeScreen
    }

    private var viewModel: CalculatorViewModel {
        activeScreen.viewModel
    }

    private var activeTheme: AppTheme {
        AppTheme(rawValue: activeScreen.settings.themeRawValue) ?? .system
    }

    private var storedHomeScreenSettings: CalculatorScreenSettings {
        let keypadHeightMultiplier = min(max(preferredKeypadHeightMultiplier, 0.5), 1.0)
        return CalculatorScreenSettings(
            themeRawValue: preferredThemeRaw,
            languageCode: preferredLanguage,
            usesScientificNotation: preferredScientificNotation,
            numberFormatStyleRawValue: preferredNumberFormatRaw,
            usesClassicPercentBehavior: preferredClassicPercentBehavior,
            usesEnterKeySymbol: preferredUsesEnterKeySymbol,
            keypadHeightMultiplier: keypadHeightMultiplier
        )
    }

    private var equalsButtonTitle: String {
        activeScreen.settings.usesEnterKeySymbol ? "⏎" : "="
    }

    private var palette: Palette {
        activeTheme.palette(using: colorScheme)
    }

    private var activeSettingsTitleKey: String {
        activeScreen.isHomeScreen ? "settings.title" : "settings.screen.title"
    }

    private var activeAppearanceLabelKey: String {
        activeScreen.isHomeScreen ? "settings.appearance.label" : "settings.appearance.screenLabel"
    }

    private var rows: [[IOSCalcButton]] {
        [
            [
                .function("C", action: { $0.clearAll() }),
                .function("( )", action: { $0.inputParentheses() }),
                .function("%", action: { $0.applyPercent() }),
                .function("⌫", action: { $0.backspace() })
            ],
            [
                .function("1/x", action: { $0.reciprocal() }),
                .function("x²", action: { $0.square() }),
                .function("²√x", action: { $0.squareRoot() }),
                .operation("÷", action: { $0.setOperator(.divide) })
            ],
            [
                .digit("7"), .digit("8"), .digit("9"), .operation("×", action: { $0.setOperator(.multiply) })
            ],
            [
                .digit("4"), .digit("5"), .digit("6"), .operation("−", action: { $0.setOperator(.subtract) })
            ],
            [
                .digit("1"), .digit("2"), .digit("3"), .operation("+", action: { $0.setOperator(.add) })
            ],
            [
                .function("+/−", action: { $0.toggleSign() }),
                .digit("0"),
                .decimal(),
                .equals(title: equalsButtonTitle)
            ]
        ]
    }

    private var flattenedButtons: [IOSCalcButton] {
        rows.flatMap { $0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = IOSLayoutMetrics(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets,
                horizontalSizeClass: horizontalSizeClass,
                deviceFamily: currentDeviceFamily()
            )

            ZStack(alignment: .top) {
                palette.surface
                    .ignoresSafeArea()

                layoutBody(metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .rotationEffect(.degrees(counterRotatesForUpsideDownPortrait ? 180 : 0))

                if showsOverlayScrim(metrics: metrics) {
                    overlayScrim(metrics: metrics)
                }

                overlayPanels(metrics: metrics)
                    .rotationEffect(.degrees(counterRotatesForUpsideDownPortrait ? 180 : 0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .preferredColorScheme(activeTheme.preferredColorScheme)
            .onAppear {
                syncSystemSettingsMetadata()
                normalizePreferredLanguageIfNeeded()
                syncHomeScreenFromStoredSettings()
                applyActiveScreenConfiguration()
                startDeviceOrientationObservation()
                syncPhoneUpsideDownPresentation()
                startDisplayShimmerParallaxMotion()
                startOperatorIntroAnimation()
            }
            .onDisappear {
                stopDisplayShimmerParallaxMotion()
                stopDeviceOrientationObservation()
            }
            .onValueChange(of: scenePhase) { newPhase in
                guard newPhase == .active else {
                    stopDisplayShimmerParallaxMotion()
                    return
                }

                syncSystemSettingsMetadata()
                if isDefaultLocalizationSelection(activeScreen.settings.languageCode) {
                    applyActiveScreenConfiguration()
                }
                startDisplayShimmerParallaxMotion()
                startOperatorIntroAnimation()
            }
            .onValueChange(of: screenStore.screenCount) { newCount in
                defer { previousScreenCount = newCount }
                guard newCount > previousScreenCount else { return }
                startOperatorIntroAnimation()
            }
            .onValueChange(of: preferredThemeRaw) { _ in
                syncHomeScreenFromStoredSettings()
            }
            .onValueChange(of: preferredLanguage) { newValue in
                syncHomeScreenFromStoredSettings()
                if activeScreen.isHomeScreen {
                    applyLanguage(newValue, refreshing: screenStore.homeScreen.viewModel)
                }
            }
            .onValueChange(of: preferredScientificNotation) { _ in
                syncHomeScreenFromStoredSettings()
            }
            .onValueChange(of: preferredNumberFormatRaw) { _ in
                syncHomeScreenFromStoredSettings()
            }
            .onValueChange(of: preferredClassicPercentBehavior) { _ in
                syncHomeScreenFromStoredSettings()
            }
            .onValueChange(of: showSettingsSheet) { isPresented in
                if isPresented {
                    stopDisplayShimmerParallaxMotion()
                } else {
                    startDisplayShimmerParallaxMotion()
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                IOSSettingsSheet(
                    titleKey: activeSettingsTitleKey,
                    appearanceLabelKey: activeAppearanceLabelKey,
                    selectedTheme: activeThemeBinding,
                    selectedLanguage: activeLanguageBinding,
                    usesScientificNotation: activeScientificNotationBinding,
                    selectedNumberFormat: activeNumberFormatBinding,
                    usesClassicPercentBehavior: activeClassicPercentBinding,
                    usesEnterKeySymbol: activeEnterKeySymbolBinding,
                    availableLanguages: availableLanguageOptions(),
                    counterRotatesForUpsideDownPortrait: counterRotatesForUpsideDownPortrait
                )
            }
            .onIOSDeviceOrientationChange {
                isResizingKeypadHeight = false
                syncPhoneUpsideDownPresentation()
                updateDisplayShimmerParallax()
            }
        }
    }
}

private extension EnterCalcIOSView {
    var activeThemeBinding: Binding<String> {
        Binding(
            get: { activeScreen.settings.themeRawValue },
            set: { newValue in
                updateActiveScreenSettings { $0.themeRawValue = newValue }
            }
        )
    }

    var activeLanguageBinding: Binding<String> {
        Binding(
            get: { activeScreen.settings.languageCode },
            set: { newValue in
                updateActiveScreenSettings { $0.languageCode = newValue }
                applyLanguage(newValue, refreshing: activeScreen.viewModel)
            }
        )
    }

    var activeScientificNotationBinding: Binding<Bool> {
        Binding(
            get: { activeScreen.settings.usesScientificNotation },
            set: { newValue in
                updateActiveScreenSettings { $0.usesScientificNotation = newValue }
            }
        )
    }

    var activeNumberFormatBinding: Binding<String> {
        Binding(
            get: { activeScreen.settings.numberFormatStyleRawValue },
            set: { newValue in
                updateActiveScreenSettings { $0.numberFormatStyleRawValue = newValue }
            }
        )
    }

    var activeClassicPercentBinding: Binding<Bool> {
        Binding(
            get: { activeScreen.settings.usesClassicPercentBehavior },
            set: { newValue in
                updateActiveScreenSettings { $0.usesClassicPercentBehavior = newValue }
            }
        )
    }

    var activeEnterKeySymbolBinding: Binding<Bool> {
        Binding(
            get: { activeScreen.settings.usesEnterKeySymbol },
            set: { newValue in
                updateActiveScreenSettings { $0.usesEnterKeySymbol = newValue }
            }
        )
    }

    func settingsTitleKey(for screen: CalculatorScreenSession) -> String {
        screen.isHomeScreen ? "settings.title" : "settings.screen.title"
    }

    func appearanceLabelKey(for screen: CalculatorScreenSession) -> String {
        screen.isHomeScreen ? "settings.appearance.label" : "settings.appearance.screenLabel"
    }

    func pageActionLabelKey(for screen: CalculatorScreenSession) -> String {
        screen.isHomeScreen ? "screen.new" : "screen.close"
    }

    func pageActionImageName(for screen: CalculatorScreenSession) -> String {
        screen.isHomeScreen ? "plus.square.on.square" : "xmark.square"
    }

    func syncHomeScreenFromStoredSettings() {
        screenStore.syncHomeScreenSettings(storedHomeScreenSettings)
    }

    func startOperatorIntroAnimation() {
        let revealDuration: Double = 0.46
        let fadeDelay: Double = 0.48
        let fadeDuration: Double = 0.22
        operatorRevealProgress = 0.0
        operatorAnimFadeOpacity = 1.0
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
        startShimmerIntroAnimation()
    }

    func startShimmerIntroAnimation() {
        displayShimmerIntroActive = true
        displayShimmerAngleDegrees = 0
        withAnimation(.easeOut(duration: 1.0)) {
            displayShimmerAngleDegrees = -28
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            displayShimmerIntroActive = false
        }
    }

    func updateActiveScreenSettings(_ update: (inout CalculatorScreenSettings) -> Void) {
        var updated = activeScreen.settings
        update(&updated)

        if activeScreen.isHomeScreen {
            preferredThemeRaw = updated.themeRawValue
            preferredLanguage = updated.languageCode
            preferredScientificNotation = updated.usesScientificNotation
            preferredNumberFormatRaw = updated.numberFormatStyleRawValue
            preferredClassicPercentBehavior = updated.usesClassicPercentBehavior
            preferredUsesEnterKeySymbol = updated.usesEnterKeySymbol
            preferredKeypadHeightMultiplier = updated.keypadHeightMultiplier
            screenStore.syncHomeScreenSettings(updated)
        } else {
            activeScreen.replaceSettings(updated)
        }
    }

    func applyActiveScreenConfiguration() {
        let screen = activeScreen
        screen.applyCalculatorSettings()
        applyLanguage(screen.settings.languageCode, refreshing: screen.viewModel)
    }

    func navigateToScreen(at index: Int) {
        guard screenStore.screens.indices.contains(index) else { return }
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.2)) {
            activeOverlay = nil
            _ = screenStore.activateScreen(at: index)
        }
        applyActiveScreenConfiguration()
    }

    func createScreenAfterActive() {
        guard screenStore.canCreateScreen else { return }
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.2)) {
            activeOverlay = nil
            _ = screenStore.insertScreenAfterActive(homeSettings: storedHomeScreenSettings)
        }
        applyActiveScreenConfiguration()
    }

    func closeActiveScreen() {
        guard screenStore.canCloseActiveScreen else { return }
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.2)) {
            activeOverlay = nil
            _ = screenStore.closeActiveScreen()
        }
        applyActiveScreenConfiguration()
    }

    func handlePageAction() {
        if activeScreen.isHomeScreen {
            createScreenAfterActive()
        } else {
            closeActiveScreen()
        }
    }

    @ViewBuilder
    func overlayPanels(metrics: IOSLayoutMetrics) -> some View {
        ZStack(alignment: .top) {
            if metrics.usesOverlayHistory, activeOverlay == .history {
                overlayPanel(metrics: metrics) {
                    IOSHistoryPanel(
                        entries: viewModel.history,
                        palette: palette,
                        metrics: metrics,
                        onSelect: { entry in
                            viewModel.reuse(entry)
                            activeOverlay = nil
                        },
                        onClear: { viewModel.clearHistory() },
                        onDismiss: { activeOverlay = nil },
                        onCopyEntry: { entry in copyHistoryEntryResultToPasteboard(entry, from: viewModel) },
                        onCopyOperationEntry: { entry in copyHistoryEntryOperationToPasteboard(entry, from: viewModel) }
                    )
                }
            }
        }
    }

    func showsOverlayScrim(metrics: IOSLayoutMetrics) -> Bool {
        metrics.usesOverlayHistory && activeOverlay == .history
    }

    func startDeviceOrientationObservation() {
#if canImport(UIKit)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
#endif
    }

    func stopDeviceOrientationObservation() {
#if canImport(UIKit)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
#endif
    }

    func syncPhoneUpsideDownPresentation() {
#if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            counterRotatesForUpsideDownPortrait = false
            return
        }

        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            counterRotatesForUpsideDownPortrait = true

            let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let activeWindowScene = windowScenes.first(where: { $0.activationState == .foregroundActive }) ?? windowScenes.first

            activeWindowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        case .portrait, .landscapeLeft, .landscapeRight:
            counterRotatesForUpsideDownPortrait = false
        default:
            counterRotatesForUpsideDownPortrait = false
        }
#else
        counterRotatesForUpsideDownPortrait = false
#endif
    }

    func updateDisplayShimmerParallax() {
#if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            displayShimmerParallaxOffset = .zero
            return
        }
        if displayMotionManager.isDeviceMotionActive {
            return
        }

        var targetOffset: CGSize = displayShimmerParallaxOffset
        var targetAngle: Double = displayShimmerAngleDegrees

        switch UIDevice.current.orientation {
        case .portrait:
            targetOffset = .zero
            targetAngle = -28
        case .portraitUpsideDown:
            targetOffset = .zero
            targetAngle = 152
        case .landscapeLeft:
            targetOffset = CGSize(width: -1.0, height: 0)
            targetAngle = -62
        case .landscapeRight:
            targetOffset = CGSize(width: 1.0, height: 0)
            targetAngle = 22
        default:
            break
        }

        withAnimation(.easeOut(duration: 0.65)) {
            displayShimmerParallaxOffset = targetOffset
            displayShimmerAngleDegrees = targetAngle
        }
#else
        displayShimmerParallaxOffset = .zero
#endif
    }

    func displayShimmerHorizontalGravityComponent(gravityX: Double, gravityY: Double) -> Double {
#if canImport(UIKit)
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return -gravityY
        case .landscapeRight:
            return gravityY
        case .portraitUpsideDown:
            return -gravityX
        default:
            return gravityX
        }
#else
        return gravityX
#endif
    }

    func displayShimmerBaseAngle() -> Double {
#if canImport(UIKit)
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            return 152
        case .landscapeLeft:
            return -62
        case .landscapeRight:
            return 22
        default:
            return -28
        }
#else
        return -28
#endif
    }

    func startDisplayShimmerFallbackAnimation() {
        guard !displayFallbackParallaxAnimating else { return }
        displayFallbackParallaxAnimating = true
        displayShimmerAngleDegrees = displayShimmerBaseAngle()
        displayShimmerParallaxOffset = CGSize(width: -1.4, height: 0)
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            displayShimmerParallaxOffset = CGSize(width: 1.4, height: 0)
        }
    }

    func stopDisplayShimmerFallbackAnimation() {
        guard displayFallbackParallaxAnimating else { return }
        displayFallbackParallaxAnimating = false
        withAnimation(.easeOut(duration: 0.12)) {
            displayShimmerParallaxOffset = .zero
        }
    }

    func startDisplayShimmerParallaxMotion() {
#if canImport(UIKit) && canImport(CoreMotion)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            displayShimmerParallaxOffset = .zero
            stopDisplayShimmerFallbackAnimation()
            return
        }
        guard !showSettingsSheet else {
            stopDisplayShimmerFallbackAnimation()
            return
        }
        if displayMotionManager.isDeviceMotionActive {
            return
        }
        guard displayMotionManager.isDeviceMotionAvailable else {
            startDisplayShimmerFallbackAnimation()
            return
        }

        stopDisplayShimmerFallbackAnimation()

        displayMotionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        let motionQueue = OperationQueue()
        motionQueue.name = "enterCalc.deviceMotion"
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInteractive

        displayMotionManager.startDeviceMotionUpdates(to: motionQueue) { motion, error in
            if let error {
                _ = error
                return
            }
            guard let motion else { return }

            let maxOffset: CGFloat = 5.2
            let horizontalGravity = displayShimmerHorizontalGravityComponent(
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y
            )
            let rawX = max(-maxOffset, min(maxOffset, CGFloat(horizontalGravity) * maxOffset))
            let targetOffset = CGSize(width: rawX, height: 0)
            let targetAngle = displayShimmerBaseAngle() + horizontalGravity * 30

            DispatchQueue.main.async {
                guard !showSettingsSheet else { return }

                // Heavier smoothing plus capped per-update steps prevents abrupt pops on fast motion.
                let smoothing: CGFloat = 0.92
                let maxOffsetStep: CGFloat = 0.28
                let nextOffsetX = displayShimmerParallaxOffset.width * smoothing + targetOffset.width * (1 - smoothing)
                let nextOffsetY = displayShimmerParallaxOffset.height * smoothing + targetOffset.height * (1 - smoothing)
                let deltaX = max(-maxOffsetStep, min(maxOffsetStep, nextOffsetX - displayShimmerParallaxOffset.width))
                let deltaY = max(-maxOffsetStep, min(maxOffsetStep, nextOffsetY - displayShimmerParallaxOffset.height))
                displayShimmerParallaxOffset = CGSize(
                    width: displayShimmerParallaxOffset.width + deltaX,
                    height: displayShimmerParallaxOffset.height + deltaY
                )

                if !displayShimmerIntroActive {
                    let angleSmoothing: Double = 0.94
                    let maxAngleStep: Double = 3.2
                    let nextAngle = displayShimmerAngleDegrees * angleSmoothing + targetAngle * (1 - angleSmoothing)
                    let angleDelta = max(-maxAngleStep, min(maxAngleStep, nextAngle - displayShimmerAngleDegrees))
                    displayShimmerAngleDegrees += angleDelta
                }
            }
        }
#else
        startDisplayShimmerFallbackAnimation()
#endif
    }

    func stopDisplayShimmerParallaxMotion() {
#if canImport(CoreMotion)
        if displayMotionManager.isDeviceMotionActive {
            displayMotionManager.stopDeviceMotionUpdates()
        }
#endif
        stopDisplayShimmerFallbackAnimation()
    }

    @ViewBuilder
    func layoutBody(metrics: IOSLayoutMetrics) -> some View {
        let usesLandscapeNavigationRail = metrics.mode != .phonePortrait
        let landscapeRailWidth = usesLandscapeNavigationRail ? metrics.headerButtonSize + 4 : 0
        let pageSpacing = metrics.mode == .phoneLandscape && metrics.usesInlineLandscapeHistory
            ? metrics.historyPanelWidth + metrics.outerPadding * 2
            : (usesLandscapeNavigationRail ? max(metrics.sectionSpacing * 4, metrics.outerPadding * 1.5) : 0)

        let pager = CalculatorScreenPager(
            pagingAxis: .horizontal,
            pageSpacing: pageSpacing,
            pageCount: screenStore.screenCount,
            activeIndex: screenStore.activeIndex,
            canMoveBackward: screenStore.activeIndex > 0,
            canMoveForward: screenStore.activeIndex < screenStore.screenCount - 1,
            canCreateTrailingPage: screenStore.canCreateScreen && screenStore.activeIndex == screenStore.screenCount - 1,
            onMoveBackward: { navigateToScreen(at: screenStore.activeIndex - 1) },
            onMoveForward: { navigateToScreen(at: screenStore.activeIndex + 1) },
            onRequestCreateTrailingPage: { createScreenAfterActive() },
            canCloseUpward: metrics.mode == .phonePortrait && !activeScreen.isHomeScreen && activeOverlay == nil,
            upwardCloseThreshold: max(90, metrics.displayHeight * 0.7),
            onCloseUpward: { closeActiveScreen() },
            activationThresholdRatio: 0.4,
            trailingPlaceholder: AnyView(trailingNewScreenPlaceholder(metrics: metrics)),
            transitionOverlayColor: palette.surface
        ) { index in
            screenBody(metrics: metrics, screen: screenStore.screens[index])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        if usesLandscapeNavigationRail {
            HStack(spacing: metrics.sectionSpacing) {
                landscapeNavigationRail(
                    metrics: metrics,
                    screen: activeScreen,
                    showsPaginationIndicator: screenStore.screenCount > 1
                )
                .frame(width: landscapeRailWidth)
                .frame(maxHeight: .infinity)

                pager
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            pager
        }
    }

    @ViewBuilder
    func paginationIndicator(metrics: IOSLayoutMetrics) -> some View {
        let usesLandscapeNavigationRail = metrics.mode != .phonePortrait
        let activePaginationColor = activeTheme == .blue
            ? Color.white
            : Color(red: 0, green: 0.3529, blue: 1.0)
        let inactivePaginationColor = colorScheme == .dark
            ? palette.textSecondary.opacity(0.28)
            : palette.textPrimary.opacity(0.18)

        CalculatorScreenPageIndicator(
            axis: usesLandscapeNavigationRail ? .vertical : .horizontal,
            pageCount: screenStore.screenCount,
            activeIndex: screenStore.activeIndex,
            activeColor: activePaginationColor,
            inactiveColor: inactivePaginationColor,
            dotSize: metrics.pageIndicatorDotSize,
            spacing: metrics.pageIndicatorSpacing
        )
    }

    @ViewBuilder
    func settingsButton(
        metrics: IOSLayoutMetrics,
        screen: CalculatorScreenSession,
        buttonSize: CGFloat? = nil,
        iconSize: CGFloat? = nil
    ) -> some View {
        IOSContextMenuContainer(
            sections: clipboardContextMenuSections(
                for: screen.viewModel,
                settingsTitleKey: settingsTitleKey(for: screen),
                includeSettingsAction: true
            )
        ) {
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(EnterCalcFont.appFont(size: iconSize ?? metrics.headerIconFontSize))
                    .frame(width: buttonSize ?? metrics.headerButtonSize, height: buttonSize ?? metrics.headerButtonSize)
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            .buttonStyle(IOSPressedButtonStyle(cornerRadius: metrics.headerCornerRadius, overlayColor: palette.headerHover))
            .accessibilityLabel(Text(localized(settingsTitleKey(for: screen))))
        }
        .frame(width: buttonSize ?? metrics.headerButtonSize, height: buttonSize ?? metrics.headerButtonSize)
    }

    @ViewBuilder
    func pageActionButton(
        metrics: IOSLayoutMetrics,
        screen: CalculatorScreenSession,
        buttonSize: CGFloat? = nil,
        iconSize: CGFloat? = nil
    ) -> some View {
        Button {
            handlePageAction()
        } label: {
            Image(systemName: pageActionImageName(for: screen))
                .font(EnterCalcFont.appFont(size: iconSize ?? metrics.headerIconFontSize))
                .frame(width: buttonSize ?? metrics.headerButtonSize, height: buttonSize ?? metrics.headerButtonSize)
                .foregroundStyle(palette.textPrimary)
        }
        .buttonStyle(.plain)
        .buttonStyle(IOSPressedButtonStyle(cornerRadius: metrics.headerCornerRadius, overlayColor: palette.headerHover))
        .disabled(screen.isHomeScreen && !screenStore.canCreateScreen)
        .opacity(screen.isHomeScreen && !screenStore.canCreateScreen ? 0.5 : 1)
        .accessibilityLabel(Text(localized(pageActionLabelKey(for: screen))))
    }

    @ViewBuilder
    func landscapeNavigationRail(
        metrics: IOSLayoutMetrics,
        screen: CalculatorScreenSession,
        showsPaginationIndicator: Bool
    ) -> some View {
        VStack(spacing: 0) {
            pageActionButton(
                metrics: metrics,
                screen: screen,
                buttonSize: metrics.headerButtonSize + 4,
                iconSize: metrics.headerIconFontSize + 2
            )
            .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: metrics.sectionSpacing)

            if showsPaginationIndicator {
                paginationIndicator(metrics: metrics)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: metrics.sectionSpacing)

            settingsButton(
                metrics: metrics,
                screen: screen,
                buttonSize: metrics.headerButtonSize + 4,
                iconSize: metrics.headerIconFontSize + 2
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func pageContentWithPagination<Content: View>(
        metrics: IOSLayoutMetrics,
        showsPaginationIndicator: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            let usesLandscapeNavigationRail = metrics.mode != .phonePortrait
            let paginationSpacing = showsPaginationIndicator ? metrics.sectionSpacing : 0
            let bottomFooterHeight = showsPaginationIndicator
                ? metrics.pageIndicatorHeight
                : (metrics.mode == .phonePortrait ? metrics.portraitBottomReserveWithoutPagination : 0)
            let paginationReserve = showsPaginationIndicator ? metrics.pageIndicatorHeight + paginationSpacing : 0

            if usesLandscapeNavigationRail {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: paginationSpacing) {
                    content()
                        .frame(maxWidth: .infinity, alignment: .top)
                        .frame(height: max(0, geometry.size.height - paginationReserve - bottomFooterHeight), alignment: .top)

                    if showsPaginationIndicator {
                        paginationIndicator(metrics: metrics)
                    } else if bottomFooterHeight > 0 {
                        Color.clear
                            .frame(height: bottomFooterHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    func screenBody(metrics: IOSLayoutMetrics, screen: CalculatorScreenSession) -> some View {
        let showsPaginationIndicator = screenStore.screenCount > 1
        let paginationBottomInset = metrics.mode == .phonePortrait
            ? (showsPaginationIndicator
                ? metrics.pageIndicatorHeight + metrics.sectionSpacing
                : 0)
            : 0

        switch metrics.mode {
        case .phoneLandscape:
            if metrics.usesInlineLandscapeHistory {
                pageContentWithPagination(metrics: metrics, showsPaginationIndicator: showsPaginationIndicator) {
                    HStack(spacing: metrics.outerPadding) {
                        landscapeHistoryPane(metrics: metrics, screen: screen)
                            .frame(width: metrics.historyPanelWidth)
                            .frame(maxHeight: .infinity)

                        calculatorSurface(metrics: metrics, screen: screen, paginationBottomInset: paginationBottomInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, metrics.outerPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            } else {
                pageContentWithPagination(metrics: metrics, showsPaginationIndicator: showsPaginationIndicator) {
                    calculatorSurface(metrics: metrics, screen: screen, paginationBottomInset: paginationBottomInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, metrics.outerPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            }
        case .phonePortrait:
            pageContentWithPagination(metrics: metrics, showsPaginationIndicator: showsPaginationIndicator) {
                calculatorSurface(metrics: metrics, screen: screen, paginationBottomInset: paginationBottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, metrics.outerPadding)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
        case .padWide:
            pageContentWithPagination(metrics: metrics, showsPaginationIndicator: showsPaginationIndicator) {
                HStack(spacing: 0) {
                    Spacer(minLength: metrics.outerPadding)
                    calculatorSurface(metrics: metrics, screen: screen, paginationBottomInset: paginationBottomInset)
                        .frame(maxWidth: metrics.calculatorWidth, maxHeight: .infinity, alignment: .top)
                    Spacer(minLength: metrics.outerPadding)
                }
            }
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
            .padding(.horizontal, metrics.outerPadding)
        }
    }

    func calculatorSurface(
        metrics: IOSLayoutMetrics,
        screen: CalculatorScreenSession,
        paginationBottomInset: CGFloat = 0
    ) -> some View {
        GeometryReader { geometry in
            let scale = metrics.surfaceScaleFactor(for: geometry.size.height)
            let isLandscapeMode = metrics.mode == .phoneLandscape || metrics.mode == .padWide
            let allowsKeypadResize = !isLandscapeMode
            let showsInlineLandscapeHeader = !metrics.usesInlineLandscapeHistory
            let keypadHeightMultiplier = allowsKeypadResize ? normalizedKeypadHeightMultiplier(for: screen) : 1.0
            let baseKeypadHeight = metrics.keypadHeight
            let baseButtonHeight = metrics.buttonHeight * keypadHeightMultiplier
            let baseActualKeypadHeight = baseButtonHeight * 6 + metrics.gridSpacing * 5
            let resultAreaHeight = metrics.displayHeight + metrics.memoryHeight + (baseKeypadHeight - baseActualKeypadHeight)
            let separatorHeight: CGFloat = 10
            let headerHeightContribution = showsInlineLandscapeHeader ? metrics.headerHeight : 0
            let outerSpacingTotal = CGFloat(showsInlineLandscapeHeader ? 2 : 1) * metrics.sectionSpacing
            let verticalPaddingTotal = metrics.contentTopPadding + metrics.contentBottomPadding
            let fixedHeight = verticalPaddingTotal
                + headerHeightContribution
                + resultAreaHeight
                + separatorHeight
                + outerSpacingTotal
            let availableKeypadHeight = max(0, geometry.size.height - fixedHeight - paginationBottomInset)
            let fittedButtonHeight = max(0, (availableKeypadHeight - metrics.gridSpacing * 5) / 6)
            let actualButtonHeight = isLandscapeMode
                ? max(baseButtonHeight, fittedButtonHeight)
                : min(baseButtonHeight, fittedButtonHeight)
            let actualKeypadHeight = actualButtonHeight * 6 + metrics.gridSpacing * 5

            VStack(spacing: metrics.sectionSpacing) {
                if showsInlineLandscapeHeader {
                    header(metrics: metrics, screen: screen)
                }
                display(
                    metrics: metrics,
                    screen: screen,
                    resultAreaHeight: resultAreaHeight,
                    showsMemoryLabel: !isLandscapeMode
                )
                    .frame(maxWidth: .infinity, minHeight: resultAreaHeight, maxHeight: resultAreaHeight, alignment: .top)

                VStack(spacing: 0) {
                    if allowsKeypadResize {
                        keypadResizeHandle(metrics: metrics, screen: screen, height: separatorHeight)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: separatorHeight)
                    }

                    keypad(metrics: metrics, screen: screen, buttonHeight: actualButtonHeight)
                        .frame(maxWidth: .infinity, minHeight: actualKeypadHeight, maxHeight: actualKeypadHeight, alignment: .bottom)
                }
                .overlay {
                    if allowsKeypadResize && isResizingKeypadHeight {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                cancelKeypadResize(screen: screen)
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .padding(.top, metrics.contentTopPadding)
            .padding(.bottom, metrics.contentBottomPadding)
            .padding(.horizontal, metrics.innerHorizontalPadding)
            .background(palette.surface)
            .scaleEffect(scale, anchor: .top)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    func landscapeHistoryPane(metrics: IOSLayoutMetrics, screen: CalculatorScreenSession) -> some View {
        IOSHistoryPanel(
            entries: screen.viewModel.history,
            palette: palette,
            metrics: metrics,
            onSelect: { entry in screen.viewModel.reuse(entry) },
            onClear: { screen.viewModel.clearHistory() },
            onDismiss: { toggleOverlay(.history) },
            onCopyEntry: { entry in copyHistoryEntryResultToPasteboard(entry, from: screen.viewModel) },
            onCopyOperationEntry: { entry in copyHistoryEntryOperationToPasteboard(entry, from: screen.viewModel) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    func trailingNewScreenPlaceholder(metrics: IOSLayoutMetrics) -> some View {
        GeometryReader { geometry in
            ZStack {
                palette.surface

                Image(systemName: "plus.square.on.square")
                    .font(EnterCalcFont.appFont(size: metrics.headerIconFontSize * 3.2))
                    .foregroundStyle(palette.textSecondary.opacity(colorScheme == .dark ? 0.12 : 0.10))
                    .offset(x: -geometry.size.width * 0.25)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func header(metrics: IOSLayoutMetrics, screen: CalculatorScreenSession) -> some View {
        let showsLandscapeRailControls = metrics.mode != .phonePortrait

        return HStack(spacing: metrics.headerSpacing) {
            if !showsLandscapeRailControls {
                settingsButton(metrics: metrics, screen: screen)
            }

            Spacer(minLength: 0)

            if metrics.showsHistoryButton {
                Button {
                    toggleOverlay(.history)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(EnterCalcFont.appFont(size: metrics.headerIconFontSize))
                        .frame(width: metrics.headerButtonSize, height: metrics.headerButtonSize)
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .buttonStyle(IOSPressedButtonStyle(cornerRadius: metrics.headerCornerRadius, overlayColor: palette.headerHover))
                .accessibilityLabel(Text(localized("history.toggle")))
            }

            if !showsLandscapeRailControls {
                pageActionButton(metrics: metrics, screen: screen)
            }
        }
        .frame(height: metrics.headerHeight)
        .background(palette.surface)
    }

    func display(
        metrics: IOSLayoutMetrics,
        screen: CalculatorScreenSession,
        resultAreaHeight expandedResultAreaHeight: CGFloat,
        showsMemoryLabel: Bool
    ) -> some View {
        let isBlueTheme = activeTheme == .blue
        let parallaxX = max(-8, min(8, displayShimmerParallaxOffset.width * 1.8))
        let parallaxY = max(-8, min(8, displayShimmerParallaxOffset.height * 1.8))
        let displayShape = RoundedRectangle(cornerRadius: metrics.surfaceCornerRadius, style: .continuous)
        let shimmerHardMask = RoundedRectangle(cornerRadius: max(metrics.surfaceCornerRadius - 2.0, 0), style: .continuous)
        let displayHeight = metrics.displayHeight
        let resultsTextHeight = showsMemoryLabel ? displayHeight : expandedResultAreaHeight
        let displayBaseColor = isBlueTheme
            ? Color(red: 0.408, green: 0.424, blue: 0.982)
            : palette.buttonOperation
        let shimmerEdgeColor = isBlueTheme
            ? Color(red: 0.900, green: 0.790, blue: 1.0).opacity(0.28)
            : (colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.07))
        let shimmerTailColor = isBlueTheme
            ? Color(red: 0.610, green: 0.545, blue: 1.0).opacity(0.18)
            : (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.035))
        let shimmerBandColor = isBlueTheme
            ? Color(red: 0.760, green: 0.710, blue: 1.0).opacity(0.21)
            : (colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.06))
        let leadingShimmerStops: [Gradient.Stop] = colorScheme == .dark
            ? [
                .init(color: shimmerEdgeColor, location: 0.0),
                .init(color: shimmerEdgeColor, location: 0.06),
                .init(color: .clear, location: 0.16),
                .init(color: shimmerTailColor, location: 1.0)
            ]
            : [
                .init(color: shimmerEdgeColor.opacity(0.3), location: 0.0),
                .init(color: shimmerEdgeColor, location: 0.035),
                .init(color: .clear, location: 0.14),
                .init(color: shimmerTailColor, location: 1.0)
            ]

        return IOSContextMenuContainer(
            sections: clipboardContextMenuSections(for: screen.viewModel),
            previewStyle: counterRotatesForUpsideDownPortrait ? .hidden : .transformedSource
        ) {
            ZStack {
                displayShape
                    .fill(displayBaseColor)

                if isBlueTheme {
                    displayShape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(red: 0.830, green: 0.660, blue: 1.0).opacity(0.20), location: 0.0),
                                    .init(color: Color(red: 0.525, green: 0.435, blue: 0.990).opacity(0.16), location: 0.42),
                                    .init(color: Color(red: 0.455, green: 0.620, blue: 1.0).opacity(0.26), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    GeometryReader { geometry in
                        let size = geometry.size

                        ZStack {
                            Path { path in
                                path.move(to: .zero)
                                path.addLine(to: CGPoint(x: size.width * 0.48, y: 0))
                                path.addLine(to: CGPoint(x: 0, y: size.height * 0.56))
                                path.closeSubpath()
                            }
                            .fill(Color(red: 0.860, green: 0.710, blue: 1.0).opacity(0.19))

                            Path { path in
                                path.move(to: CGPoint(x: size.width * 0.60, y: size.height))
                                path.addLine(to: CGPoint(x: size.width, y: size.height))
                                path.addLine(to: CGPoint(x: size.width, y: size.height * 0.52))
                                path.closeSubpath()
                            }
                            .fill(Color(red: 0.650, green: 0.790, blue: 1.0).opacity(0.22))
                        }
                    }
                    .clipShape(displayShape)
                    .allowsHitTesting(false)

                    displayShape
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }

                ZStack {
                    displayShape
                        .fill(
                            LinearGradient(
                                stops: leadingShimmerStops,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(1.0)
                        .offset(x: parallaxX, y: parallaxY)

                    displayShape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0), location: 0.0),
                                    .init(color: shimmerBandColor, location: 0.5),
                                    .init(color: Color.white.opacity(0), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                            .scaleEffect(1.04)
                        .rotationEffect(.degrees(displayShimmerAngleDegrees))
                            .offset(x: parallaxX * 1.5, y: parallaxY * 0.55)
                }
                .compositingGroup()
                        .mask { shimmerHardMask.padding(1.2) }
                .clipShape(shimmerHardMask, style: FillStyle(eoFill: false, antialiased: false))
                .allowsHitTesting(false)

                if flashCopy || copyStreakActive {
                    GeometryReader { layerGeometry in
                        let streakWidth = max(56, layerGeometry.size.width * 0.22)
                        let copyFlashColor = Color.white
                        let copyFlashOpacity = colorScheme == .dark ? 0.18 : 0.24
                        let copyStreakOpacity = colorScheme == .dark ? 0.45 : 0.62

                        ZStack {
                            if flashCopy {
                                copyFlashColor
                                    .opacity(copyFlashOpacity)
                            }

                            if copyStreakActive {
                                LinearGradient(
                                    stops: [
                                        .init(color: copyFlashColor.opacity(0.0), location: 0.0),
                                        .init(color: copyFlashColor.opacity(copyStreakOpacity), location: 0.28),
                                        .init(color: copyFlashColor.opacity(1.0), location: 0.5),
                                        .init(color: copyFlashColor.opacity(copyStreakOpacity), location: 0.72),
                                        .init(color: copyFlashColor.opacity(0.0), location: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: streakWidth, height: layerGeometry.size.height * 1.6)
                                .rotationEffect(.degrees(-32))
                                .offset(
                                    x: layerGeometry.size.width * copyStreakTravel,
                                    y: layerGeometry.size.height * copyStreakTravel
                                )
                                .blendMode(.screen)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(displayShape)
                    }
                    .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    VStack(alignment: .trailing, spacing: metrics.displaySpacing) {
                        Text(screen.viewModel.expressionDisplay)
                            .font(EnterCalcFont.appFont(size: metrics.expressionFontSize(for: resultsTextHeight)))
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.35)

                        Text(screen.viewModel.display)
                            .font(EnterCalcFont.appFont(size: metrics.displayFontSize(for: resultsTextHeight)))
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.22)
                    }
                    .padding(.horizontal, metrics.displayHorizontalPadding)
                    .padding(.vertical, metrics.displayVerticalPadding)
                    .frame(maxWidth: .infinity, minHeight: resultsTextHeight, maxHeight: resultsTextHeight, alignment: .topTrailing)

                    if showsMemoryLabel {
                        Spacer(minLength: 0)
                        memoryControls(metrics: metrics, screen: screen)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: expandedResultAreaHeight, maxHeight: expandedResultAreaHeight, alignment: .top)
            .mask { displayShape.padding(0.6) }
            .clipShape(displayShape, style: FillStyle(eoFill: false, antialiased: false))
            .clipped()
            .contentShape(displayShape)
            .onTapGesture {
                copyDisplayToPasteboardWithFlash(from: screen.viewModel)
            }
        }
    }

    func memoryControls(metrics: IOSLayoutMetrics, screen: CalculatorScreenSession) -> some View {
        let basicLabelOpacity = activeTheme == .blue ? 0.24 : 0.15
        return Text("Basic")
            .font(EnterCalcFont.appFont(size: metrics.memoryFontSize))
            .foregroundStyle(palette.textPrimary.opacity(basicLabelOpacity))
            .frame(maxWidth: .infinity, minHeight: metrics.memoryHeight, maxHeight: metrics.memoryHeight, alignment: .leading)
            .padding(.horizontal, metrics.displayHorizontalPadding)
            .lineLimit(1)
    }

    func copyDisplayToPasteboardWithFlash(from viewModel: CalculatorViewModel) {
        viewModel.copyToPasteboard()
        triggerActionFeedback(emphasized: true)

        copyStreakTravel = 1.35
        copyStreakActive = true
        withAnimation(.linear(duration: 0.085)) {
            copyStreakTravel = -1.35
        }

        withAnimation(.easeOut(duration: 0.1)) {
            flashCopy = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.1)) {
                flashCopy = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            copyStreakActive = false
        }
    }

    func copyCurrentResultToPasteboard(from viewModel: CalculatorViewModel) {
        viewModel.copyToPasteboard()
        triggerActionFeedback()
    }

    func copyCurrentOperationToPasteboard(from viewModel: CalculatorViewModel) {
        guard viewModel.hasOperationToCopy else { return }
        viewModel.copyOperationToPasteboard()
        triggerActionFeedback()
    }

    func pasteFromPasteboard(into viewModel: CalculatorViewModel) {
        viewModel.pasteFromPasteboard()
        triggerActionFeedback()
    }

    func copyHistoryEntryResultToPasteboard(_ entry: HistoryEntry, from viewModel: CalculatorViewModel) {
        viewModel.copyResultToPasteboard(entry)
        triggerActionFeedback()
    }

    func copyHistoryEntryOperationToPasteboard(_ entry: HistoryEntry, from viewModel: CalculatorViewModel) {
        viewModel.copyOperationToPasteboard(entry)
        triggerActionFeedback()
    }

    func triggerActionFeedback() {
        triggerActionFeedback(emphasized: false)
    }

    func triggerKeyPressFeedback() {
#if canImport(UIKit)
        guard !actionHapticsDisabled() else {
            return
        }

        IOSActionHaptics.performKeyPress()
#endif
    }

    func triggerActionFeedback(emphasized: Bool) {
#if canImport(UIKit)
        guard !actionHapticsDisabled() else {
            return
        }

        IOSActionHaptics.perform(emphasized: emphasized)
#endif
    }

    func clipboardContextMenuSections(
        for viewModel: CalculatorViewModel,
        settingsTitleKey: String = "settings.title",
        includeSettingsAction: Bool = false
    ) -> [IOSContextMenuSection] {
        var sections = [
            IOSContextMenuSection(actions: [
                IOSContextMenuAction(
                    title: localized("copy"),
                    systemImage: "doc.on.doc",
                    handler: { copyCurrentResultToPasteboard(from: viewModel) }
                ),
                IOSContextMenuAction(
                    title: localized("history.copyOperation"),
                    systemImage: "doc.on.doc",
                    isDisabled: !viewModel.hasOperationToCopy,
                    handler: { copyCurrentOperationToPasteboard(from: viewModel) }
                ),
                IOSContextMenuAction(
                    title: localized("paste"),
                    systemImage: "doc.on.clipboard",
                    handler: { pasteFromPasteboard(into: viewModel) }
                )
            ])
        ]

        if includeSettingsAction {
            sections.append(
                IOSContextMenuSection(actions: [
                    IOSContextMenuAction(
                        title: localized(settingsTitleKey),
                        systemImage: "gearshape",
                        handler: { showSettingsSheet = true }
                    )
                ])
            )
        }

        return sections
    }

    func keypad(metrics: IOSLayoutMetrics, screen: CalculatorScreenSession, buttonHeight: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: metrics.gridSpacing), count: 4)

        return LazyVGrid(columns: columns, spacing: metrics.gridSpacing) {
            ForEach(Array(flattenedButtons.enumerated()), id: \.offset) { _, button in
                IOSKeypadButton(
                    button: button,
                    palette: palette,
                    metrics: metrics,
                    buttonHeight: buttonHeight,
                    pressFeedback: triggerKeyPressFeedback,
                    action: { button.action(screen.viewModel) },
                    operatorRevealProgress: operatorRevealProgress,
                    operatorAnimFadeOpacity: operatorAnimFadeOpacity
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    func keypadResizeHandle(metrics: IOSLayoutMetrics, screen: CalculatorScreenSession, height: CGFloat) -> some View {
        let accentColor = palette.accent
        let isActive = isResizingKeypadHeight
        let handleColor = isActive ? accentColor : palette.textSecondary.opacity(colorScheme == .dark ? 0.65 : 0.4)
        let lineColor = handleColor
        let handleBackground = isActive ? accentColor.opacity(colorScheme == .dark ? 0.14 : 0.12) : palette.surface
        let verticalCenterOffset = -metrics.sectionSpacing / 2
        let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isResizingKeypadHeight {
                    keypadResizeGestureStartMultiplier = normalizedKeypadHeightMultiplier(for: screen)
                    isResizingKeypadHeight = true
                    let startYText = String(format: "%.1f", value.startLocation.y)
                    DebugLog.emit("UI", "Keypad resize began screen:\(screen.id) home:\(screen.isHomeScreen) startMultiplier:\(keypadResizeGestureStartMultiplier) startY:\(startYText)")
                }

                let totalHeight = max(metrics.keypadHeight + metrics.displayHeight, 1)
                let delta = Double(value.translation.height / totalHeight)
                let newMultiplier = clamp(keypadResizeGestureStartMultiplier - delta, to: 0.5...1.0)
                let translationText = String(format: "%.1f", value.translation.height)
                let deltaText = String(format: "%.3f", delta)
                let multiplierText = String(format: "%.3f", newMultiplier)
                DebugLog.emit("UI", "Keypad resize changed screen:\(screen.id) translationY:\(translationText) delta:\(deltaText) multiplier:\(multiplierText)")
                updateActiveScreenSettings { $0.keypadHeightMultiplier = newMultiplier }
            }
            .onEnded { _ in
                let finalMultiplierText = String(format: "%.3f", normalizedKeypadHeightMultiplier(for: screen))
                DebugLog.emit("UI", "Keypad resize ended screen:\(screen.id) finalMultiplier:\(finalMultiplierText)")
                isResizingKeypadHeight = false
            }

        return ZStack {
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(lineColor)
                .frame(height: isActive ? 2 : 1)
                .padding(.horizontal, metrics.outerPadding + 24)

            Image(systemName: "arrow.up.arrow.down")
                .font(EnterCalcFont.appFont(size: 9))
                .foregroundStyle(handleColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(handleBackground)
                )
        }
            .offset(y: verticalCenterOffset)
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 36))
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .accessibilityLabel(Text("Resize keypad"))
        .accessibilityHint(Text("Drag up or down to resize the keypad"))
    }

    func cancelKeypadResize(screen: CalculatorScreenSession) {
        let finalMultiplierText = String(format: "%.3f", normalizedKeypadHeightMultiplier(for: screen))
        DebugLog.emit("UI", "Keypad resize cancelled screen:\(screen.id) finalMultiplier:\(finalMultiplierText)")
        isResizingKeypadHeight = false
    }

    func normalizedKeypadHeightMultiplier(for screen: CalculatorScreenSession) -> Double {
        clamp(screen.settings.keypadHeightMultiplier, to: 0.5...1.0)
    }

    func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    func toggleOverlay(_ overlay: IOSOverlayPane) {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeOverlay = activeOverlay == overlay ? nil : overlay
        }
    }

    func overlayScrim(metrics: IOSLayoutMetrics) -> some View {
        Color.black.opacity(metrics.mode == .padWide ? 0.22 : 0.4)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeOverlay = nil
                }
            }
    }

    @ViewBuilder
    func overlayPanel<Content: View>(metrics: IOSLayoutMetrics, @ViewBuilder content: () -> Content) -> some View {
        if metrics.usesBottomOverlaySheet {
            content()
                .frame(width: metrics.overlayPanelWidth, height: metrics.bottomOverlayPanelHeight)
                .padding(.bottom, metrics.overlayBottomPadding)
                .padding(.horizontal, metrics.mode == .phonePortrait ? metrics.outerPadding : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            content()
                .frame(width: metrics.overlayPanelWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: metrics.overlayAlignment)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.overlayBottomPadding)
                .padding(.trailing, metrics.outerPadding)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    func currentDeviceFamily() -> IOSDeviceFamily {
#if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
#else
        return .phone
#endif
    }
}

private struct IOSSettingsSheet: View {
    let titleKey: String
    let appearanceLabelKey: String
    @Binding var selectedTheme: String
    @Binding var selectedLanguage: String
    @Binding var usesScientificNotation: Bool
    @Binding var selectedNumberFormat: String
    @Binding var usesClassicPercentBehavior: Bool
    @Binding var usesEnterKeySymbol: Bool
    let availableLanguages: [LanguageOption]
    let counterRotatesForUpsideDownPortrait: Bool
    @State private var draftTheme: AppTheme
    @State private var draftLanguage: String
    @State private var draftScientificNotation: Bool
    @State private var draftNumberFormat: NumberFormatStyle
    @State private var draftClassicPercentBehavior: Bool
    @State private var draftUsesEnterKeySymbol: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    init(
        titleKey: String,
        appearanceLabelKey: String,
        selectedTheme: Binding<String>,
        selectedLanguage: Binding<String>,
        usesScientificNotation: Binding<Bool>,
        selectedNumberFormat: Binding<String>,
        usesClassicPercentBehavior: Binding<Bool>,
        usesEnterKeySymbol: Binding<Bool>,
        availableLanguages: [LanguageOption],
        counterRotatesForUpsideDownPortrait: Bool
    ) {
        self.titleKey = titleKey
        self.appearanceLabelKey = appearanceLabelKey
        self._selectedTheme = selectedTheme
        self._selectedLanguage = selectedLanguage
        self._usesScientificNotation = usesScientificNotation
        self._selectedNumberFormat = selectedNumberFormat
        self._usesClassicPercentBehavior = usesClassicPercentBehavior
        self._usesEnterKeySymbol = usesEnterKeySymbol
        self.availableLanguages = availableLanguages
        self.counterRotatesForUpsideDownPortrait = counterRotatesForUpsideDownPortrait
        _draftTheme = State(initialValue: AppTheme(rawValue: selectedTheme.wrappedValue) ?? .system)
        _draftLanguage = State(initialValue: selectedLanguage.wrappedValue)
        _draftScientificNotation = State(initialValue: usesScientificNotation.wrappedValue)
        _draftNumberFormat = State(initialValue: NumberFormatStyle(rawValue: selectedNumberFormat.wrappedValue) ?? NumberFormatStyle.detected())
        _draftClassicPercentBehavior = State(initialValue: usesClassicPercentBehavior.wrappedValue)
        _draftUsesEnterKeySymbol = State(initialValue: usesEnterKeySymbol.wrappedValue)
    }

    private var palette: Palette {
        Palette.forScheme(colorScheme)
    }

    private var themeSelection: Binding<AppTheme> {
        Binding(
            get: { draftTheme },
            set: { draftTheme = $0 }
        )
    }

    private var numberFormatSelection: Binding<NumberFormatStyle> {
        Binding(
            get: { draftNumberFormat },
            set: { draftNumberFormat = $0 }
        )
    }

    private func commitDraftSettings() {
        selectedTheme = draftTheme.rawValue
        selectedLanguage = draftLanguage
        usesScientificNotation = draftScientificNotation
        selectedNumberFormat = draftNumberFormat.rawValue
        usesClassicPercentBehavior = draftClassicPercentBehavior
        usesEnterKeySymbol = draftUsesEnterKeySymbol
    }

    private func creditAttributedString() -> AttributedString {
        let part1 = AttributedString(localized("settings.credit.part1"))
        var linkText = AttributedString(localized("settings.credit.linkText"))
        linkText.link = URL(string: "https://github.com/tipliai/enterCalc")!
        let middle = AttributedString(localized("settings.credit.middle"))

        return part1 + linkText + middle
    }

    private var versionString: String {
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

    var body: some View {
        ZStack {
            palette.surface
                .ignoresSafeArea()

            NavigationStack {
                Form {
                    Section(localized("settings.appearance")) {
                        Picker(localized(appearanceLabelKey), selection: themeSelection) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Text(theme.label).tag(theme)
                            }
                        }
                    }

                    Section(localized("settings.language")) {
                        Picker(localized("settings.language.label"), selection: $draftLanguage) {
                            ForEach(availableLanguages, id: \.code) { language in
                                Text(language.displayName).tag(language.code)
                            }
                        }
                    }

                    Section(localized("settings.userInterface")) {
                        Toggle(localized("settings.numberFormat.scientific"), isOn: $draftScientificNotation)
                        Toggle(localized("settings.percent.classicBehavior"), isOn: $draftClassicPercentBehavior)
                        Toggle(
                            localized("settings.equals.enterKeySymbol"),
                            isOn: Binding(
                                get: { !draftUsesEnterKeySymbol },
                                set: { draftUsesEnterKeySymbol = !$0 }
                            )
                        )
                        Picker(localized("settings.numberFormat.style"), selection: numberFormatSelection) {
                            ForEach(NumberFormatStyle.allCases, id: \.self) { style in
                                Text(style.example).tag(style)
                            }
                        }
                    }

                    Section(localized("settings.credits")) {
                        Text(creditAttributedString())
                            .font(EnterCalcFont.subheadline)
                        Text(String(format: localized("settings.credits.version"), versionString))
                            .font(EnterCalcFont.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(palette.surface)
                .navigationTitle(localized(titleKey))
                .iosInlineNavigationBarTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            commitDraftSettings()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text(localized("settings.close")))
                    }
                }
            }
        }
        .iosSheetBackground(palette.surface)
        .onDisappear {
            commitDraftSettings()
        }
        .rotationEffect(.degrees(counterRotatesForUpsideDownPortrait ? 180 : 0))
    }
}

private struct IOSHistoryPanel: View {
    let entries: [HistoryEntry]
    let palette: Palette
    let metrics: IOSLayoutMetrics
    let onSelect: (HistoryEntry) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void
    let onCopyEntry: (HistoryEntry) -> Void
    let onCopyOperationEntry: (HistoryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.panelSpacing) {
            if entries.isEmpty {
                Text(localized("history.empty"))
                    .font(EnterCalcFont.appFont(size: metrics.panelSecondaryFontSize + 2))
                    .foregroundColor(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: metrics.panelItemSpacing) {
                        ForEach(entries) { entry in
                            IOSContextMenuContainer(
                                sections: [
                                    IOSContextMenuSection(actions: [
                                        IOSContextMenuAction(
                                            title: localized("copy"),
                                            systemImage: "doc.on.doc",
                                            handler: { onCopyEntry(entry) }
                                        ),
                                        IOSContextMenuAction(
                                            title: localized("history.copyOperation"),
                                            systemImage: "doc.on.doc",
                                            handler: { onCopyOperationEntry(entry) }
                                        )
                                    ])
                                ]
                            ) {
                                Button {
                                    onSelect(entry)
                                } label: {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(entry.displayExpression) =")
                                            .font(EnterCalcFont.appFont(size: metrics.panelSecondaryFontSize))
                                            .foregroundColor(palette.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                        Text(entry.displayResult)
                                            .font(EnterCalcFont.appFont(size: metrics.panelPrimaryFontSize))
                                            .foregroundColor(palette.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    .padding(metrics.panelTilePadding)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .background(
                                        RoundedRectangle(cornerRadius: metrics.panelTileCornerRadius, style: .continuous)
                                            .fill(palette.historyTileBackground)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: entries.isEmpty ? onDismiss : onClear) {
                    Image(systemName: "trash")
                        .font(EnterCalcFont.appFont(size: metrics.panelPrimaryFontSize * 1.3))
                        .frame(width: metrics.headerButtonSize, height: metrics.headerButtonSize)
                        .foregroundColor(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, metrics.panelHorizontalPadding)
        .padding(.vertical, metrics.panelVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: metrics.surfaceCornerRadius, style: .continuous)
                .fill(palette.historyBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.surfaceCornerRadius, style: .continuous)
                .stroke(palette.buttonBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: metrics.surfaceCornerRadius, style: .continuous))
    }
}

private struct IOSContextMenuAction {
    let title: String
    let systemImage: String?
    var isDisabled: Bool = false
    let handler: () -> Void
}

private struct IOSContextMenuSection {
    let actions: [IOSContextMenuAction]
}

private enum IOSContextMenuPreviewStyle {
    case transformedSource
    case hidden
}

private struct IOSContextMenuContainer<Content: View>: View {
    let sections: [IOSContextMenuSection]
    let previewStyle: IOSContextMenuPreviewStyle
    let content: Content

    init(
        sections: [IOSContextMenuSection],
        previewStyle: IOSContextMenuPreviewStyle = .transformedSource,
        @ViewBuilder content: () -> Content
    ) {
        self.sections = sections
        self.previewStyle = previewStyle
        self.content = content()
    }

    var body: some View {
#if canImport(UIKit)
        IOSContextMenuRepresentable(sections: sections, previewStyle: previewStyle, content: content)
#else
        content
#endif
    }
}

#if canImport(UIKit)
private struct IOSContextMenuRepresentable<Content: View>: UIViewControllerRepresentable {
    let sections: [IOSContextMenuSection]
    let previewStyle: IOSContextMenuPreviewStyle
    let content: Content

    func makeUIViewController(context: Context) -> IOSContextMenuHostingViewController {
        IOSContextMenuHostingViewController(rootView: AnyView(content), sections: sections, previewStyle: previewStyle)
    }

    func updateUIViewController(_ uiViewController: IOSContextMenuHostingViewController, context: Context) {
        uiViewController.update(rootView: AnyView(content), sections: sections, previewStyle: previewStyle)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: IOSContextMenuHostingViewController,
        context: Context
    ) -> CGSize? {
        let targetSize = CGSize(
            width: proposal.width ?? UIScreen.main.bounds.width,
            height: proposal.height ?? UIView.layoutFittingExpandedSize.height
        )
        return uiViewController.sizeThatFits(in: targetSize)
    }
}

private final class IOSContextMenuHostingViewController: UIViewController, UIContextMenuInteractionDelegate {
    private let hostingController: UIHostingController<AnyView>
    private var sections: [IOSContextMenuSection]
    private var previewStyle: IOSContextMenuPreviewStyle

    init(rootView: AnyView, sections: [IOSContextMenuSection], previewStyle: IOSContextMenuPreviewStyle) {
        self.hostingController = UIHostingController(rootView: rootView)
        self.sections = sections
        self.previewStyle = previewStyle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        view.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    func update(rootView: AnyView, sections: [IOSContextMenuSection], previewStyle: IOSContextMenuPreviewStyle) {
        hostingController.rootView = rootView
        self.sections = sections
        self.previewStyle = previewStyle
    }

    func sizeThatFits(in targetSize: CGSize) -> CGSize {
        hostingController.sizeThatFits(in: targetSize)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard sections.contains(where: { !$0.actions.isEmpty }) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.makeMenu()
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        makeTargetedPreviewIfNeeded()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        makeTargetedPreviewIfNeeded()
    }

    private func makeMenu() -> UIMenu {
        let childMenus = sections.compactMap { section -> UIMenu? in
            let actions = section.actions.map { action in
                UIAction(
                    title: action.title,
                    image: action.systemImage.flatMap(UIImage.init(systemName:)),
                    attributes: action.isDisabled ? [.disabled] : []
                ) { _ in
                    action.handler()
                }
            }

            guard !actions.isEmpty else { return nil }
            return UIMenu(title: "", options: .displayInline, children: actions)
        }

        return UIMenu(title: "", children: childMenus)
    }

    private func makeTargetedPreviewIfNeeded() -> UITargetedPreview? {
        guard let containerView = view.window ?? view.superview else { return nil }

        if previewStyle == .hidden {
            let previewView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)))
            previewView.backgroundColor = .clear

            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(rect: .zero)

            let center = containerView.convert(
                CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                from: view
            )
            let target = UIPreviewTarget(container: containerView, center: center)
            return UITargetedPreview(view: previewView, parameters: parameters, target: target)
        }

        let previewTransform = accumulatedAffineTransform(from: view, to: containerView)
        guard !previewTransform.isIdentity else { return nil }
        guard let snapshot = hostingController.view.snapshotView(afterScreenUpdates: false) else { return nil }

        snapshot.frame = view.bounds
        snapshot.transform = previewTransform

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear

        let center = containerView.convert(
            CGPoint(x: view.bounds.midX, y: view.bounds.midY),
            from: view
        )
        let target = UIPreviewTarget(container: containerView, center: center)
        return UITargetedPreview(view: snapshot, parameters: parameters, target: target)
    }

    private func accumulatedAffineTransform(from sourceView: UIView, to containerView: UIView) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        var currentView: UIView? = sourceView

        while let view = currentView, view !== containerView {
            transform = view.transform.concatenating(transform)
            currentView = view.superview
        }

        return transform
    }
}
#endif

private struct LanguageOption {
    let code: String
    let displayName: String
}

private extension View {
    @ViewBuilder
    func iosInlineNavigationBarTitle() -> some View {
#if canImport(UIKit)
        self.navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func iosSheetBackground(_ color: Color) -> some View {
#if canImport(UIKit)
        self.presentationBackground(color)
#else
        self
#endif
    }
}

private enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
    case blue

    var label: String {
        switch self {
        case .system: return localized("settings.theme.system")
        case .light: return localized("settings.theme.light")
        case .dark: return localized("settings.theme.dark")
        case .blue: return localized("settings.theme.blue")
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

    func palette(using systemColorScheme: ColorScheme) -> Palette {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .blue:
            return .blue
        case .system:
            return Palette.forScheme(systemColorScheme)
        }
    }
}

private enum IOSOverlayPane {
    case history
}

private enum IOSLayoutMode {
    case phonePortrait
    case phoneLandscape
    case padWide
}

private enum IOSDeviceFamily {
    case phone
    case pad
}

private struct IOSLayoutMetrics {
    static let minimumPadWindowSize = CGSize(width: 340, height: 540)
    static let defaultPadWindowSize = minimumPadWindowSize

    let mode: IOSLayoutMode
    let outerPadding: CGFloat
    let innerHorizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let headerSpacing: CGFloat
    let gridSpacing: CGFloat
    let memorySpacing: CGFloat
    let headerHeight: CGFloat
    let headerButtonSize: CGFloat
    let headerIconFontSize: CGFloat
    let headerCornerRadius: CGFloat
    let titleFontSize: CGFloat
    let displayHeight: CGFloat
    let displaySpacing: CGFloat
    let expressionFontSize: CGFloat
    let displayFontSize: CGFloat
    let displayHorizontalPadding: CGFloat
    let displayVerticalPadding: CGFloat
    let memoryHeight: CGFloat
    let memoryFontSize: CGFloat
    let buttonHeight: CGFloat
    let buttonFontSize: CGFloat
    let buttonCornerRadius: CGFloat
    let surfaceCornerRadius: CGFloat
    let historyPanelWidth: CGFloat
    let overlayPanelWidth: CGFloat
    let calculatorWidth: CGFloat
    let panelSpacing: CGFloat
    let panelItemSpacing: CGFloat
    let panelHorizontalPadding: CGFloat
    let panelVerticalPadding: CGFloat
    let panelTilePadding: CGFloat
    let panelTileCornerRadius: CGFloat
    let panelPrimaryFontSize: CGFloat
    let panelSecondaryFontSize: CGFloat
    let minimumButtonHeight: CGFloat
    let pageIndicatorDotSize: CGFloat
    let pageIndicatorSpacing: CGFloat
    let portraitBottomReserveWithoutPagination: CGFloat
    let usesInlineLandscapeHistory: Bool
    let titlebarLeadingInset: CGFloat
    let usesAdaptiveScaling: Bool

    init(size: CGSize, safeAreaInsets: EdgeInsets, horizontalSizeClass: UserInterfaceSizeClass?, deviceFamily: IOSDeviceFamily) {
        let isLandscape = size.width > size.height
        let usesWidePadLayout = deviceFamily == .pad && horizontalSizeClass == .regular && size.width >= 700
        let isPadWindow = deviceFamily == .pad
        let pageIndicatorReserve: CGFloat = isPadWindow ? 18 : 0
        let needsLegacyPhoneBottomReserve = !isPadWindow && !isLandscape && size.height <= 750 && safeAreaInsets.bottom < 10

        if usesWidePadLayout {
            mode = .padWide
        } else if isLandscape {
            mode = .phoneLandscape
        } else {
            mode = .phonePortrait
        }

        switch mode {
        case .phonePortrait:
            outerPadding = isPadWindow ? max(14, safeAreaInsets.leading + 14) : 12
            innerHorizontalPadding = 0
            topPadding = isPadWindow ? max(48, safeAreaInsets.top + 16) : 0
            bottomPadding = isPadWindow ? max(8, safeAreaInsets.bottom + 2) : 8
            contentTopPadding = 6
            contentBottomPadding = 6
            sectionSpacing = 12
            headerSpacing = 10
            gridSpacing = 8
            memorySpacing = 6
            headerHeight = isPadWindow ? 46 : 52
            headerButtonSize = isPadWindow ? 42 : 50
            headerIconFontSize = isPadWindow ? 20 : 24
            headerCornerRadius = 10
            titleFontSize = isPadWindow ? 23 : 27
            let availableHeight = max(size.height - topPadding - bottomPadding - contentTopPadding - contentBottomPadding, isPadWindow ? 320 : 480)
            displayHeight = min(max(availableHeight * 0.15, isPadWindow ? 72 : 96), isPadWindow ? 116 : 132)
            displaySpacing = 6
            expressionFontSize = 15
            displayFontSize = min(max(availableHeight * 0.072, isPadWindow ? 34 : 42), 56)
            displayHorizontalPadding = 14
            displayVerticalPadding = 10
            let rowBudget = max(availableHeight - headerHeight - displayHeight - sectionSpacing * 3 - gridSpacing * 5 - pageIndicatorReserve, isPadWindow ? 138 : 252)
            let unit = rowBudget / 6.78
            memoryHeight = min(max(unit * 0.72, isPadWindow ? 22 : 28), 38)
            memoryFontSize = min(max(unit * 0.38, isPadWindow ? 12 : 14), 19)
            buttonHeight = min(max(unit, isPadWindow ? 28 : 42), 78)
            buttonFontSize = min(max(unit * 0.42, isPadWindow ? 17 : 20), 30)
            buttonCornerRadius = min(max(unit * 0.28, 14), 24)
            surfaceCornerRadius = 24
            historyPanelWidth = 0
            overlayPanelWidth = min(max(size.width - outerPadding * 2, 280), 460)
            calculatorWidth = size.width - outerPadding * 2
            panelSpacing = 12
            panelItemSpacing = 8
            panelHorizontalPadding = 10
            panelVerticalPadding = 10
            panelTilePadding = 8
            panelTileCornerRadius = 12
            panelPrimaryFontSize = 16
            panelSecondaryFontSize = 12
            minimumButtonHeight = isPadWindow ? 24 : 34
            pageIndicatorDotSize = 7
            pageIndicatorSpacing = 8
            portraitBottomReserveWithoutPagination = needsLegacyPhoneBottomReserve ? 24 : 0
            usesInlineLandscapeHistory = false
            titlebarLeadingInset = 0
            usesAdaptiveScaling = isPadWindow
        case .phoneLandscape:
            outerPadding = isPadWindow ? max(14, safeAreaInsets.leading + 14) : 10
            innerHorizontalPadding = 0
            topPadding = isPadWindow ? max(40, safeAreaInsets.top + 14) : 8
            bottomPadding = isPadWindow ? max(8, safeAreaInsets.bottom + 8) : 8
            contentTopPadding = 0
            contentBottomPadding = 0
            sectionSpacing = 8
            headerSpacing = 8
            gridSpacing = 6
            memorySpacing = 4
            headerHeight = isPadWindow ? 38 : 34
            headerButtonSize = isPadWindow ? 34 : 30
            headerIconFontSize = isPadWindow ? 15 : 14
            headerCornerRadius = 7
            titleFontSize = isPadWindow ? 18 : 17
            let historyWidth = min(max(size.width * 0.31, 185), 250)
            historyPanelWidth = historyWidth
            let leftWidth = max(size.width - historyWidth - outerPadding * 3, 300)
            calculatorWidth = leftWidth
            let availableHeight = max(size.height - topPadding - bottomPadding, isPadWindow ? 250 : 260)
            displayHeight = min(max(availableHeight * 0.18, isPadWindow ? 54 : 62), 88)
            displaySpacing = 3
            expressionFontSize = 12
            displayFontSize = min(max(availableHeight * 0.095, isPadWindow ? 24 : 28), 44)
            displayHorizontalPadding = 12
            displayVerticalPadding = 8
            let rowBudget = max(availableHeight - headerHeight - displayHeight - sectionSpacing * 3 - gridSpacing * 5 - pageIndicatorReserve, isPadWindow ? 120 : 150)
            let unit = rowBudget / 6.72
            memoryHeight = min(max(unit * 0.70, isPadWindow ? 18 : 20), 28)
            memoryFontSize = min(max(unit * 0.42, 10), 15)
            buttonHeight = min(max(unit, isPadWindow ? 22 : 28), 48)
            buttonFontSize = min(max(unit * 0.50, isPadWindow ? 14 : 16), 24)
            buttonCornerRadius = min(max(unit * 0.26, 10), 18)
            surfaceCornerRadius = 20
            overlayPanelWidth = historyWidth
            panelSpacing = 8
            panelItemSpacing = 6
            panelHorizontalPadding = 8
            panelVerticalPadding = 8
            panelTilePadding = 7
            panelTileCornerRadius = 10
            panelPrimaryFontSize = 14
            panelSecondaryFontSize = 11
            minimumButtonHeight = isPadWindow ? 20 : 24
            pageIndicatorDotSize = 6
            pageIndicatorSpacing = 6
            portraitBottomReserveWithoutPagination = 0
            usesInlineLandscapeHistory = !isPadWindow
            titlebarLeadingInset = 0
            usesAdaptiveScaling = isPadWindow
        case .padWide:
            outerPadding = max(18, safeAreaInsets.leading + 12)
            innerHorizontalPadding = 0
            topPadding = max(14, safeAreaInsets.top + 10)
            bottomPadding = max(14, safeAreaInsets.bottom + 14)
            contentTopPadding = 0
            contentBottomPadding = 0
            sectionSpacing = 14
            headerSpacing = 12
            gridSpacing = 10
            memorySpacing = 8
            headerHeight = 44
            headerButtonSize = 36
            headerIconFontSize = 17
            headerCornerRadius = 9
            titleFontSize = 22
            calculatorWidth = min(max(size.width * 0.46, 420), 560)
            let availableHeight = max(size.height - topPadding - bottomPadding, 700)
            displayHeight = min(max(availableHeight * 0.16, 120), 156)
            displaySpacing = 6
            expressionFontSize = 16
            displayFontSize = min(max(availableHeight * 0.072, 50), 62)
            displayHorizontalPadding = 16
            displayVerticalPadding = 12
            let rowBudget = max(availableHeight - headerHeight - displayHeight - sectionSpacing * 3 - gridSpacing * 5 - pageIndicatorReserve, 360)
            let unit = rowBudget / 6.85
            memoryHeight = min(max(unit * 0.72, 32), 42)
            memoryFontSize = min(max(unit * 0.38, 15), 20)
            buttonHeight = min(max(unit, 52), 82)
            buttonFontSize = min(max(unit * 0.40, 22), 32)
            buttonCornerRadius = min(max(unit * 0.24, 16), 24)
            surfaceCornerRadius = 26
            historyPanelWidth = 0
            overlayPanelWidth = min(max(size.width * 0.32, 280), 360)
            panelSpacing = 14
            panelItemSpacing = 10
            panelHorizontalPadding = 12
            panelVerticalPadding = 12
            panelTilePadding = 10
            panelTileCornerRadius = 14
            panelPrimaryFontSize = 17
            panelSecondaryFontSize = 13
            minimumButtonHeight = 40
            pageIndicatorDotSize = 7
            pageIndicatorSpacing = 8
            portraitBottomReserveWithoutPagination = 0
            usesInlineLandscapeHistory = false
            titlebarLeadingInset = 0
            usesAdaptiveScaling = true
        }
    }

    func buttonHeight(for availableHeight: CGFloat) -> CGFloat {
        let spacingTotal = gridSpacing * 5
        let fittedHeight = (max(availableHeight, spacingTotal + 6) - spacingTotal) / 6
        return min(buttonHeight, max(minimumButtonHeight, fittedHeight))
    }

    func expressionFontSize(for displayHeight: CGFloat) -> CGFloat {
        let scale = min(max(displayHeight / max(self.displayHeight, 1), 1), 1.4)
        return expressionFontSize * scale
    }

    func displayFontSize(for displayHeight: CGFloat) -> CGFloat {
        let scale = min(max(displayHeight / max(self.displayHeight, 1), 1), 1.42)
        return displayFontSize * scale
    }

    var keypadHeight: CGFloat {
        buttonHeight * 6 + gridSpacing * 5
    }

    var pageIndicatorHeight: CGFloat {
        pageIndicatorDotSize
    }

    var preferredSurfaceHeight: CGFloat {
        contentTopPadding
        + headerHeight
        + displayHeight
        + memoryHeight
        + 10
        + keypadHeight
        + pageIndicatorHeight
        + sectionSpacing * 4
        + contentBottomPadding
    }

    func surfaceScaleFactor(for availableHeight: CGFloat) -> CGFloat {
        guard usesAdaptiveScaling, preferredSurfaceHeight > 0 else { return 1 }
        return min(1, max(0.58, availableHeight / preferredSurfaceHeight))
    }

    var usesBottomOverlaySheet: Bool {
        mode != .padWide
    }

    var bottomOverlayPanelHeight: CGFloat {
        keypadHeight + sectionSpacing
    }

    var overlayBottomPadding: CGFloat {
        switch mode {
        case .phonePortrait:
            return contentBottomPadding
        case .phoneLandscape, .padWide:
            return bottomPadding
        }
    }

    var showsHistoryButton: Bool {
        mode != .phoneLandscape || !usesInlineLandscapeHistory
    }

    var usesOverlayHistory: Bool {
        mode != .phoneLandscape || !usesInlineLandscapeHistory
    }

    var overlayAlignment: Alignment {
        mode == .padWide ? .trailing : .bottom
    }
}

private extension EnterCalcIOSView {
    func syncSystemSettingsMetadata() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["settings.haptics.disabled": false])

        if defaults.object(forKey: "settings.haptics.disabled") == nil,
           let legacyUsesActionHaptics = defaults.object(forKey: "settings.haptics.actions") as? Bool {
            defaults.set(!legacyUsesActionHaptics, forKey: "settings.haptics.disabled")
            defaults.removeObject(forKey: "settings.haptics.actions")
        }

        defaults.set(systemSettingsVersionString(), forKey: "settings.about.version")
    }

    func actionHapticsDisabled() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["settings.haptics.disabled": false])

        if defaults.object(forKey: "settings.haptics.disabled") != nil {
            return defaults.bool(forKey: "settings.haptics.disabled")
        }

        if let legacyUsesActionHaptics = defaults.object(forKey: "settings.haptics.actions") as? Bool {
            return !legacyUsesActionHaptics
        }

        return false
    }

    func systemSettingsVersionString() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !version.isEmpty {
            return version
        }

        return "Version unavailable"
    }

    func normalizePreferredLanguageIfNeeded() {
        if isDefaultLocalizationSelection(preferredLanguage) {
            return
        }

        let resolvedCode = resolvedLocalizationCode(for: preferredLanguage)
        if preferredLanguage != resolvedCode {
            preferredLanguage = resolvedCode
        }
    }

    func availableLanguageOptions() -> [LanguageOption] {
        let resolvedDefaultCode = resolvedLocalizationCode()
        let defaultOption = LanguageOption(
            code: defaultLocalizationSelectionCode,
            displayName: String(
                format: localized("settings.language.defaultOption"),
                localizationDisplayName(for: resolvedDefaultCode)
            )
        )

        let explicitOptions = supportedLocalizationCodes().map { code in
            LanguageOption(code: code, displayName: localizationDisplayName(for: code).capitalized)
        }.sorted { $0.displayName < $1.displayName }

        return [defaultOption] + explicitOptions
    }

    func applyLanguage(_ code: String, refreshing calculatorViewModel: CalculatorViewModel? = nil) {
        languageOverrideBundle = isDefaultLocalizationSelection(code) ? nil : localizationBundle(for: code)
        (calculatorViewModel ?? viewModel).refreshLocalization()
    }
}

private extension View {
    @ViewBuilder
    func iPadWindowMinimumSize() -> some View {
#if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .pad {
            frame(
                minWidth: IOSLayoutMetrics.minimumPadWindowSize.width,
                minHeight: IOSLayoutMetrics.minimumPadWindowSize.height
            )
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func onIOSDeviceOrientationChange(perform action: @escaping () -> Void) -> some View {
#if canImport(UIKit)
        onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            action()
        }
#else
        self
#endif
    }

    @ViewBuilder
    func onValueChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17, macOS 14, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

private struct IOSCalcButton {
    enum Kind {
        case digit, operation, function, equals
    }

    let title: String
    let kind: Kind
    let action: (CalculatorViewModel) -> Void

    static func digit(_ title: String) -> IOSCalcButton {
        IOSCalcButton(title: title, kind: .digit, action: { $0.inputDigit(title) })
    }

    static func decimal() -> IOSCalcButton {
        IOSCalcButton(title: ".", kind: .digit, action: { $0.inputDecimal() })
    }

    static func operation(_ title: String, action: @escaping (CalculatorViewModel) -> Void) -> IOSCalcButton {
        IOSCalcButton(title: title, kind: .operation, action: action)
    }

    static func function(_ title: String, action: @escaping (CalculatorViewModel) -> Void) -> IOSCalcButton {
        IOSCalcButton(title: title, kind: .function, action: action)
    }

    static func equals(title: String = "⏎") -> IOSCalcButton {
        IOSCalcButton(title: title, kind: .equals, action: { $0.evaluate() })
    }

    private static let highlightedTitles: Set<String> = []
    private static let gradientTitles: Set<String> = []

    func backgroundStyle(palette: Palette) -> AnyShapeStyle {
        switch kind {
        case .digit:
            return AnyShapeStyle(palette.buttonNumber)
        case .operation:
            return AnyShapeStyle(palette.buttonOperation)
        case .function:
            return AnyShapeStyle(palette.buttonFunction)
        case .equals:
            return AnyShapeStyle(palette.accent)
        }
    }

    func foregroundColor(palette: Palette) -> Color {
        switch kind {
        case .digit, .function:
            return palette.textPrimary
        case .operation:
            return palette.textPrimary
        case .equals:
            return palette.accentText
        }
    }
}

private struct IOSKeypadButton: View {
    let button: IOSCalcButton
    let palette: Palette
    let metrics: IOSLayoutMetrics
    let buttonHeight: CGFloat
    let pressFeedback: () -> Void
    let action: () -> Void
    var operatorRevealProgress: Double = 0.0
    var operatorAnimFadeOpacity: Double = 1.0
    @State private var shimmerProgress: CGFloat = 0
    @State private var shimmerVisible: Bool = false

    // Reveal order from bottom (+) to top (÷): +→0, −→1, ×→2, ÷→3
    private static let operatorRevealOrder: [String: Int] = ["+": 0, "−": 1, "×": 2, "÷": 3]
    private struct GlyphOffset {
        var horizontal: CGFloat = 0
        var vertical: CGFloat = 0
    }

    private struct SignToggleLabelTuning {
        var overallLabelOffset: GlyphOffset = GlyphOffset()
        var glyphSpacing: CGFloat = 0
        var plusGlyphOffset: GlyphOffset = GlyphOffset()
        var slashGlyphOffset: GlyphOffset = GlyphOffset()
        var minusGlyphOffset: GlyphOffset = GlyphOffset()
    }

    private enum SpecialButtonLabelTuning {
        static let signToggle = SignToggleLabelTuning()
    }

    private var isEqualsButton: Bool { button.kind == .equals }
    private var scaledCornerRadius: CGFloat {
        let baseHeight = max(metrics.buttonHeight, 1)
        let scale = buttonHeight / baseHeight
        return min(metrics.buttonCornerRadius, max(8, metrics.buttonCornerRadius * scale))
    }
    private var equalsButtonGradient: LinearGradient {
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

    var body: some View {
        Button(action: handleTap) {
            labelView
                .foregroundStyle(button.foregroundColor(palette: palette))
                .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(button.title))
        .buttonStyle(
            IOSPressedButtonStyle(
                cornerRadius: scaledCornerRadius,
                overlayColor: palette.buttonHoverOverlay
            )
        )
        .overlay {
            if isEqualsButton && shimmerVisible {
                GeometryReader { geo in
                    let diagonal = (geo.size.width * geo.size.width + geo.size.height * geo.size.height).squareRoot()
                    let travel = diagonal * 3.0
                    let offset = (0.5 - shimmerProgress) * travel

                    RoundedRectangle(cornerRadius: scaledCornerRadius, style: .continuous)
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
                .clipShape(RoundedRectangle(cornerRadius: scaledCornerRadius, style: .continuous))
                .allowsHitTesting(false)
            }
        }
    }

    private func handleTap() {
        pressFeedback()
        action()
        guard isEqualsButton else { return }
        shimmerProgress = 0
        shimmerVisible = true
        withAnimation(.linear(duration: 0.17)) {
            shimmerProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            shimmerVisible = false
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let cr = scaledCornerRadius
        if isEqualsButton {
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .fill(equalsButtonGradient)
        } else if let revealOrder = Self.operatorRevealOrder[button.title],
           let gradColor = palette.operatorColumnColor(for: button.title) {
            let overlayOpacity = min(1.0, max(0.0, operatorRevealProgress - Double(revealOrder))) * operatorAnimFadeOpacity
            ZStack {
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .fill(button.backgroundStyle(palette: palette))
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .fill(gradColor)
                    .opacity(overlayOpacity)
            }
        } else {
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .fill(button.backgroundStyle(palette: palette))
        }
    }

    @ViewBuilder
    private var labelView: some View {
        switch button.title {
        case "1/x":
            let iconWidth = min(max(buttonHeight * 0.68, 24), 38)
            let iconHeight = min(max(buttonHeight * 0.68, 24), 38)
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
        case "x²":
            let iconWidth = min(max(buttonHeight * 0.68, 24), 38)
            let iconHeight = min(max(buttonHeight * 0.68, 24), 38)
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
        case "²√x":
            let iconWidth = min(max(buttonHeight * 0.68, 24), 38)
            let iconHeight = min(max(buttonHeight * 0.68, 24), 38)
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
        case "+/−":
            let tuning = SpecialButtonLabelTuning.signToggle

            HStack(spacing: tuning.glyphSpacing) {
                Text("+")
                    .font(EnterCalcFont.thinAppFont(size: signSize))
                    .offset(x: tuning.plusGlyphOffset.horizontal, y: tuning.plusGlyphOffset.vertical)
                Text("/")
                    .font(EnterCalcFont.thinAppFont(size: slashSize))
                    .offset(x: tuning.slashGlyphOffset.horizontal, y: tuning.slashGlyphOffset.vertical)
                Text("−")
                    .font(EnterCalcFont.thinAppFont(size: signSize))
                    .offset(x: tuning.minusGlyphOffset.horizontal, y: tuning.minusGlyphOffset.vertical)
            }
            .offset(x: tuning.overallLabelOffset.horizontal, y: tuning.overallLabelOffset.vertical)
        default:
            Text(button.title)
                .font(buttonFont)
        }
    }

    private var symbolBaseSize: CGFloat {
        min(metrics.buttonFontSize, buttonHeight * 0.52)
    }

    private var slashSize: CGFloat {
        symbolBaseSize * 1.02
    }

    private var signSize: CGFloat {
        symbolBaseSize * 0.72
    }

    private var buttonFont: Font {
        EnterCalcFont.thinAppFont(size: symbolBaseSize)
    }
}

private struct IOSPressedButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let overlayColor: Color
    var overlayOpacity: Double = 1
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(overlayColor)
                    .opacity(configuration.isPressed ? overlayOpacity : 0)
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
