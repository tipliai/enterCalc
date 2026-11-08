import Combine
import Foundation

// Persisted, user-facing preferences for a single calculator screen. Stored as
// raw values (strings/bools) so they map cleanly to UserDefaults and SwiftUI
// @AppStorage.
public struct CalculatorScreenSettings: Equatable {
    public var themeRawValue: String
    public var languageCode: String
    public var usesScientificNotation: Bool
    public var numberFormatStyleRawValue: String
    public var disablesSwipeDownToRound: Bool
    public var disablesButtonSound: Bool
    public var keypadHeightMultiplier: Double
    /// Symbol the currency key inserts. Defaults to the device region's
    /// currency until the user picks one in Settings.
    public var currencySymbol: String
    /// Which function sits in each configurable key on this page.
    public var functionKeyAssignments: CalculatorFunctionKeyAssignments

    public init(
        themeRawValue: String,
        languageCode: String,
        usesScientificNotation: Bool,
        numberFormatStyleRawValue: String,
        disablesSwipeDownToRound: Bool = false,
        disablesButtonSound: Bool = false,
        keypadHeightMultiplier: Double = 1.0,
        currencySymbol: String = CurrencyCatalog.detected().symbol,
        functionKeyAssignments: CalculatorFunctionKeyAssignments = .default
    ) {
        self.themeRawValue = themeRawValue
        self.languageCode = languageCode
        self.usesScientificNotation = usesScientificNotation
        self.numberFormatStyleRawValue = numberFormatStyleRawValue
        self.disablesSwipeDownToRound = disablesSwipeDownToRound
        self.disablesButtonSound = disablesButtonSound
        self.keypadHeightMultiplier = keypadHeightMultiplier
        self.currencySymbol = currencySymbol
        self.functionKeyAssignments = functionKeyAssignments
    }

    public var numberFormatStyle: NumberFormatStyle {
        NumberFormatStyle(rawValue: numberFormatStyleRawValue) ?? NumberFormatStyle.detected()
    }
}

// One live calculator "screen": pairs a view model with its settings and
// re-publishes the view model's changes so SwiftUI observes a single object.
public final class CalculatorScreenSession: ObservableObject, Identifiable {
    public let id: UUID
    /// The first screen, whose settings are the app's stored settings. Set
    /// at creation, or when the home screen closes and this one takes its
    /// place (#168).
    public private(set) var isHomeScreen: Bool
    public let viewModel: CalculatorViewModel

    @Published public private(set) var settings: CalculatorScreenSettings
    @Published public private(set) var historyOverlayHeight: Double?

    private var cancellables: Set<AnyCancellable> = []

    public init(
        id: UUID = UUID(),
        isHomeScreen: Bool = false,
        settings: CalculatorScreenSettings
    ) {
        self.id = id
        self.isHomeScreen = isHomeScreen
        self.settings = settings
        self.viewModel = CalculatorViewModel(
            numberFormatStyle: settings.numberFormatStyle,
            usesScientificNotation: settings.usesScientificNotation
        )

        bindViewModel()
        applyCalculatorSettings()
    }

    func becomeHomeScreen() {
        isHomeScreen = true
    }

    public func replaceSettings(_ settings: CalculatorScreenSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        applyCalculatorSettings()
    }

    public func updateSettings(_ update: (inout CalculatorScreenSettings) -> Void) {
        var updated = settings
        update(&updated)
        replaceSettings(updated)
    }

    public func updateHistoryOverlayHeight(_ height: Double?) {
        let normalizedHeight = height.map { max(0, $0) }
        guard historyOverlayHeight != normalizedHeight else { return }
        historyOverlayHeight = normalizedHeight
    }

    public func applyCalculatorSettings() {
        viewModel.setScientificNotationEnabled(settings.usesScientificNotation)
        viewModel.setNumberFormatStyle(settings.numberFormatStyle)
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

// Owns the ordered list of screens (iPad multi-page support) and the active
// index. macOS uses one view model per window instead and does not use this.
public final class CalculatorScreenStore: ObservableObject {
    public static let maxScreenCount: Int = 5

    @Published public private(set) var screens: [CalculatorScreenSession]
    @Published public private(set) var activeIndex: Int
    /// The screen shown on the second half of a display that holds two
    /// calculators side by side, the iPhone Duo's inner display in book
    /// position (#168), or nil while that half shows something else. Both
    /// halves page through the same screens and may show the same one.
    @Published public private(set) var secondaryIndex: Int?

    private var screenObservers: Set<AnyCancellable> = []

    public init(homeSettings: CalculatorScreenSettings) {
        self.screens = [CalculatorScreenSession(isHomeScreen: true, settings: homeSettings)]
        self.activeIndex = 0
        bindScreens()
    }

    public var screenCount: Int {
        screens.count
    }

    public var canCreateScreen: Bool {
        screens.count < Self.maxScreenCount
    }

    public var canCloseActiveScreen: Bool {
        activeIndex > 0
    }

    public var activeScreen: CalculatorScreenSession {
        screens[activeIndex]
    }

    public var homeScreen: CalculatorScreenSession {
        screens[0]
    }

    public var secondaryScreen: CalculatorScreenSession? {
        secondaryIndex.map { screens[$0] }
    }

    @discardableResult
    public func activateScreen(at index: Int) -> Bool {
        guard screens.indices.contains(index) else { return false }
        guard activeIndex != index else { return true }
        activeIndex = index
        return true
    }

    @discardableResult
    public func insertScreenAfterActive(homeSettings: CalculatorScreenSettings) -> Bool {
        insertScreen(after: activeIndex, homeSettings: homeSettings)
    }

    @discardableResult
    public func insertScreen(after index: Int, homeSettings: CalculatorScreenSettings) -> Bool {
        guard let insertIndex = insertNewScreen(after: index, homeSettings: homeSettings) else { return false }
        activeIndex = insertIndex
        return true
    }

    /// Opens a new screen after the active one and shows it on the second
    /// half, leaving the active screen where it is (#168).
    @discardableResult
    public func insertSecondaryScreenAfterActive(homeSettings: CalculatorScreenSettings) -> Bool {
        guard let insertIndex = insertNewScreen(after: activeIndex, homeSettings: homeSettings) else { return false }
        secondaryIndex = insertIndex
        return true
    }

    /// Opens a new screen after the given one and shows it on the second
    /// half; the main half keeps its screen, renumbered when the new one
    /// lands before it (#168).
    @discardableResult
    public func insertSecondaryScreen(after index: Int, homeSettings: CalculatorScreenSettings) -> Bool {
        guard let insertIndex = insertNewScreen(after: index, homeSettings: homeSettings) else { return false }
        if activeIndex >= insertIndex {
            activeIndex += 1
        }
        secondaryIndex = insertIndex
        return true
    }

    private func insertNewScreen(after index: Int, homeSettings: CalculatorScreenSettings) -> Int? {
        guard screens.count < Self.maxScreenCount else { return nil }
        let clampedIndex = min(max(index, 0), max(screens.count - 1, 0))
        let insertIndex = min(clampedIndex + 1, screens.count)
        let newScreen = CalculatorScreenSession(settings: homeSettings)
        screens.insert(newScreen, at: insertIndex)
        if let secondaryIndex, secondaryIndex >= insertIndex {
            self.secondaryIndex = secondaryIndex + 1
        }
        bindScreens()
        return insertIndex
    }

    /// Shows a screen on the second half, opening that half if it was
    /// closed (#168).
    @discardableResult
    public func showSecondaryScreen(at index: Int) -> Bool {
        guard screens.indices.contains(index) else { return false }
        secondaryIndex = index
        return true
    }

    @discardableResult
    public func activateSecondaryScreen(at index: Int) -> Bool {
        guard secondaryIndex != nil, screens.indices.contains(index) else { return false }
        guard secondaryIndex != index else { return true }
        secondaryIndex = index
        return true
    }

    /// Takes the screen off the second half without closing it; it stays in
    /// the pages.
    public func closeSecondary() {
        secondaryIndex = nil
    }

    @discardableResult
    public func closeActiveScreen() -> Bool {
        closeScreen(at: activeIndex)
    }

    /// Closes any screen but the home screen. Each half stays on the screen it
    /// was showing. The main half moves to the one before a closed screen it
    /// was showing; the second half moves to the one after (or before, when
    /// it was the last), so closing from it goes through the screens rather
    /// than landing on the home screen, where the next close shuts the half.
    /// With one screen left there is nothing for the second half to show on
    /// its own, so it closes.
    @discardableResult
    public func closeScreen(at index: Int) -> Bool {
        guard index > 0, screens.indices.contains(index) else { return false }
        screens.remove(at: index)
        if activeIndex > index {
            activeIndex -= 1
        } else if activeIndex == index {
            activeIndex = min(index - 1, screens.count - 1)
        }
        if let secondaryIndex {
            if screens.count <= 1 {
                self.secondaryIndex = nil
            } else if secondaryIndex > index {
                self.secondaryIndex = secondaryIndex - 1
            } else if secondaryIndex == index {
                self.secondaryIndex = min(index, screens.count - 1)
            }
        }
        bindScreens()
        return true
    }

    /// Closes the home screen when another screen can take its place: the
    /// next screen becomes the home screen and keeps its own settings, which
    /// the caller then stores as the app's. Each half moves with its screen;
    /// a half that showed the home screen shows the new one. With one screen
    /// left the second half closes (#168).
    @discardableResult
    public func closeHomeScreenPromotingNext() -> Bool {
        guard screens.count > 1 else { return false }
        screens.remove(at: 0)
        screens[0].becomeHomeScreen()
        activeIndex = max(0, activeIndex - 1)
        if let secondaryIndex {
            self.secondaryIndex = screens.count <= 1 ? nil : max(0, secondaryIndex - 1)
        }
        bindScreens()
        return true
    }

    public func syncHomeScreenSettings(_ settings: CalculatorScreenSettings) {
        homeScreen.replaceSettings(settings)
    }

    private func bindScreens() {
        screenObservers.removeAll()

        for screen in screens {
            screen.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &screenObservers)
        }
    }
}