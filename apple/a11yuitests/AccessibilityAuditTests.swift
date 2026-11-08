import XCTest

/// A light accessibility check (#145): every control on the main screens has
/// a name VoiceOver can read, and nothing is hidden from it. Contrast and
/// Dynamic Type are left to the VoiceOver test script: the keys behind an open
/// pane are dimmed on purpose, and the keypad keeps its size by design.
/// Run with the EnterCalc-iOSAccessibility scheme.
final class AccessibilityAuditTests: XCTestCase {
    private let checks: XCUIAccessibilityAuditType = [.sufficientElementDescription, .elementDetection]
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        QuiescenceBypass.install()
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10), "The calculator did not appear")
    }

    func testCalculator() throws {
        try app.performAccessibilityAudit(for: checks)
    }

    func testSettings() throws {
        app.buttons["Settings"].tap()
        sleep(1)
        try app.performAccessibilityAudit(for: checks)
    }

    func testVATPane() throws {
        app.buttons["Toggle currency"].tap()
        app.buttons["1"].tap()
        app.buttons["2"].tap()
        app.buttons["VAT"].tap()
        sleep(1)
        try app.performAccessibilityAudit(for: checks)
    }
}

/// EnterCalc animates continuously (the display shimmer), so the app never
/// goes idle and XCUITest would wait for it before every tap.
enum QuiescenceBypass {
    private static var installed = false

    static func install() {
        guard !installed, let processClass = NSClassFromString("XCUIApplicationProcess") else { return }
        installed = true
        let skip: @convention(block) (AnyObject) -> Bool = { _ in true }
        for name in ["shouldSkipPreEventQuiescence", "shouldSkipPostEventQuiescence"] {
            if let method = class_getInstanceMethod(processClass, NSSelectorFromString(name)) {
                method_setImplementation(method, imp_implementationWithBlock(skip))
            }
        }
    }
}
