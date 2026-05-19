import Foundation
import SwiftUI
import EnterCalcCore

struct MacLocalizationBundleKey: EnvironmentKey {
    static let defaultValue: Bundle? = nil
}

extension EnvironmentValues {
    var macLocalizationBundle: Bundle? {
        get { self[MacLocalizationBundleKey.self] }
        set { self[MacLocalizationBundleKey.self] = newValue }
    }
}

func macLocalized(_ key: String, bundle: Bundle?) -> String {
    if let bundle {
        let value = bundle.localizedString(forKey: key, value: nil as String?, table: "Localizable")
        if value != key { return value }
    }

    let moduleValue = Bundle.enterCalcCore.localizedString(forKey: key, value: nil as String?, table: "Localizable")
    if moduleValue != key { return moduleValue }

    if let basePath = Bundle.enterCalcCore.path(forResource: "Base", ofType: "lproj"),
       let baseBundle = Bundle(path: basePath) {
        let baseValue = baseBundle.localizedString(forKey: key, value: nil as String?, table: "Localizable")
        if baseValue != key { return baseValue }
    }

    return Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
}