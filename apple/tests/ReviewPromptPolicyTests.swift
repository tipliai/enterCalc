import XCTest
@testable import EnterCalcCore

final class ReviewPromptPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func shouldPrompt(
        calculations: Int = 100,
        uses: Int = 20,
        days: Int = 10,
        daysOnVersion: Int = 10,
        lastPromptedVersion: String? = nil,
        lastPromptedDaysAgo: Double? = nil,
        currentVersion: String = "1.2.0",
        lastResultWasError: Bool = false
    ) -> Bool {
        ReviewPromptPolicy.shouldRequestReview(
            completedCalculations: calculations,
            uses: uses,
            distinctDaysUsed: days,
            distinctDaysOnCurrentVersion: daysOnVersion,
            lastPromptedVersion: lastPromptedVersion,
            lastPromptedDate: lastPromptedDaysAgo.map { now.addingTimeInterval(-$0 * day) },
            currentVersion: currentVersion,
            lastResultWasError: lastResultWasError,
            now: now
        )
    }

    func testPromptsOnceUsageIsEstablished() {
        XCTAssertTrue(shouldPrompt())
    }

    // Heavy use on a single day is activity, not evidence anyone came back, and
    // a calculator can reach any calculation count in one sitting.
    func testHeavyUseOnASingleDayDoesNotPrompt() {
        XCTAssertFalse(shouldPrompt(calculations: 500, days: 1, daysOnVersion: 1))
    }

    // The mirror case: opening the app briefly on several days.
    func testReturningWithoutRealUseDoesNotPrompt() {
        XCTAssertFalse(shouldPrompt(calculations: 3, days: 7))
    }

    func testFirstRunNeverPrompts() {
        XCTAssertFalse(shouldPrompt(calculations: 0, uses: 1, days: 1, daysOnVersion: 1))
    }

    // Three days and plenty of sums are not enough until the app is a habit.
    func testWaitsForTenUses() {
        XCTAssertEqual(ReviewPromptPolicy.minimumUses, 10)
        XCTAssertFalse(shouldPrompt(uses: 9))
        XCTAssertTrue(shouldPrompt(uses: 10))
    }

    func testWaitsForTwelveCalculations() {
        XCTAssertEqual(ReviewPromptPolicy.minimumCompletedCalculations, 12)
        XCTAssertFalse(shouldPrompt(calculations: 11))
        XCTAssertTrue(shouldPrompt(calculations: 12))
    }

    // Someone who ignored the ask should not be asked again for the same build.
    func testDoesNotPromptTwiceForTheSameVersion() {
        XCTAssertFalse(shouldPrompt(lastPromptedVersion: "1.2.0", lastPromptedDaysAgo: 400))
    }

    func testPromptsAgainAfterAnUpgradeOnceTheSpacingHasPassed() {
        XCTAssertTrue(shouldPrompt(lastPromptedVersion: "1.1.0", lastPromptedDaysAgo: 121))
    }

    // Frequent releases must not each spend one of the system's few yearly asks.
    func testWaitsOutTheSpacingAcrossVersions() {
        let limit = Double(ReviewPromptPolicy.minimumDaysBetweenPrompts)
        XCTAssertFalse(shouldPrompt(lastPromptedVersion: "1.1.0", lastPromptedDaysAgo: 30))
        XCTAssertFalse(shouldPrompt(lastPromptedVersion: "1.1.0", lastPromptedDaysAgo: limit - 1))
        XCTAssertTrue(shouldPrompt(lastPromptedVersion: "1.1.0", lastPromptedDaysAgo: limit))
    }

    // A last-ask date in the future means the clock went back; keep waiting.
    func testALastAskInTheFutureDoesNotSkipTheSpacing() {
        XCTAssertFalse(shouldPrompt(lastPromptedVersion: "1.1.0", lastPromptedDaysAgo: -5))
    }

    func testNeverPromptsRightAfterAnError() {
        XCTAssertFalse(shouldPrompt(lastResultWasError: true))
    }

    // Someone who has just updated has not judged the new release yet.
    func testWaitsForASecondDayAfterAnUpdate() {
        XCTAssertFalse(shouldPrompt(daysOnVersion: 1))
        XCTAssertTrue(shouldPrompt(daysOnVersion: ReviewPromptPolicy.minimumDistinctDaysOnCurrentVersion))
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

@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        suiteName = "ReviewPromptTrackerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func date(day: Int) -> Date {
        start.addingTimeInterval(TimeInterval(day) * 24 * 60 * 60)
    }

    /// Opens the app on each of these days, and on the first of them enough
    /// times, an hour apart with the app left in between, to meet the uses
    /// threshold.
    private func use(_ tracker: ReviewPromptTracker, onDays days: ClosedRange<Int>) {
        for open in 0..<ReviewPromptPolicy.minimumUses {
            let opened = date(day: days.lowerBound).addingTimeInterval(TimeInterval(open) * 3600)
            tracker.recordUse(now: opened, calendar: calendar)
            tracker.recordLeaving(now: opened.addingTimeInterval(60))
        }
        for day in days.dropFirst() {
            tracker.recordUse(now: date(day: day), calendar: calendar)
            tracker.recordLeaving(now: date(day: day).addingTimeInterval(60))
        }
    }

    func testEarnsThePromptAfterRealUseOnSeparateDays() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        use(tracker, onDays: 0...2)
        XCTAssertTrue(tracker.recordCompletedCalculations(30, forPage: UUID()))
        XCTAssertTrue(tracker.shouldRequestReview(lastResultWasError: false, now: date(day: 2)))
    }

    // Coming back within half an hour of leaving is the same use; later it is
    // a new one. Time spent in the app does not count as time away.
    func testUsesAreMeasuredFromLeavingNotFromOpening() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        let start = date(day: 0)
        tracker.recordUse(now: start, calendar: calendar)
        XCTAssertEqual(tracker.uses, 1)

        // An hour in the app, a minute away, then back: still the same use.
        tracker.recordLeaving(now: start.addingTimeInterval(60 * 60))
        tracker.recordUse(now: start.addingTimeInterval(61 * 60), calendar: calendar)
        XCTAssertEqual(tracker.uses, 1)

        // Away for 40 minutes: a new use.
        tracker.recordLeaving(now: start.addingTimeInterval(70 * 60))
        tracker.recordUse(now: start.addingTimeInterval(110 * 60), calendar: calendar)
        XCTAssertEqual(tracker.uses, 2)
    }

    // Activation is reported more than once (appearing and becoming active);
    // without leaving in between it is one use.
    func testRepeatedActivationWithoutLeavingIsOneUse() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        tracker.recordUse(now: date(day: 0), calendar: calendar)
        tracker.recordUse(now: date(day: 0).addingTimeInterval(2 * 60 * 60), calendar: calendar)
        XCTAssertEqual(tracker.uses, 1)
    }

    // A cold launch with nothing stored is the first use.
    func testTheFirstLaunchIsAUse() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        tracker.recordUse(now: date(day: 0), calendar: calendar)
        XCTAssertEqual(tracker.uses, 1)
    }

    func testUsingTheAppTwiceInADayCountsOnce() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        tracker.recordUse(now: date(day: 0), calendar: calendar)
        tracker.recordLeaving(now: date(day: 0).addingTimeInterval(60))
        tracker.recordUse(now: date(day: 0).addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(tracker.distinctDaysUsed, 1)
        XCTAssertEqual(tracker.distinctDaysOnCurrentVersion, 1)
    }

    // Only a press that finished a calculation reports growth, so a digit key
    // pressed later never becomes the moment the prompt appears.
    func testReportsOnlyWhenACalculationWasAdded() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        let page = UUID()
        XCTAssertTrue(tracker.recordCompletedCalculations(1, forPage: page))
        XCTAssertFalse(tracker.recordCompletedCalculations(1, forPage: page))
        XCTAssertTrue(tracker.recordCompletedCalculations(2, forPage: page))
    }

    func testDaysOnTheVersionStartAgainAfterAnUpdate() {
        let old = ReviewPromptTracker(defaults: defaults, currentVersion: "1.1.0")
        use(old, onDays: 0...4)
        old.recordCompletedCalculations(50, forPage: UUID())

        let updated = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        updated.recordUse(now: date(day: 5), calendar: calendar)
        updated.recordLeaving(now: date(day: 5).addingTimeInterval(60))
        XCTAssertEqual(updated.distinctDaysUsed, 6)
        XCTAssertEqual(updated.distinctDaysOnCurrentVersion, 1)
        XCTAssertFalse(updated.shouldRequestReview(lastResultWasError: false, now: date(day: 5)))

        updated.recordUse(now: date(day: 6), calendar: calendar)
        XCTAssertTrue(updated.shouldRequestReview(lastResultWasError: false, now: date(day: 6)))
    }

    func testAskingSpendsTheVersionAndStartsTheSpacing() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0")
        use(tracker, onDays: 0...2)
        tracker.recordCompletedCalculations(30, forPage: UUID())
        tracker.recordPromptShown(now: date(day: 2))
        XCTAssertFalse(tracker.shouldRequestReview(lastResultWasError: false, now: date(day: 300)))

        let next = ReviewPromptTracker(defaults: defaults, currentVersion: "1.3.0")
        use(next, onDays: 10...11)
        XCTAssertFalse(next.shouldRequestReview(lastResultWasError: false, now: date(day: 11)))
        use(next, onDays: 122...123)
        XCTAssertTrue(next.shouldRequestReview(lastResultWasError: false, now: date(day: 123)))
    }

    // 1.1.0 recorded only the version it asked on. Without a date, someone asked
    // last week on 1.1.0 must not be asked again as soon as 1.2.0 arrives.
    func testAnAskFromBeforeDatesWereStoredStartsTheSpacingNow() {
        defaults.set("1.1.0", forKey: "review.lastPromptedVersion")
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0", now: date(day: 0))
        use(tracker, onDays: 0...5)
        tracker.recordCompletedCalculations(30, forPage: UUID())
        XCTAssertFalse(tracker.shouldRequestReview(lastResultWasError: false, now: date(day: 5)))
        XCTAssertTrue(tracker.shouldRequestReview(lastResultWasError: false, now: date(day: 120)))
    }

    func testTheQAOverrideOpensTheGateButNotAfterAnError() {
        let tracker = ReviewPromptTracker(defaults: defaults, currentVersion: "1.2.0", forcesPrompt: true)
        XCTAssertTrue(tracker.shouldRequestReview(lastResultWasError: false))
        XCTAssertFalse(tracker.shouldRequestReview(lastResultWasError: true))
    }
}

@MainActor
final class ReviewPromptIdleWaitTests: XCTestCase {
    private func runMainLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testAsksOnceTheWaitEndsUntouched() {
        let wait = ReviewPromptIdleWait()
        var asked = 0
        wait.start(after: 0.05, isStillIdle: { true }, ask: { asked += 1 })
        XCTAssertTrue(wait.isWaiting)
        XCTAssertEqual(asked, 0)
        runMainLoop(for: 0.2)
        XCTAssertEqual(asked, 1)
        XCTAssertFalse(wait.isWaiting)
    }

    // A run of sums: each finished calculation starts the wait again, so only
    // the pause after the last one can ask, and only once.
    func testAnotherCalculationStartsTheWaitAgain() {
        let wait = ReviewPromptIdleWait()
        var asked: [Int] = []
        wait.start(after: 0.05, isStillIdle: { true }, ask: { asked.append(1) })
        wait.start(after: 0.05, isStillIdle: { true }, ask: { asked.append(2) })
        runMainLoop(for: 0.2)
        XCTAssertEqual(asked, [2])
    }

    // Typing after the calculation (without finishing another) means the
    // person is busy, so the wait ends without asking.
    func testDoesNotAskIfTheCalculatorWasTouched() {
        let wait = ReviewPromptIdleWait()
        var asked = false
        wait.start(after: 0.05, isStillIdle: { false }, ask: { asked = true })
        runMainLoop(for: 0.2)
        XCTAssertFalse(asked)
    }

    func testTheSnapshotChangesWithAnyKeyPress() {
        let viewModel = CalculatorViewModel()
        viewModel.inputDigit("2")
        viewModel.setOperator(.add)
        viewModel.inputDigit("3")
        viewModel.evaluate()
        let finished = viewModel.reviewPromptIdleSnapshot
        XCTAssertEqual(viewModel.reviewPromptIdleSnapshot, finished)

        viewModel.inputDigit("7")
        XCTAssertNotEqual(viewModel.reviewPromptIdleSnapshot, finished)
    }

    func testWaitsTwentySecondsByDefault() {
        XCTAssertEqual(ReviewPromptPolicy.idleSecondsBeforeAsking, 20)
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
        XCTAssertEqual(tally.total, 25)
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
