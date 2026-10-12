import Foundation

// Reads/writes CalculatorScreenSettings to UserDefaults, and clears out keys
// for settings that no longer exist.
public enum CalculatorScreenSettingsPersistence {
    private static let defaultThemeRawValue = "system"
    private static let defaultKeypadHeightMultiplier: Double = 1.0
    /// The alternative keypad and the settings it grew out of, removed in 1.2.0
    /// (#151). Its keys live on as configurable function keys, so a page that
    /// used it simply opens on the standard keypad.
    static let retiredKeys = [
        "settings.keypad.alternative",
        "settings.keypad.newDefault.v1",
        "settings.percent.classic"
    ]
    private static let currencySymbolKey = "settings.currency.symbol"
    private static let functionKeyAssignmentsKey = "settings.functionKeys.assignments"

    public static func load(from defaults: UserDefaults = .standard) -> CalculatorScreenSettings {
        removeRetiredKeys(from: defaults)

        let storedKeypadHeightMultiplier = defaults.object(forKey: "settings.keypadHeightMultiplier") as? Double ?? defaultKeypadHeightMultiplier
        return CalculatorScreenSettings(
            themeRawValue: defaults.string(forKey: "settings.theme") ?? defaultThemeRawValue,
            languageCode: storedLanguageCode(from: defaults),
            usesScientificNotation: defaults.object(forKey: "settings.numberFormat.scientific") as? Bool ?? true,
            numberFormatStyleRawValue: defaults.string(forKey: "settings.numberFormat.style") ?? NumberFormatStyle.detected().rawValue,
            disablesSwipeDownToRound: defaults.object(forKey: "settings.rounding.disableSwipeDown") as? Bool ?? false,
            disablesButtonSound: defaults.object(forKey: "settings.buttonSound.disabled") as? Bool ?? false,
            keypadHeightMultiplier: min(max(storedKeypadHeightMultiplier, 0.5), 1.0),
            currencySymbol: storedCurrencySymbol(from: defaults),
            functionKeyAssignments: storedFunctionKeyAssignments(from: defaults)
        )
    }

    public static func persist(_ settings: CalculatorScreenSettings, to defaults: UserDefaults = .standard) {
        defaults.set(settings.themeRawValue, forKey: "settings.theme")
        defaults.set(settings.languageCode, forKey: "settings.language")
        defaults.set(settings.usesScientificNotation, forKey: "settings.numberFormat.scientific")
        defaults.set(settings.numberFormatStyleRawValue, forKey: "settings.numberFormat.style")
        defaults.set(settings.disablesSwipeDownToRound, forKey: "settings.rounding.disableSwipeDown")
        defaults.set(settings.disablesButtonSound, forKey: "settings.buttonSound.disabled")
        defaults.set(settings.keypadHeightMultiplier, forKey: "settings.keypadHeightMultiplier")
        defaults.set(settings.currencySymbol, forKey: currencySymbolKey)
        defaults.set(settings.functionKeyAssignments.serialized, forKey: functionKeyAssignmentsKey)
    }

    /// Reads the configurable-key layout. Anything unparseable falls back to
    /// the defaults rather than leaving the keypad half-configured.
    public static func storedFunctionKeyAssignments(from defaults: UserDefaults = .standard) -> CalculatorFunctionKeyAssignments {
        CalculatorFunctionKeyAssignments(serialized: defaults.string(forKey: functionKeyAssignmentsKey))
    }

    /// Falls back to the region default until the user picks a symbol, so the
    /// currency key is useful on first launch without any setup. A stored value
    /// that is no longer offered also falls back rather than persisting a symbol
    /// the picker cannot display.
    public static func storedCurrencySymbol(from defaults: UserDefaults = .standard) -> String {
        guard let stored = defaults.string(forKey: currencySymbolKey),
              CurrencyCatalog.option(forSymbol: stored) != nil else {
            return CurrencyCatalog.detected().symbol
        }

        return stored
    }

    /// Clears stored values for settings that no longer exist. `load` does
    /// this; iOS, which reads its settings through `@AppStorage`, calls it at
    /// launch.
    public static func removeRetiredKeys(from defaults: UserDefaults = .standard) {
        for key in retiredKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }

    public static func storedLanguageCode(from defaults: UserDefaults = .standard) -> String {
        let storedLanguage = defaults.string(forKey: "settings.language")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedLanguage, !storedLanguage.isEmpty {
            return storedLanguage
        }

        return defaultLocalizationSelectionCode
    }
}
