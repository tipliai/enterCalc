import Foundation
import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Bundled Inter typeface wrapper. Fonts are registered with CoreText once on
// first use; each accessor falls back to the rounded system font (via a cascade
// list) so glyphs missing from Inter still render.
public enum EnterCalcFont {
    // Only the weights actually rendered are bundled and registered: SemiBold
    // for primary text and Thin for accent glyphs.
    private static let interSemiBoldName = "Inter-SemiBold"
    private static let interThinName = "Inter-Thin"
    private static let fontResourceExtension = "ttf"
    private static let fontResourceSubdirectory = "Fonts"
    private static let registrationLock = NSLock()
    private static var didAttemptRegistration = false

    public static var subheadline: Font { appFont(size: 15) }

    public static func thinAppFont(size: CGFloat) -> Font {
        registerIfNeeded()

        #if canImport(UIKit)
        return Font(platformThinFont(size: size))
        #elseif canImport(AppKit)
        return Font(platformThinFont(size: size))
        #else
        return .system(size: size, weight: .regular, design: .rounded)
        #endif
    }

    public static func registerIfNeeded(bundle: Bundle = .enterCalcCore) {
        registrationLock.lock()
        defer { registrationLock.unlock() }

        guard !didAttemptRegistration else { return }
        didAttemptRegistration = true

        for fontResourceName in [interSemiBoldName, interThinName] {
            guard let fontURL = bundle.url(
                forResource: fontResourceName,
                withExtension: fontResourceExtension,
                subdirectory: fontResourceSubdirectory
            ) else {
                continue
            }

            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    public static func appFont(size: CGFloat) -> Font {
        registerIfNeeded()

        #if canImport(UIKit)
        return Font(platformFont(size: size))
        #elseif canImport(AppKit)
        return Font(platformFont(size: size))
        #else
        return .system(size: size, weight: .semibold, design: .rounded)
        #endif
    }

    #if canImport(UIKit)
    public static func platformFont(size: CGFloat) -> UIFont {
        registerIfNeeded()

        guard let baseFont = UIFont(name: interSemiBoldName, size: size) else {
            return roundedSystemFont(size: size, weight: .semibold)
        }

        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: [roundedSystemFont(size: size, weight: .semibold).fontDescriptor]
        ])

        return UIFont(descriptor: descriptor, size: size)
    }

    public static func platformThinFont(size: CGFloat) -> UIFont {
        registerIfNeeded()

        guard let baseFont = UIFont(name: interThinName, size: size) else {
            return roundedSystemFont(size: size, weight: .regular)
        }

        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: [roundedSystemFont(size: size, weight: .regular).fontDescriptor]
        ])

        return UIFont(descriptor: descriptor, size: size)
    }

    private static func roundedSystemFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = systemFont.fontDescriptor.withDesign(.rounded) ?? systemFont.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }
    #elseif canImport(AppKit)
    public static func platformFont(size: CGFloat) -> NSFont {
        registerIfNeeded()

        guard let baseFont = NSFont(name: interSemiBoldName, size: size) else {
            return roundedSystemFont(size: size, weight: .semibold)
        }

        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: [roundedSystemFont(size: size, weight: .semibold).fontDescriptor]
        ])

        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    public static func platformThinFont(size: CGFloat) -> NSFont {
        registerIfNeeded()

        guard let baseFont = NSFont(name: interThinName, size: size) else {
            return roundedSystemFont(size: size, weight: .regular)
        }

        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: [roundedSystemFont(size: size, weight: .regular).fontDescriptor]
        ])

        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    private static func roundedSystemFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = systemFont.fontDescriptor.withDesign(.rounded) ?? systemFont.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? systemFont
    }
    #endif
}