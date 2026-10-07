import XCTest
@testable import EnterCalcCore

final class ReviewPromptPolicyTests: XCTestCase {
    private func shouldPrompt(
        calculations: Int = 100,
        days: Int = 10,
        lastPromptedVersion: String? = nil,
        currentVersion: String = "1.1.0"
    ) -> Bool {
        ReviewPromptPolicy.shouldRequestReview(
            completedCalculations: calculations,
            distinctDaysUsed: days,
            lastPromptedVersion: lastPromptedVersion,
            currentVersion: currentVersion
        )
    }

    func testPromptsOnceUsageIsEstablished() {
        XCTAssertTrue(shouldPrompt())
    }

    // Heavy use on a single day is activity, not evidence anyone came back, and
    // a calculator can reach any calculation count in one sitting.
    func testHeavyUseOnASingleDayDoesNotPrompt() {
        XCTAssertFalse(shouldPrompt(calculations: 500, days: 1))
    }

    // The mirror case: opening the app briefly on several days.
    func testReturningWithoutRealUseDoesNotPrompt() {
        XCTAssertFalse(shouldPrompt(calculations: 3, days: 7))
    }

    func testFirstRunNeverPrompts() {
        XCTAssertFalse(shouldPrompt(calculations: 0, days: 1))
    }

    // Someone who ignored the ask should not be asked again for the same build.
    func testDoesNotPromptTwiceForTheSameVersion() {
        XCTAssertFalse(shouldPrompt(lastPromptedVersion: "1.1.0", currentVersion: "1.1.0"))
    }

    func testPromptsAgainAfterAnUpgrade() {
        XCTAssertTrue(shouldPrompt(lastPromptedVersion: "1.0.0", currentVersion: "1.1.0"))
    }

    // Boundary: the thresholds are inclusive, so exactly meeting them qualifies.
    func testThresholdsAreInclusive() {
        XCTAssertTrue(
            shouldPrompt(
                calculations: ReviewPromptPolicy.minimumCompletedCalculations,
                days: ReviewPromptPolicy.minimumDistinctDaysUsed
            )
        )
        XCTAssertFalse(
            shouldPrompt(
                calculations: ReviewPromptPolicy.minimumCompletedCalculations - 1,
                days: ReviewPromptPolicy.minimumDistinctDaysUsed
            )
        )
        XCTAssertFalse(
            shouldPrompt(
                calculations: ReviewPromptPolicy.minimumCompletedCalculations,
                days: ReviewPromptPolicy.minimumDistinctDaysUsed - 1
            )
        )
    }
}

final class CompletedCalculationCountTests: XCTestCase {
    private func enter(_ digits: String, into viewModel: CalculatorViewModel) {
        for character in digits { viewModel.inputDigit(String(character)) }
    }

    func testCountsCalculationsThatReachAResult() {
        let viewModel = CalculatorViewModel()
        XCTAssertEqual(viewModel.completedCalculationCount, 0)

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.completedCalculationCount, 1)
    }

    // Typing is not calculating; only reaching a result counts.
    func testTypingWithoutEvaluatingDoesNotCount() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setOperator(.add)

        XCTAssertEqual(viewModel.completedCalculationCount, 0)
    }

    // The count records what the person did, so undoing a calculation does not
    // un-do the fact that they made it.
    func testUndoDoesNotDecrementTheCount() {
        let viewModel = CalculatorViewModel()
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.evaluate()

        viewModel.undo()

        XCTAssertEqual(viewModel.completedCalculationCount, 1)
    }

    func testClearingHistoryDoesNotResetTheCount() {
        let viewModel = CalculatorViewModel()
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.evaluate()

        viewModel.clearHistory()

        XCTAssertEqual(viewModel.completedCalculationCount, 1)
    }
}

final class CompletedCalculationTallyTests: XCTestCase {
    func testAddsEachPagesGrowthOnce() {
        let first = UUID(), second = UUID()
        var tally = CompletedCalculationTally()
        tally.record(count: 3, forPage: first)
        tally.record(count: 3, forPage: first)
        tally.record(count: 5, forPage: first)
        tally.record(count: 4, forPage: second)
        XCTAssertEqual(tally.total, 9)
    }

    // After a relaunch the stored total carries on, and the pages' in-memory
    // counts start again from zero.
    func testCarriesTheStoredTotalAcrossLaunches() {
        var tally = CompletedCalculationTally(total: 22)
        tally.record(count: 3, forPage: UUID())
        XCTAssertEqual(tally.total, ReviewPromptPolicy.minimumCompletedCalculations)
    }

    func testAPageCountGoingBackDoesNotSubtract() {
        let page = UUID()
        var tally = CompletedCalculationTally()
        tally.record(count: 4, forPage: page)
        tally.record(count: 1, forPage: page)
        tally.record(count: 2, forPage: page)
        XCTAssertEqual(tally.total, 5)
    }
}
