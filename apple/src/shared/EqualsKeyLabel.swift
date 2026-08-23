import Foundation

/// Chooses between the word "Enter" and the `=` symbol on the evaluate key.
///
/// This is derived rather than configured. "Enter" is an English word, and a
/// translated equivalent reads as prose on a key sized for a symbol, so every
/// other language uses `=`, which needs no translation. The alternative keypad
/// was laid out around the symbol, so it uses `=` regardless of language.
public enum EqualsKeyLabel {
    public static let symbol = "="

    public static func usesEnterWord(usesAlternativeKeypad: Bool, resolvedLocalizationCode: String) -> Bool {
        guard !usesAlternativeKeypad else { return false }
        return isEnglish(resolvedLocalizationCode)
    }

    /// Matches the language subtag so regional variants (`en-GB`, `en_AU`) are
    /// still English, without matching unrelated codes that merely start with
    /// those letters.
    private static func isEnglish(_ code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let languageSubtag = normalized
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init) ?? normalized

        return languageSubtag.caseInsensitiveCompare("en") == .orderedSame
    }
}
