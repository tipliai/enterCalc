import XCTest
import SwiftUI
@testable import EnterCalcCore

final class TextSizePreferenceTests: XCTestCase {
    func testDefaultsToFollowingTheSystem() {
        XCTAssertEqual(TextSizePreference(storedValue: ""), .system)
        XCTAssertEqual(TextSizePreference(storedValue: "somethingNewer"), .system)
        XCTAssertTrue(TextSizePreference.system.followsSystem)
        XCTAssertNil(TextSizePreference.system.dynamicTypeSize)
        XCTAssertNil(TextSizePreference.system.relativeScale)
        XCTAssertNil(TextSizePreference.system.sizeIndex)
    }

    func testStoredValuesRoundTrip() {
        for preference in TextSizePreference.allCases {
            XCTAssertEqual(TextSizePreference(storedValue: preference.rawValue), preference)
        }
    }

    func testFiveSizesSmallestFirstWithDefaultInTheMiddle() {
        XCTAssertEqual(TextSizePreference.sizes.count, 5)
        XCTAssertEqual(TextSizePreference.sizes[2], .standard)
        XCTAssertEqual(TextSizePreference.standard.relativeScale, 1)
        XCTAssertEqual(TextSizePreference.standard.dynamicTypeSize, .large)

        let scales = TextSizePreference.sizes.compactMap(\.relativeScale)
        XCTAssertEqual(scales, scales.sorted())
        XCTAssertEqual(Set(scales).count, scales.count)

        let dynamicTypeSizes = TextSizePreference.sizes.compactMap(\.dynamicTypeSize)
        XCTAssertEqual(dynamicTypeSizes, dynamicTypeSizes.sorted())
    }

    func testSliderIndexMapsToSizesAndClamps() {
        for (index, size) in TextSizePreference.sizes.enumerated() {
            XCTAssertEqual(TextSizePreference.size(atIndex: index), size)
            XCTAssertEqual(size.sizeIndex, index)
        }
        XCTAssertEqual(TextSizePreference.size(atIndex: -3), .extraSmall)
        XCTAssertEqual(TextSizePreference.size(atIndex: 99), .extraLarge)
    }

    func testEveryLabelIsTranslated() {
        let keys = ["settings.textSize"] + TextSizePreference.allCases.map(\.localizationKey)
        for language in ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"] {
            guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                XCTFail("Missing \(language).lproj")
                continue
            }
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "__missing__", table: nil)
                XCTAssertNotEqual(value, "__missing__", "\(key) missing in \(language)")
            }
        }
    }
}
