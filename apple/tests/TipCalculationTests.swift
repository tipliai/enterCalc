import XCTest
@testable import EnterCalcCore

final class TipCalculationTests: XCTestCase {
    // The acceptance criterion from #92: a bill, a tip percentage and a split
    // count produce the tip, the total and the per-person amount together.
    func testBillRateAndSplitProduceAllThreeOutputs() {
        let breakdown = TipBreakdown(bill: 100, rate: 20, splitCount: 4)

        XCTAssertEqual(breakdown.tip, 20)
        XCTAssertEqual(breakdown.total, 120)
        XCTAssertEqual(breakdown.perPerson, 30)
    }

    // "Default split count of 1 behaves as no-split."
    func testDefaultSplitIsNoSplit() {
        let breakdown = TipBreakdown(bill: 80, rate: 15)

        XCTAssertEqual(breakdown.splitCount, 1)
        XCTAssertEqual(breakdown.tip, 12)
        XCTAssertEqual(breakdown.total, 92)
        XCTAssertEqual(breakdown.perPerson, breakdown.total)
    }

    func testEachPresetRate() {
        let expected: [Decimal: Decimal] = [10: 5, 15: 7.5, 18: 9, 20: 10]

        for rate in TipBreakdown.presetRates {
            let breakdown = TipBreakdown(bill: 50, rate: rate)
            XCTAssertEqual(breakdown.tip, expected[rate], "rate \(rate)")
            XCTAssertEqual(breakdown.total, 50 + (expected[rate] ?? 0), "rate \(rate)")
        }
    }

    func testPresetRatesAreTheOnesTheIssueNames() {
        XCTAssertEqual(TipBreakdown.presetRates, [10, 15, 18, 20])
    }

    // The three outputs are shown side by side, so they have to reconcile or
    // they contradict each other on screen.
    func testOutputsAlwaysReconcile() {
        for bill in [Decimal(0), 1, Decimal(string: "23.45")!, 100, Decimal(string: "1999.99")!] {
            for rate in [Decimal(0), 10, 15, 18, 20, Decimal(string: "12.5")!] {
                for split in [1, 2, 3, 4, 7] {
                    let breakdown = TipBreakdown(bill: bill, rate: rate, splitCount: split)

                    XCTAssertEqual(breakdown.total, breakdown.bill + breakdown.tip, "\(bill)/\(rate)/\(split)")

                    // The share is an exact quotient, so scaling it back only
                    // returns the total to within Decimal's precision — a
                    // third of something never multiplies back cleanly. What
                    // must not happen is a share wrong by an amount anyone
                    // could notice.
                    var residual = breakdown.perPerson * Decimal(breakdown.splitCount) - breakdown.total
                    if residual < 0 { residual.negate() }
                    XCTAssertLessThan(
                        residual,
                        Decimal(string: "0.0000000001")!,
                        "per-person does not scale back to the total: \(bill)/\(rate)/\(split)"
                    )
                }
            }
        }
    }

    func testZeroTipLeavesTheBillAlone() {
        let breakdown = TipBreakdown(bill: 42, rate: 0)

        XCTAssertEqual(breakdown.tip, 0)
        XCTAssertEqual(breakdown.total, 42)
    }

    func testZeroBill() {
        let breakdown = TipBreakdown(bill: 0, rate: 20, splitCount: 3)

        XCTAssertEqual(breakdown.tip, 0)
        XCTAssertEqual(breakdown.total, 0)
        XCTAssertEqual(breakdown.perPerson, 0)
    }

    // Splitting a bill zero or negative ways is not something a user means, so
    // the count clamps rather than dividing by zero or inverting the share.
    func testSplitCountIsClamped() {
        XCTAssertEqual(TipBreakdown(bill: 100, rate: 10, splitCount: 0).splitCount, 1)
        XCTAssertEqual(TipBreakdown(bill: 100, rate: 10, splitCount: -5).splitCount, 1)
        XCTAssertEqual(TipBreakdown(bill: 100, rate: 10, splitCount: 500).splitCount, 99)
    }

    func testClampedSplitStillProducesAUsableShare() {
        let breakdown = TipBreakdown(bill: 100, rate: 0, splitCount: 0)

        XCTAssertEqual(breakdown.perPerson, 100)
    }

    // Decimal arithmetic, so a real restaurant bill does not pick up binary
    // floating-point residue.
    func testAwkwardBillStaysExact() {
        let breakdown = TipBreakdown(bill: Decimal(string: "23.45")!, rate: 18)

        XCTAssertEqual(breakdown.tip, Decimal(string: "4.2210"))
        XCTAssertEqual(breakdown.total, Decimal(string: "27.6710"))
    }

    // Where the split divides evenly the share does scale back exactly, so the
    // approximate check above is not hiding a sloppy result.
    func testEvenSplitScalesBackExactly() {
        let breakdown = TipBreakdown(bill: 100, rate: 20, splitCount: 4)

        XCTAssertEqual(breakdown.perPerson, 30)
        XCTAssertEqual(breakdown.perPerson * 4, breakdown.total)
    }

    // An uneven split keeps the exact quotient, the way the calculator shows
    // `10 ÷ 3` in full rather than rounding it. Anything that rounds these for
    // display has to allocate the leftover penny itself.
    func testUnevenSplitKeepsTheExactQuotient() {
        let breakdown = TipBreakdown(bill: 100, rate: 10, splitCount: 3)

        XCTAssertEqual(breakdown.total, 110)
        XCTAssertEqual(breakdown.perPerson, Decimal(110) / Decimal(3))
        XCTAssertTrue(breakdown.perPerson > Decimal(string: "36.6666")!, "got \(breakdown.perPerson)")
        XCTAssertTrue(breakdown.perPerson < Decimal(string: "36.6667")!, "got \(breakdown.perPerson)")
    }

    // A custom rate outside the presets is explicitly supported.
    func testCustomRate() {
        let breakdown = TipBreakdown(bill: 200, rate: Decimal(string: "12.5")!, splitCount: 2)

        XCTAssertEqual(breakdown.tip, 25)
        XCTAssertEqual(breakdown.total, 225)
        XCTAssertEqual(breakdown.perPerson, Decimal(string: "112.5"))
    }
}
