import XCTest
@testable import EnterCalcCore

// The second half of a display with two calculators side by side, the iPhone
// Duo's inner display in book position (#168): both halves page through the
// same screens, so adding and closing screens must keep both cursors on the
// screens they were showing.
final class CalculatorScreenStoreTests: XCTestCase {
    private let settings = CalculatorScreenSettings(
        themeRawValue: "system",
        languageCode: "en",
        usesScientificNotation: true,
        numberFormatStyleRawValue: NumberFormatStyle.detected().rawValue
    )

    private func makeStore() -> CalculatorScreenStore {
        CalculatorScreenStore(homeSettings: settings)
    }

    func testSecondaryScreenOpensAfterTheActiveOneAndLeavesItInPlace() {
        let store = makeStore()
        XCTAssertNil(store.secondaryIndex)

        XCTAssertTrue(store.insertSecondaryScreenAfterActive(homeSettings: settings))

        XCTAssertEqual(store.screenCount, 2)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertEqual(store.secondaryIndex, 1)
        XCTAssertTrue(store.secondaryScreen === store.screens[1])
    }

    func testTheSecondHalfOpensOnAnExistingScreen() {
        let store = makeStore()
        store.insertScreenAfterActive(homeSettings: settings)
        XCTAssertNil(store.secondaryIndex)

        XCTAssertTrue(store.showSecondaryScreen(at: 0))
        XCTAssertEqual(store.secondaryIndex, 0)
        XCTAssertEqual(store.screenCount, 2)

        XCTAssertFalse(store.showSecondaryScreen(at: 5))
    }

    // A swipe past the last page on the second half opens a new screen
    // there; the main half keeps its screen, renumbered when the new one
    // lands before it.
    func testInsertingAfterTheSecondaryScreenKeepsTheMainHalfOnItsScreen() {
        let store = makeStore()
        store.insertScreenAfterActive(homeSettings: settings)
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        store.activateSecondaryScreen(at: 0)
        let mainScreen = store.activeScreen
        XCTAssertEqual(store.activeIndex, 1)

        XCTAssertTrue(store.insertSecondaryScreen(after: 0, homeSettings: settings))

        XCTAssertEqual(store.screenCount, 4)
        XCTAssertEqual(store.secondaryIndex, 1)
        XCTAssertEqual(store.activeIndex, 2)
        XCTAssertTrue(store.activeScreen === mainScreen)
    }

    func testSecondaryScreenCannotBeChosenWhileTheHalfIsClosed() {
        let store = makeStore()
        store.insertScreenAfterActive(homeSettings: settings)

        XCTAssertFalse(store.activateSecondaryScreen(at: 0))
        XCTAssertNil(store.secondaryIndex)
    }

    func testBothHalvesMayShowTheSameScreen() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)

        XCTAssertTrue(store.activateScreen(at: 1))

        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.secondaryIndex, 1)
    }

    func testInsertingBeforeTheSecondaryScreenKeepsItOnItsScreen() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        let secondaryScreen = store.secondaryScreen

        // A screen inserted after the home screen lands in front of the
        // secondary one.
        store.insertScreenAfterActive(homeSettings: settings)

        XCTAssertEqual(store.screenCount, 3)
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.secondaryIndex, 2)
        XCTAssertTrue(store.secondaryScreen === secondaryScreen)
    }

    func testClosingAScreenBeforeTheSecondaryOneKeepsItOnItsScreen() {
        let store = makeStore()
        store.insertScreenAfterActive(homeSettings: settings)
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        let secondaryScreen = store.secondaryScreen

        XCTAssertTrue(store.closeScreen(at: 1))

        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertEqual(store.secondaryIndex, 1)
        XCTAssertTrue(store.secondaryScreen === secondaryScreen)
    }

    func testClosingTheLastSecondaryScreenMovesThatHalfToTheOneBefore() {
        let store = makeStore()
        store.insertScreenAfterActive(homeSettings: settings)
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        XCTAssertEqual(store.secondaryIndex, 2)

        XCTAssertTrue(store.closeScreen(at: 2))

        XCTAssertEqual(store.screenCount, 2)
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.secondaryIndex, 1)
    }

    // Closing from the second half goes on to the next screen, not back to
    // the home screen, so each close from there removes another screen.
    func testClosingASecondaryScreenWithOthersAfterItMovesThatHalfToTheNext() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        XCTAssertEqual(store.screenCount, 4)
        XCTAssertEqual(store.secondaryIndex, 1)
        let next = store.screens[2]

        XCTAssertTrue(store.closeScreen(at: 1))

        XCTAssertEqual(store.screenCount, 3)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertEqual(store.secondaryIndex, 1)
        XCTAssertTrue(store.secondaryScreen === next)

        XCTAssertTrue(store.closeScreen(at: 1))
        XCTAssertEqual(store.secondaryIndex, 1)
        XCTAssertTrue(store.closeScreen(at: 1))
        XCTAssertEqual(store.screenCount, 1)
        XCTAssertNil(store.secondaryIndex)
    }

    func testTheSecondHalfClosesOnceOneScreenIsLeft() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)

        XCTAssertTrue(store.closeScreen(at: 1))

        XCTAssertEqual(store.screenCount, 1)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertNil(store.secondaryIndex)
    }

    func testTheHomeScreenNeverClosesAsAnOrdinaryScreen() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)

        XCTAssertFalse(store.closeScreen(at: 0))

        XCTAssertEqual(store.screenCount, 2)
        XCTAssertEqual(store.secondaryIndex, 1)
    }

    // The second half may close the home screen too: the next screen takes
    // its place, keeping its own settings, and each half moves with its
    // screen, so closing from the second half goes through every screen.
    func testClosingTheHomeScreenMakesTheNextScreenTheHomeScreen() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        store.activateScreen(at: 2)
        store.activateSecondaryScreen(at: 0)
        let next = store.screens[1]
        var german = settings
        german.languageCode = "de"
        next.replaceSettings(german)

        XCTAssertTrue(store.closeHomeScreenPromotingNext())

        XCTAssertEqual(store.screenCount, 2)
        XCTAssertTrue(store.homeScreen === next)
        XCTAssertTrue(next.isHomeScreen)
        XCTAssertEqual(next.settings.languageCode, "de")
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.secondaryIndex, 0)

        XCTAssertTrue(store.closeHomeScreenPromotingNext())
        XCTAssertEqual(store.screenCount, 1)
        XCTAssertTrue(store.homeScreen.isHomeScreen)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertNil(store.secondaryIndex)

        XCTAssertFalse(store.closeHomeScreenPromotingNext())
    }

    func testClosingTheSecondHalfKeepsItsScreenInThePages() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)

        store.closeSecondary()

        XCTAssertNil(store.secondaryIndex)
        XCTAssertEqual(store.screenCount, 2)
    }

    func testClosingTheActiveScreenWhileBothHalvesShowItMovesEachHalfItsOwnWay() {
        let store = makeStore()
        store.insertSecondaryScreenAfterActive(homeSettings: settings)
        store.insertScreenAfterActive(homeSettings: settings)
        store.activateSecondaryScreen(at: 1)
        XCTAssertEqual(store.activeIndex, 1)

        XCTAssertTrue(store.closeActiveScreen())

        XCTAssertEqual(store.screenCount, 2)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertEqual(store.secondaryIndex, 1)
    }
}
