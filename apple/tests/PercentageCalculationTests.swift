import XCTest
@testable import EnterCalcCore

final class PercentageCalculationTests: XCTestCase {
    // MARK: - Percentage mode

    // The example from #25: `100 + 10%` shows `10` as the amount and `110` as
    // the result. The calculator could already reach 110; the amount is what
    // percentage mode adds.
    func testAddingAPercentageExposesBothTheAmountAndTheResult() {
        let breakdown = PercentageBreakdown(base: 100, rate: 10, direction: .add)

        XCTAssertEqual(breakdown.amount, 10)
        XCTAssertEqual(breakdown.result, 110)
    }

    func testSubtractingAPercentage() {
        let breakdown = PercentageBreakdown(base: 100, rate: 10, direction: .subtract)

        XCTAssertEqual(breakdown.amount, 10)
        XCTAssertEqual(breakdown.result, 90)
    }

    // The amount reads as "the 10 in 100 + 10%", so it does not flip sign with
    // the direction. Otherwise subtracting would show "-10" where the user
    // expects to see the size of the discount.
    func testAmountDoesNotFlipSignWithDirection() {
        XCTAssertEqual(PercentageBreakdown(base: 250, rate: 20, direction: .add).amount, 50)
        XCTAssertEqual(PercentageBreakdown(base: 250, rate: 20, direction: .subtract).amount, 50)
    }

    // It does follow the sign of the base, though: 20% of −50 is −10, and the
    // result still reconciles.
    func testAmountFollowsTheSignOfTheBase() {
        let breakdown = PercentageBreakdown(base: -50, rate: 20, direction: .add)

        XCTAssertEqual(breakdown.amount, -10)
        XCTAssertEqual(breakdown.result, -60)
    }

    // Whatever is shown must add up, or the two numbers on screen contradict
    // each other.
    func testAmountAndResultAlwaysReconcile() {
        for base in [Decimal(0), 1, 19.99, 100, 12345.67, -50] {
            for rate in [Decimal(0), 5, 7.5, 20, 100, 175] {
                for direction in [PercentageBreakdown.Direction.add, .subtract] {
                    let breakdown = PercentageBreakdown(base: base, rate: rate, direction: direction)
                    let expected = direction == .add
                        ? breakdown.base + breakdown.amount
                        : breakdown.base - breakdown.amount

                    XCTAssertEqual(
                        breakdown.result,
                        expected,
                        "base \(base) rate \(rate) \(direction)"
                    )
                }
            }
        }
    }

    func testZeroRateLeavesTheBaseAlone() {
        let breakdown = PercentageBreakdown(base: 42, rate: 0, direction: .add)

        XCTAssertEqual(breakdown.amount, 0)
        XCTAssertEqual(breakdown.result, 42)
    }

    // Rates above 100 are ordinary — a 175% markup is a real thing.
    func testRateAboveOneHundred() {
        let breakdown = PercentageBreakdown(base: 100, rate: 175, direction: .add)

        XCTAssertEqual(breakdown.amount, 175)
        XCTAssertEqual(breakdown.result, 275)
    }

    // Decimal arithmetic, not binary floating point, so a price like 19.99
    // gives an exact answer rather than 21.988999999999997.
    func testDecimalPricesStayExact() {
        let breakdown = PercentageBreakdown(base: Decimal(string: "19.99")!, rate: 10, direction: .add)

        XCTAssertEqual(breakdown.amount, Decimal(string: "1.999"))
        XCTAssertEqual(breakdown.result, Decimal(string: "21.989"))
    }

    // MARK: - VAT, forward

    func testAddingVAT() {
        let breakdown = try? XCTUnwrap(VATCalculation.adding(rate: 20, toNet: 100))

        XCTAssertEqual(breakdown?.net, 100)
        XCTAssertEqual(breakdown?.vat, 20)
        XCTAssertEqual(breakdown?.gross, 120)
        XCTAssertEqual(breakdown?.rate, 20)
    }

    // MARK: - Reverse VAT

    // The case spelled out in #25: enter 120 including 20% VAT and get 120 inc,
    // 100 ex, 20 VAT.
    func testRemovingVATFromAGrossPrice() throws {
        let breakdown = try XCTUnwrap(VATCalculation.removing(rate: 20, fromGross: 120))

        XCTAssertEqual(breakdown.gross, 120)
        XCTAssertEqual(breakdown.net, 100)
        XCTAssertEqual(breakdown.vat, 20)
    }

    func testRemovingVATAtEachPresetRate() throws {
        // net 200 at each preset, then backed out again.
        for rate in VATCalculation.presetRates {
            let forward = try XCTUnwrap(VATCalculation.adding(rate: rate, toNet: 200))
            let reverse = try XCTUnwrap(VATCalculation.removing(rate: rate, fromGross: forward.gross))

            XCTAssertEqual(reverse.net, 200, "rate \(rate)")
            XCTAssertEqual(reverse.vat, forward.vat, "rate \(rate)")
        }
    }

    // Reverse VAT is a division, so the net rarely lands on a round number.
    // The parts still have to add back up to the price that was typed in —
    // that is the property an accountant checks.
    func testPartsAlwaysAddBackUpToTheGross() throws {
        for gross in [Decimal(0), 1, Decimal(string: "0.01")!, 100, Decimal(string: "19.99")!, 12345, Decimal(string: "999999.99")!] {
            for rate in [Decimal(0), 5, Decimal(string: "7.5")!, 20, 25, 100] {
                let breakdown = try XCTUnwrap(VATCalculation.removing(rate: rate, fromGross: gross))

                XCTAssertEqual(
                    breakdown.net + breakdown.vat,
                    breakdown.gross,
                    "gross \(gross) rate \(rate)"
                )
            }
        }
    }

    func testForwardPartsAlwaysAddUp() throws {
        for net in [Decimal(0), 1, Decimal(string: "19.99")!, 100, Decimal(string: "8.33")!] {
            for rate in [Decimal(0), 5, Decimal(string: "7.5")!, 20, 25] {
                let breakdown = try XCTUnwrap(VATCalculation.adding(rate: rate, toNet: net))

                XCTAssertEqual(
                    breakdown.net + breakdown.vat,
                    breakdown.gross,
                    "net \(net) rate \(rate)"
                )
            }
        }
    }

    // A gross price that does not divide evenly is the normal case, so it is
    // worth pinning one exactly: 100 including 20% VAT is 83.33… net.
    func testUnevenReverseVATKeepsFullPrecision() throws {
        let breakdown = try XCTUnwrap(VATCalculation.removing(rate: 20, fromGross: 100))

        XCTAssertEqual(breakdown.net + breakdown.vat, 100)
        XCTAssertTrue(breakdown.net > Decimal(string: "83.33")!, "got \(breakdown.net)")
        XCTAssertTrue(breakdown.net < Decimal(string: "83.34")!, "got \(breakdown.net)")
    }

    func testZeroRateIsANoOpInBothDirections() throws {
        let forward = try XCTUnwrap(VATCalculation.adding(rate: 0, toNet: 75))
        XCTAssertEqual(forward.vat, 0)
        XCTAssertEqual(forward.gross, 75)

        let reverse = try XCTUnwrap(VATCalculation.removing(rate: 0, fromGross: 75))
        XCTAssertEqual(reverse.vat, 0)
        XCTAssertEqual(reverse.net, 75)
    }

    func testZeroPrice() throws {
        let reverse = try XCTUnwrap(VATCalculation.removing(rate: 20, fromGross: 0))

        XCTAssertEqual(reverse.net, 0)
        XCTAssertEqual(reverse.vat, 0)
    }

    // MARK: - Rate validation

    // −100% would divide by zero on the way back out; below that the price
    // flips sign. Neither is a rate, so both are refused rather than returning
    // a nonsense breakdown.
    func testRatesAtOrBelowMinusOneHundredAreRejected() {
        XCTAssertNil(VATCalculation.removing(rate: -100, fromGross: 120))
        XCTAssertNil(VATCalculation.adding(rate: -100, toNet: 120))
        XCTAssertNil(VATCalculation.removing(rate: -150, fromGross: 120))
        XCTAssertFalse(VATCalculation.isValidRate(-100))
        XCTAssertFalse(VATCalculation.isValidRate(-100.01))
    }

    // A negative rate above −100 is a discount rather than a tax, and the maths
    // is well defined, so it is allowed.
    func testSmallNegativeRatesAreAllowed() throws {
        XCTAssertTrue(VATCalculation.isValidRate(-20))
        let breakdown = try XCTUnwrap(VATCalculation.adding(rate: -20, toNet: 100))

        XCTAssertEqual(breakdown.vat, -20)
        XCTAssertEqual(breakdown.gross, 80)
    }

    func testPresetRatesAreTheOnesTheIssueNames() {
        XCTAssertEqual(VATCalculation.presetRates, [5, 10, 15, 20, 25])
    }

    // MARK: - Agreement with the calculator engine

    // Percentage mode must not disagree with what typing the same thing on the
    // keypad already produces.
    func testBreakdownMatchesTheEngineForAddition() {
        let viewModel = CalculatorViewModel()
        enter("100", into: viewModel)
        viewModel.setOperator(.add)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "110")
        XCTAssertEqual(PercentageBreakdown(base: 100, rate: 10, direction: .add).result, 110)
    }

    func testBreakdownMatchesTheEngineForSubtraction() {
        let viewModel = CalculatorViewModel()
        enter("100", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "90")
        XCTAssertEqual(PercentageBreakdown(base: 100, rate: 10, direction: .subtract).result, 90)
    }

    // Reverse VAT has to agree with doing the division by hand on the keypad.
    func testReverseVATMatchesTheEquivalentDivision() throws {
        let viewModel = CalculatorViewModel()
        enter("120", into: viewModel)
        viewModel.setOperator(.divide)
        enter("1.2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "100")
        XCTAssertEqual(try XCTUnwrap(VATCalculation.removing(rate: 20, fromGross: 120)).net, 100)
    }

    private func enter(_ digits: String, into viewModel: CalculatorViewModel) {
        for character in digits {
            if character == "." {
                viewModel.inputDecimal()
            } else {
                viewModel.inputDigit(String(character))
            }
        }
    }
}
