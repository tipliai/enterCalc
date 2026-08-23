import Foundation

/// Where the app sends people who want to tell us something.
///
/// This is deliberately the support page rather than the App Store review
/// sheet. Someone opening a "Feedback" row usually has a bug or a request, and
/// pointing that at a review form turns support requests into one-star reviews.
/// Reviews are asked for separately, at a moment the user is not complaining.
public enum SupportLinks {
    /// Public support page, which also links on to GitHub issues.
    public static var supportURL: URL {
        // Force-unwrap is safe: a compile-time constant, covered by a test that
        // would fail if it were ever edited into something malformed.
        URL(string: "https://tipliai.github.io/enterCalc/support/")!
    }
}
