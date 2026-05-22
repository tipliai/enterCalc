import Foundation

public enum CalculatorScreenSettingsPersistence {
    private static let defaultThemeRawValue = "system"
    private static let defaultKeypadHeightMultiplier: Double = 1.0

    public static func load(from defaults: UserDefaults = .standard) -> CalculatorScreenSettings {
        let storedKeypadHeightMultiplier = defaults.object(forKey: "settings.keypadHeightMultiplier") as? Double ?? defaultKeypadHeightMultiplier
        return CalculatorScreenSettings(
            themeRawValue: defaults.string(forKey: "settings.theme") ?? defaultThemeRawValue,
            languageCode: storedLanguageCode(from: defaults),
            usesScientificNotation: defaults.object(forKey: "settings.numberFormat.scientific") as? Bool ?? true,
            numberFormatStyleRawValue: defaults.string(forKey: "settings.numberFormat.style") ?? NumberFormatStyle.detected().rawValue,
            usesClassicPercentBehavior: defaults.object(forKey: "settings.percent.classic") as? Bool ?? false,
            usesEnterKeySymbol: defaults.object(forKey: "settings.equals.enterKeySymbol") as? Bool ?? true,
            disablesButtonSound: defaults.object(forKey: "settings.buttonSound.disabled") as? Bool ?? false,
            keypadHeightMultiplier: min(max(storedKeypadHeightMultiplier, 0.5), 1.0)
        )
    }

    public static func persist(_ settings: CalculatorScreenSettings, to defaults: UserDefaults = .standard) {
        defaults.set(settings.themeRawValue, forKey: "settings.theme")
        defaults.set(settings.languageCode, forKey: "settings.language")
        defaults.set(settings.usesScientificNotation, forKey: "settings.numberFormat.scientific")
        defaults.set(settings.numberFormatStyleRawValue, forKey: "settings.numberFormat.style")
        defaults.set(settings.usesClassicPercentBehavior, forKey: "settings.percent.classic")
        defaults.set(settings.usesEnterKeySymbol, forKey: "settings.equals.enterKeySymbol")
        defaults.set(settings.disablesButtonSound, forKey: "settings.buttonSound.disabled")
        defaults.set(settings.keypadHeightMultiplier, forKey: "settings.keypadHeightMultiplier")
    }

    public static func storedLanguageCode(from defaults: UserDefaults = .standard) -> String {
        let storedLanguage = defaults.string(forKey: "settings.language")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedLanguage, !storedLanguage.isEmpty {
            return storedLanguage
        }

        return defaultLocalizationSelectionCode
    }
}