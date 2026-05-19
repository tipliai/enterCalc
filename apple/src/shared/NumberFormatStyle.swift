import Foundation

public enum NumberFormatStyle: String, CaseIterable {
    case western
    case european
    case french
    case indian
    case swiss

    public var example: String {
        switch self {
        case .western: return "1,234,567.89"
        case .european: return "1.234.567,89"
        case .french: return "1 234 567,89"
        case .indian: return "12,34,567.89"
        case .swiss: return "1'234'567.89"
        }
    }

    var decimalSeparator: String {
        switch self {
        case .western, .indian, .swiss: return "."
        case .european, .french: return ","
        }
    }

    var groupingSeparator: String {
        switch self {
        case .western, .indian: return ","
        case .european: return "."
        case .french: return " "
        case .swiss: return "'"
        }
    }

    var usesIndianGrouping: Bool {
        self == .indian
    }

    public static func detected(from locale: Locale = .current) -> NumberFormatStyle {
        let identifier = locale.identifier.lowercased()
        let grouping = locale.groupingSeparator ?? ","
        let decimal = locale.decimalSeparator ?? "."
        let isWhitespaceGrouping = grouping.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains)

        if identifier.contains("_in") || identifier.contains("-in") {
            return .indian
        }

        if identifier.contains("_ch") || identifier.contains("-ch") || grouping == "'" {
            return .swiss
        }

        if identifier.contains("_fr") || identifier.contains("-fr") || isWhitespaceGrouping {
            return .french
        }

        if decimal == "," && grouping == "." {
            return .european
        }

        return .western
    }
}