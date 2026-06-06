import Foundation

// Reads/writes CalculatorScreenSettings to UserDefaults and runs one-time
// migrations for renamed legacy keys (classic-percent -> alternative keypad).
public enum CalculatorScreenSettingsPersistence {
    private static let defaultThemeRawValue = "system"
    private static let defaultKeypadHeightMultiplier: Double = 1.0
    private static let alternativeKeypadKey = "settings.keypad.alternative"
    private static let newDefaultKeypadMigrationKey = "settings.keypad.newDefault.v1"
    private static let legacyClassicPercentKey = "settings.percent.classic"

    public static func load(from defaults: UserDefaults = .standard) -> CalculatorScreenSettings {
        migrateLegacyKeypadPreferenceIfNeeded(in: defaults)
        migrateToNewDefaultKeypadIfNeeded(in: defaults)

        let storedKeypadHeightMultiplier = defaults.object(forKey: "settings.keypadHeightMultiplier") as? Double ?? defaultKeypadHeightMultiplier
        return CalculatorScreenSettings(
            themeRawValue: defaults.string(forKey: "settings.theme") ?? defaultThemeRawValue,
            languageCode: storedLanguageCode(from: defaults),
            usesScientificNotation: defaults.object(forKey: "settings.numberFormat.scientific") as? Bool ?? true,
            numberFormatStyleRawValue: defaults.string(forKey: "settings.numberFormat.style") ?? NumberFormatStyle.detected().rawValue,
            usesAlternativeKeypad: usesAlternativeKeypad(from: defaults),
            usesEnterKeySymbol: defaults.object(forKey: "settings.equals.enterKeySymbol") as? Bool ?? true,
            disablesSwipeDownToRound: defaults.object(forKey: "settings.rounding.disableSwipeDown") as? Bool ?? false,
            disablesButtonSound: defaults.object(forKey: "settings.buttonSound.disabled") as? Bool ?? false,
            keypadHeightMultiplier: min(max(storedKeypadHeightMultiplier, 0.5), 1.0)
        )
    }

    public static func persist(_ settings: CalculatorScreenSettings, to defaults: UserDefaults = .standard) {
        defaults.set(settings.themeRawValue, forKey: "settings.theme")
        defaults.set(settings.languageCode, forKey: "settings.language")
        defaults.set(settings.usesScientificNotation, forKey: "settings.numberFormat.scientific")
        defaults.set(settings.numberFormatStyleRawValue, forKey: "settings.numberFormat.style")
        defaults.set(settings.usesAlternativeKeypad, forKey: alternativeKeypadKey)
        defaults.removeObject(forKey: legacyClassicPercentKey)
        defaults.set(true, forKey: newDefaultKeypadMigrationKey)
        defaults.set(settings.usesEnterKeySymbol, forKey: "settings.equals.enterKeySymbol")
        defaults.set(settings.disablesSwipeDownToRound, forKey: "settings.rounding.disableSwipeDown")
        defaults.set(settings.disablesButtonSound, forKey: "settings.buttonSound.disabled")
        defaults.set(settings.keypadHeightMultiplier, forKey: "settings.keypadHeightMultiplier")
    }

    private static func usesAlternativeKeypad(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: alternativeKeypadKey) as? Bool ?? false
    }

    private static func migrateLegacyKeypadPreferenceIfNeeded(in defaults: UserDefaults) {
        guard defaults.object(forKey: legacyClassicPercentKey) != nil else { return }
        defaults.removeObject(forKey: legacyClassicPercentKey)
        defaults.set(false, forKey: alternativeKeypadKey)
    }

    private static func migrateToNewDefaultKeypadIfNeeded(in defaults: UserDefaults) {
        guard defaults.object(forKey: newDefaultKeypadMigrationKey) == nil else { return }
        defaults.set(false, forKey: alternativeKeypadKey)
        defaults.set(true, forKey: newDefaultKeypadMigrationKey)
    }

    public static func storedLanguageCode(from defaults: UserDefaults = .standard) -> String {
        let storedLanguage = defaults.string(forKey: "settings.language")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedLanguage, !storedLanguage.isEmpty {
            return storedLanguage
        }

        return defaultLocalizationSelectionCode
    }
}
