import Foundation

/// Decides when the app may ask for an App Store review.
///
/// The system already rate-limits the prompt and may show nothing at all, so
/// this is not about enforcing that limit. It is about only spending a prompt on
/// someone who has actually got value out of the app: iOS will show a given user
/// very few prompts ever, and asking a first-run user or asking twice for the
/// same release wastes one.
///
/// The gate is *distinct days used* rather than launches or a raw calculation
/// count. A calculator can rack up either in a single sitting, which shows
/// activity but not that anyone came back. Returning on separate days does.
///
/// The Settings rating link is deliberately not governed by this — a control the
/// user chose to press should always work.
public enum ReviewPromptPolicy {
    /// Separate days the app has been used. Coming back is the actual signal.
    public static let minimumDistinctDaysUsed = 3

    /// Guards against someone who opened the app briefly on three days without
    /// really using it.
    public static let minimumCompletedCalculations = 25

    public static func shouldRequestReview(
        completedCalculations: Int,
        distinctDaysUsed: Int,
        lastPromptedVersion: String?,
        currentVersion: String
    ) -> Bool {
        guard completedCalculations >= minimumCompletedCalculations,
              distinctDaysUsed >= minimumDistinctDaysUsed else {
            return false
        }

        // One prompt per release at most. A user who ignored the ask on this
        // version should not see it again until there is something new.
        return lastPromptedVersion != currentVersion
    }
}

/// Turns each calculator page's running count of completed calculations into
/// one total across pages and launches, for `ReviewPromptPolicy`.
///
/// A page's count lives in memory and starts at zero, so only the growth since
/// it was last seen is added. The total is what gets stored.
public struct CompletedCalculationTally {
    public private(set) var total: Int
    private var lastSeen: [UUID: Int] = [:]

    public init(total: Int = 0) {
        self.total = max(total, 0)
    }

    /// Records a page's current count, adding what it gained since last time.
    public mutating func record(count: Int, forPage page: UUID) {
        let previous = lastSeen[page] ?? 0
        if count > previous {
            total += count - previous
        }
        lastSeen[page] = count
    }
}
