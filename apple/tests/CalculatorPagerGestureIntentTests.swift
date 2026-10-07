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

    // 1.1.0 QA still found swiping a little too eager, so a short, quick slide
    // of about a finger's width no longer counts either: the user has to drag
    // slightly further before the page starts to follow.
    func testAShortSlideOfAboutAFingerWidthIsNotPaging() {
        for drift in [CGSize(width: 20, height: 2), CGSize(width: -24, height: 3), CGSize(width: 26, height: 0)] {
            XCTAssertFalse(
                CalculatorPagerGestureIntent.isPagingIntent(translation: drift, axis: .horizontal),
                "\(drift) should not page"
            )
        }
    }

    // A key accepts a press that travels up to `keyTapAllowance`; the page
    // only engages beyond `minimumAxisTravel`. The first must stay below the
    // second, so one movement can never both enter a digit and turn the page.
    // Between them is a small band where neither happens. #83 originally had
    // the key give up after just 8pt, which dropped digits during fast typing
    // (#122); now a slide that small still enters the key.
    func testPagingThresholdSitsAboveTheKeypadTapAllowance() {
        XCTAssertLessThan(
            CalculatorPagerGestureIntent.keyTapAllowance,
            CalculatorPagerGestureIntent.minimumAxisTravel,
            "paging must not engage while the keypad would still have accepted the tap"
        )
    }

    // The slide a fast typist's finger makes as it lifts toward the next key
    // must stay a tap, not count as the start of a swipe (#122).
    func testAFastTypingSlideStaysWithinTheKeyTapAllowanceAndDoesNotPage() {
        for slide in [CGSize(width: 10, height: 2), CGSize(width: -15, height: 4), CGSize(width: 20, height: 3)] {
            XCTAssertLessThanOrEqual(hypot(slide.width, slide.height), CalculatorPagerGestureIntent.keyTapAllowance, "\(slide)")
            XCTAssertFalse(CalculatorPagerGestureIntent.isPagingIntent(translation: slide, axis: .horizontal), "\(slide) should not page")
        }
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
