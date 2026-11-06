import XCTest
@testable import EnterCalcCore

/// Keyboard navigation helpers (#164).
final class KeyboardNavigationTests: XCTestCase {
    // Space on a pop-up menu reached with Tab steps to its next option and
    // wraps round, so every option is reachable from the keyboard.
    func testSpaceStepsToTheNextOptionAndWraps() {
        let options = ["a", "b", "c"]
        XCTAssertEqual(nextOption(after: "a", in: options), "b")
        XCTAssertEqual(nextOption(after: "c", in: options), "a")
        XCTAssertEqual(nextOption(after: "z", in: options), "a", "An unknown value starts from the first option")
        XCTAssertEqual(nextOption(after: CalculatorMode.basic, in: CalculatorMode.allCases), .currency)
        XCTAssertEqual(nextOption(after: CalculatorMode.currency, in: CalculatorMode.allCases), .basic)
    }
}
