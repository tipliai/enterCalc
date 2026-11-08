import XCTest

/// The keyboard shortcuts no simulator panel can send (#172): Command + Left
/// and Right select the left or the right of two calculators side by side,
/// and Shift + Left and Right move between pages. Run with the
/// EnterCalc-iOSAccessibility scheme on an iPad simulator in landscape, where
/// the dual-mode button shows; on a narrower window the dual test is skipped.
final class DualCalculatorKeyboardTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        QuiescenceBypass.install()
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10), "The calculator did not appear")
        // The first key the harness sends after launch never arrives; Escape
        // clears the calculator, which is what the tests start from anyway.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        sleep(1)
    }

    func testCommandArrowsSelectTheHalves() throws {
        let dualMode = app.buttons["Two calculators"]
        try XCTSkipUnless(dualMode.waitForExistence(timeout: 3), "No room for two calculators here")
        dualMode.tap()
        // Opening the second calculator selects it: the toggle names the left.
        XCTAssertTrue(app.buttons["Left calculator"].waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: .command)
        XCTAssertTrue(app.buttons["Right calculator"].waitForExistence(timeout: 5), "Command + Right did not select the right calculator")

        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: .command)
        XCTAssertTrue(app.buttons["Left calculator"].waitForExistence(timeout: 5), "Command + Left did not select the left calculator")

        // Naming the half already selected changes nothing.
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: .command)
        XCTAssertTrue(app.buttons["Left calculator"].exists)
    }

    func testShiftArrowsMoveBetweenPages() throws {
        // Back to the first page, the home screen, whose rail button opens a
        // screen; any other page's closes one.
        for _ in 0..<5 {
            app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: .shift)
        }
        XCTAssertTrue(app.buttons["New Screen"].waitForExistence(timeout: 3))

        // Shift + Right shows the next page, or opens one past the last.
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: .shift)
        XCTAssertTrue(app.buttons["Close Screen"].waitForExistence(timeout: 3), "Shift + Right did not move to the page on the right")

        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: .shift)
        XCTAssertTrue(app.buttons["New Screen"].waitForExistence(timeout: 3), "Shift + Left did not move back to the home screen")
    }
}

