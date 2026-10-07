import XCTest
import SwiftUI
@testable import EnterCalcCore

/// Changeable keys and their chooser (#131). These run on macOS, so they cover
/// the Mac sizes and the Mac placement (below the key).
final class FunctionKeyEditingTests: XCTestCase {
    // MARK: Dog-ear

    func testEarSizesMatchTheChosenDesign() {
        // 10pt on a 55pt keypad key and 5pt on an 18pt action-row key: the
        // Mac's `ear15` sizes from the design canvas.
        XCTAssertEqual(FunctionKeyEar.size(forKeyHeight: 55, isActionRow: false), 10)
        XCTAssertEqual(FunctionKeyEar.size(forKeyHeight: 18, isActionRow: true), 5)
    }

    func testEarSizeStaysWithinItsBoundsAsKeysResize() {
        XCTAssertEqual(FunctionKeyEar.size(forKeyHeight: 20, isActionRow: false), 8)
        XCTAssertEqual(FunctionKeyEar.size(forKeyHeight: 400, isActionRow: false), 14)
        XCTAssertEqual(FunctionKeyEar.size(forKeyHeight: 4, isActionRow: true), 4)
        XCTAssertEqual(FunctionKeyEar.size(forKeyHeight: 100, isActionRow: true), 8)
    }

    func testKeyShapeCutsOffOnlyTheTopRightCorner() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 55)
        let path = FunctionKeyShape(cornerRadius: 6, ear: 10).path(in: rect)

        XCTAssertFalse(path.contains(CGPoint(x: 78, y: 2)), "inside the cut corner")
        XCTAssertTrue(path.contains(CGPoint(x: 72, y: 12)), "just inside the cut")
        XCTAssertTrue(path.contains(CGPoint(x: 40, y: 2)), "the rest of the top edge")
        XCTAssertTrue(path.contains(CGPoint(x: 78, y: 50)), "the other corners keep their rounding")
    }

    func testNoEarIsThePlainRoundedKey() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 55)
        let plain = RoundedRectangle(cornerRadius: 6, style: .continuous).path(in: rect)
        XCTAssertEqual(FunctionKeyShape(cornerRadius: 6, ear: 0).path(in: rect), plain)
        XCTAssertTrue(FunctionKeyEarFlap(cornerRadius: 6, ear: 0).path(in: rect).isEmpty)
    }

    func testFlapLiesUnderTheCutWithARoundedTip() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 55)
        let flap = FunctionKeyEarFlap(cornerRadius: 6, ear: 10).path(in: rect)

        XCTAssertTrue(flap.contains(CGPoint(x: 74, y: 7)), "below the fold line")
        XCTAssertFalse(flap.contains(CGPoint(x: 78, y: 2)), "above the fold line is cut away")
        XCTAssertFalse(flap.contains(CGPoint(x: 70.5, y: 9.5)), "the right-angle tip is rounded off")
    }

    // MARK: Chooser placement

    private let panel = CGSize(width: 238, height: 120)
    private let window = CGRect(x: 0, y: 0, width: 280, height: 484)

    func testChooserOpensBelowTheKeyOnTheMac() {
        let key = CGRect(x: 75, y: 246, width: 63, height: 42)
        let origin = CalculatorFunctionKeyChooser.panelOrigin(anchor: key, panelSize: panel, container: window)
        XCTAssertGreaterThanOrEqual(origin.y, key.maxY, "the key being edited stays in view")
        // Clear of the window's edges, not running edge to edge.
        XCTAssertGreaterThanOrEqual(origin.x, 16)
        XCTAssertLessThanOrEqual(origin.x + panel.width, window.maxX - 16)
    }

    func testChooserFlipsAboveWhenThereIsNoRoomBelow() {
        let key = CGRect(x: 75, y: 400, width: 63, height: 42)
        let origin = CalculatorFunctionKeyChooser.panelOrigin(anchor: key, panelSize: panel, container: window)
        XCTAssertLessThanOrEqual(origin.y + panel.height, key.minY)
    }

    func testChooserStaysInsideTheWindowWhenNeitherSideFits() {
        let tiny = CGRect(x: 0, y: 0, width: 280, height: 200)
        let key = CGRect(x: 75, y: 80, width: 63, height: 42)
        let origin = CalculatorFunctionKeyChooser.panelOrigin(anchor: key, panelSize: panel, container: tiny)
        XCTAssertGreaterThanOrEqual(origin.y, 16)
        XCTAssertLessThanOrEqual(origin.y + panel.height, tiny.maxY - 16 + 0.5)
    }
}
