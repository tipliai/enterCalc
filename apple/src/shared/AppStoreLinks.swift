import Foundation

/// App Store destinations for EnterCalc.
///
/// A rating entry point the user taps deliberately links straight to the App
/// Store review sheet rather than going through `SKStoreReviewController`. That
/// API is for prompts the app raises on its own: the system rate-limits it and
/// may show nothing at all, which is the wrong behavior for a control the user
/// just pressed. Linking also keeps macOS and iOS on the same path.
public enum AppStoreLinks {
    /// EnterCalc's App Store identifier.
    public static let appID = "6777242723"

    /// The product page.
    public static var productURL: URL {
        // Force-unwrap is safe: the components are compile-time constants and
        // are covered by a test that would fail if the format ever changed.
        URL(string: "https://apps.apple.com/app/id\(appID)")!
    }

    /// The product page with the "Write a Review" sheet already open.
    public static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
    }
}
