import XCTest
@testable import EnterCalcCore

final class CalculatorScreenSettingsPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CalculatorScreenSettingsPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // #151: someone who used the alternative keypad in 1.1.0 upgrades to a
    // build without it. Their settings still load, the retired keys are
    // cleared, and everything else they set is kept.
    func testUpgradeFromAlternativeKeypadLoadsAndClearsRetiredKeys() {
        defaults.set(true, forKey: "settings.keypad.alternative")
        defaults.set(true, forKey: "settings.keypad.newDefault.v1")
        defaults.set(true, forKey: "settings.percent.classic")
        defaults.set("dark", forKey: "settings.theme")
        defaults.set(true, forKey: "settings.rounding.disableSwipeDown")

        let settings = CalculatorScreenSettingsPersistence.load(from: defaults)

        XCTAssertEqual(settings.themeRawValue, "dark")
        XCTAssertTrue(settings.disablesSwipeDownToRound)
        for key in CalculatorScreenSettingsPersistence.retiredKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be removed")
        }
    }

    func testPersistingDoesNotWriteRetiredKeys() {
        let settings = CalculatorScreenSettingsPersistence.load(from: defaults)
        CalculatorScreenSettingsPersistence.persist(settings, to: defaults)

        for key in CalculatorScreenSettingsPersistence.retiredKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should not be written")
        }
    }

    func testRoundTripKeepsSettings() {
        var settings = CalculatorScreenSettingsPersistence.load(from: defaults)
        settings.themeRawValue = "blue"
        settings.usesScientificNotation = false
        settings.disablesSwipeDownToRound = true
        settings.keypadHeightMultiplier = 0.75

        CalculatorScreenSettingsPersistence.persist(settings, to: defaults)
        let reloaded = CalculatorScreenSettingsPersistence.load(from: defaults)

        XCTAssertEqual(reloaded.themeRawValue, "blue")
        XCTAssertFalse(reloaded.usesScientificNotation)
        XCTAssertTrue(reloaded.disablesSwipeDownToRound)
        XCTAssertEqual(reloaded.keypadHeightMultiplier, 0.75)
    }

    func testRemovingRetiredKeysDirectlyLeavesOtherSettingsAlone() {
        defaults.set(true, forKey: "settings.keypad.alternative")
        defaults.set("dark", forKey: "settings.theme")

        CalculatorScreenSettingsPersistence.removeRetiredKeys(from: defaults)

        XCTAssertNil(defaults.object(forKey: "settings.keypad.alternative"))
        XCTAssertEqual(defaults.string(forKey: "settings.theme"), "dark")
    }
}
