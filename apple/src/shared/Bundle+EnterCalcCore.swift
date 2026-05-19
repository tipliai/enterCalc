import Foundation

public extension Bundle {
    /// Bundle accessor that can be used from outside the `EnterCalcCore` module.
    static let enterCalcCore: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()
}
