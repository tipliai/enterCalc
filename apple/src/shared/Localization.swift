// Sources/Localization.swift
import Foundation

// Shared localization helpers with runtime override.
public var languageOverrideBundle: Bundle? = nil
public let defaultLocalizationSelectionCode = "default"

public func isDefaultLocalizationSelection(_ code: String?) -> Bool {
    code?.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(defaultLocalizationSelectionCode) == .orderedSame
}

public func supportedLocalizationCodes(in bundle: Bundle = .enterCalcCore) -> [String] {
    bundle.localizations.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }
}

public func resolvedLocalizationCode(
    for requestedCode: String? = nil,
    in bundle: Bundle = .enterCalcCore,
    preferredLanguages: [String] = Locale.preferredLanguages
) -> String {
    let supportedCodes = supportedLocalizationCodes(in: bundle)
    let fallbackCode = supportedCodes.contains("en") ? "en" : (supportedCodes.first ?? "en")

    func canonicalSupportedCode(for match: String) -> String {
        supportedCodes.first {
            $0.caseInsensitiveCompare(match) == .orderedSame
        } ?? match
    }

    let normalizedRequest = requestedCode?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let explicitRequest = isDefaultLocalizationSelection(normalizedRequest) ? nil : normalizedRequest

    let preferences: [String]
    if let explicitRequest, !explicitRequest.isEmpty {
        preferences = [explicitRequest]
    } else {
        preferences = preferredLanguages
    }

    if let preferredMatch = Bundle.preferredLocalizations(from: supportedCodes, forPreferences: preferences).first {
        return canonicalSupportedCode(for: preferredMatch)
    }

     if let explicitRequest,
         let baseLanguageCode = Locale(identifier: explicitRequest).language.languageCode?.identifier,
       let languageMatch = Bundle.preferredLocalizations(from: supportedCodes, forPreferences: [baseLanguageCode]).first {
        return canonicalSupportedCode(for: languageMatch)
    }

    return fallbackCode
}

public func localizationBundle(for requestedCode: String?, in bundle: Bundle = .enterCalcCore) -> Bundle? {
    let resolvedCode = resolvedLocalizationCode(for: requestedCode, in: bundle)

    guard let path = bundle.path(forResource: resolvedCode, ofType: "lproj") else {
        return nil
    }

    return Bundle(path: path)
}

public func localizationDisplayName(for code: String, currentLocale: Locale = .current) -> String {
    let nativeLocale = Locale(identifier: code)

    return nativeLocale.localizedString(forIdentifier: code)
        ?? nativeLocale.localizedString(forLanguageCode: code)
        ?? currentLocale.localizedString(forIdentifier: code)
        ?? currentLocale.localizedString(forLanguageCode: code)
        ?? code
}

public func localized(_ key: String) -> String {
    if let bundle = languageOverrideBundle {
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if value != key { return value }
    }

    let moduleValue = Bundle.module.localizedString(forKey: key, value: nil, table: "Localizable")
    if moduleValue != key { return moduleValue }

    if let basePath = Bundle.module.path(forResource: "Base", ofType: "lproj"),
       let baseBundle = Bundle(path: basePath) {
        let baseValue = baseBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if baseValue != key { return baseValue }
    }

    return Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
}
