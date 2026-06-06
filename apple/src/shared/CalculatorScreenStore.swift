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
    public var usesAlternativeKeypad: Bool
    public var usesEnterKeySymbol: Bool
    public var disablesSwipeDownToRound: Bool
    public var disablesButtonSound: Bool
    public var keypadHeightMultiplier: Double

    public init(
        themeRawValue: String,
        languageCode: String,
        usesScientificNotation: Bool,
        numberFormatStyleRawValue: String,
        usesAlternativeKeypad: Bool,
        usesEnterKeySymbol: Bool = true,
        disablesSwipeDownToRound: Bool = false,
        disablesButtonSound: Bool = false,
        keypadHeightMultiplier: Double = 1.0
    ) {
        self.themeRawValue = themeRawValue
        self.languageCode = languageCode
        self.usesScientificNotation = usesScientificNotation
        self.numberFormatStyleRawValue = numberFormatStyleRawValue
        self.usesAlternativeKeypad = usesAlternativeKeypad
        self.usesEnterKeySymbol = usesEnterKeySymbol
        self.disablesSwipeDownToRound = disablesSwipeDownToRound
        self.disablesButtonSound = disablesButtonSound
        self.keypadHeightMultiplier = keypadHeightMultiplier
    }

    public var numberFormatStyle: NumberFormatStyle {
        NumberFormatStyle(rawValue: numberFormatStyleRawValue) ?? NumberFormatStyle.detected()
    }
}

// One live calculator "screen": pairs a view model with its settings and
// re-publishes the view model's changes so SwiftUI observes a single object.
public final class CalculatorScreenSession: ObservableObject, Identifiable {
    public let id: UUID
    public let isHomeScreen: Bool
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
        guard screens.count < Self.maxScreenCount else { return false }
        let clampedIndex = min(max(index, 0), max(screens.count - 1, 0))
        let insertIndex = min(clampedIndex + 1, screens.count)
        let newScreen = CalculatorScreenSession(settings: homeSettings)
        screens.insert(newScreen, at: insertIndex)
        activeIndex = insertIndex
        bindScreens()
        return true
    }

    @discardableResult
    public func closeActiveScreen() -> Bool {
        guard activeIndex > 0 else { return false }
        screens.remove(at: activeIndex)
        activeIndex = min(activeIndex - 1, screens.count - 1)
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