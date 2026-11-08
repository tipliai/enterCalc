import XCTest

/// A light accessibility check (#145): every control on the main screens has
/// a name VoiceOver can read, and nothing is hidden from it. Contrast and
/// Dynamic Type are left to the VoiceOver test script: the keys behind an open
/// pane are dimmed on purpose, and the keypad keeps its size by design. The
/// Settings test draws no calculator behind the sheet; see testSettings.
/// Run with the EnterCalc-iOSAccessibility scheme.
final class AccessibilityAuditTests: XCTestCase {
    private let checks: XCUIAccessibilityAuditType = [.sufficientElementDescription, .elementDetection]
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        QuiescenceBypass.install()
        // The VAT pane is reached from the portrait mode row, which a phone in
        // landscape doesn't show; another test may have left the device turned.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10), "The calculator did not appear")
    }

    func testCalculator() throws {
        try app.performAccessibilityAudit(for: checks)
    }

    func testSettings() throws {
        // On iPad the centred Settings sheet can cut a dimmed key label in
        // half at its edge (the 11-inch and mini in portrait), and text
        // detection reports the visible half as unreachable text. The issue
        // carries no position, so it can't be told apart from a real one
        // inside the sheet; instead the app draws nothing behind the sheet
        // here, and every issue the sheet raises still fails the test.
        app.terminate()
        app.launchArguments.append("-AuditHidesCalculatorUnderSettingsSheet")
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10), "The calculator did not appear")
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

