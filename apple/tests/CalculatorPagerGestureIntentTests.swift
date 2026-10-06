import SwiftUI
import XCTest
@testable import EnterCalcCore

final class CalculatorPagerGestureIntentTests: XCTestCase {
    // The complaint behind #83: a finger that slides slightly while pressing a
    // key used to start paging. Anything at tap scale must not qualify.
    func testSmallDriftWhilePressingAKeyIsNotPaging() {
        for drift in [CGSize(width: 4, height: 2), CGSize(width: 9, height: 3), CGSize(width: 14, height: 1)] {
            XCTAssertFalse(
                CalculatorPagerGestureIntent.isPagingIntent(translation: drift, axis: .horizontal),
                "\(drift) should not page"
            )
        }
    }

    // There is a deliberate dead band. A keypad key cancels its own tap once
    // the finger travels 8pt horizontally, while paging does not engage until
    // 18pt — so a slide of 8–18pt does nothing at all. That is the intended
    // outcome for #83: a slip of that size is not a clear press *or* a clear
    // swipe, and turning the page on it is the behaviour being fixed. Verified
    // on the iPad simulator: a 12pt drift starting on a digit entered nothing
    // and changed no page, while a 400pt swipe paged normally.
    func testPagingThresholdSitsAboveTheKeypadTapCancellation() {
        let keypadTapCancellationDistance: CGFloat = 8

        XCTAssertGreaterThan(
            CalculatorPagerGestureIntent.minimumAxisTravel,
            keypadTapCancellationDistance,
            "paging must not engage while the keypad would still have accepted the tap"
        )
    }

    // A real swipe still has to work; making it more deliberate must not make
    // it hard.
    func testAnOrdinarySwipeIsPaging() {
        for swipe in [CGSize(width: 40, height: 5), CGSize(width: -60, height: 10), CGSize(width: 120, height: -20)] {
            XCTAssertTrue(
                CalculatorPagerGestureIntent.isPagingIntent(translation: swipe, axis: .horizontal),
                "\(swipe) should page"
            )
        }
    }

    // A diagonal smudge off a key is not a page swipe, however far it goes.
    func testDiagonalDragIsNotPaging() {
        XCTAssertFalse(CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: 40, height: 35), axis: .horizontal))
        XCTAssertFalse(CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: 60, height: 50), axis: .horizontal))
    }

    // Just past the dominance ratio it does count, so the rule is a threshold
    // rather than a blanket refusal of anything diagonal.
    func testClearlyHorizontalDragIsPagingEvenWithSomeVerticalTravel() {
        XCTAssertTrue(CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: 60, height: 20), axis: .horizontal))
    }

    func testDirectionDoesNotMatter() {
        let left = CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: -50, height: 4), axis: .horizontal)
        let right = CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: 50, height: 4), axis: .horizontal)

        XCTAssertTrue(left)
        XCTAssertEqual(left, right)
    }

    // The vertical pager (used for the phone's page layout) applies the same
    // rule with the axes swapped.
    func testVerticalAxisUsesTheSameRuleTransposed() {
        XCTAssertTrue(CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: 5, height: 40), axis: .vertical))
        XCTAssertFalse(CalculatorPagerGestureIntent.isPagingIntent(translation: CGSize(width: 40, height: 5), axis: .vertical))
    }

    // The gesture cannot even begin below `minimumDragDistance`, so a smaller
    // axis threshold would be unreachable and misleading to read.
    func testAxisThresholdIsReachableGivenTheMinimumDragDistance() {
        XCTAssertLessThanOrEqual(
            CalculatorPagerGestureIntent.minimumAxisTravel,
            CalculatorPagerGestureIntent.minimumDragDistance
        )
    }
}
