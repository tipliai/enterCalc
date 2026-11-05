import Foundation

/// Decides when the app may ask for an App Store review.
///
/// The system already rate-limits the prompt and may show nothing at all, so
/// this is not about enforcing that limit. It is about only spending a prompt on
/// someone who has actually got value out of the app: the system will show a
/// given user very few prompts a year (three on iOS), and asking a first-run
/// user, asking twice for the same release, or asking on every frequent release
/// wastes them.
///
/// The gate is *distinct days used* rather than launches or a raw calculation
/// count. A calculator can rack up either in a single sitting, which shows
/// activity but not that anyone came back. Returning on separate days does.
///
/// Both apps use this, through `ReviewPromptTracker`. The platform code only
/// decides when it is safe to show the prompt (no sheet or pane open, the
/// window in front) and calls the system API. App Store guideline 5.6.1 rules
/// out a custom prompt, and asking "do you like EnterCalc?" first to send only
/// happy users on is not allowed either, so neither is ever done here.
///
/// The Settings rating link is deliberately not governed by this — a control the
/// user chose to press should always work.
public enum ReviewPromptPolicy {
    /// Separate days the app has been used. Coming back is the actual signal.
    public static let minimumDistinctDaysUsed = 3

    /// Guards against someone who opened the app briefly on three days without
    /// really using it.
    public static let minimumCompletedCalculations = 12

    /// Separate times the app has been opened. Days used can be met by three
    /// visits; this asks for a habit. Coming back within
    /// `minutesBetweenUses` is the same use, so switching apps mid-task does
    /// not count.
    public static let minimumUses = 10

    public static let minutesBetweenUses: Double = 30

    /// Separate days the current version has been used. Someone who has just
    /// updated has not yet had a chance to judge the new release, and asking on
    /// the first day of an update is asking about the update, not the app.
    public static let minimumDistinctDaysOnCurrentVersion = 2

    /// The shortest gap between two asks. With frequent releases, "once per
    /// version" alone would use up the system's yearly allowance in a few
    /// months, and the system would then silently drop the asks that matter.
    public static let minimumDaysBetweenPrompts = 120

    /// How long the iPhone and iPad calculator must sit untouched after a
    /// finished calculation before the prompt may appear. People often run
    /// several sums back to back, and the prompt should come up in the pause
    /// after them, not in the middle of the next one. The Mac asks straight
    /// away: its prompt is a sheet on the window, not a card over the keys.
    public static let idleSecondsBeforeAsking: TimeInterval = 20

    public static func shouldRequestReview(
        completedCalculations: Int,
        uses: Int,
        distinctDaysUsed: Int,
        distinctDaysOnCurrentVersion: Int,
        lastPromptedVersion: String?,
        lastPromptedDate: Date?,
        currentVersion: String,
        lastResultWasError: Bool,
        now: Date
    ) -> Bool {
        // Asking right after "Cannot divide by zero" lands the prompt on a
        // moment of friction.
        guard !lastResultWasError else {
            return false
        }

        guard completedCalculations >= minimumCompletedCalculations,
              uses >= minimumUses,
              distinctDaysUsed >= minimumDistinctDaysUsed,
              distinctDaysOnCurrentVersion >= minimumDistinctDaysOnCurrentVersion else {
            return false
        }

        // One prompt per release at most. A user who ignored the ask on this
        // version should not see it again until there is something new.
        guard lastPromptedVersion != currentVersion else {
            return false
        }

        if let lastPromptedDate {
            let spacing = TimeInterval(minimumDaysBetweenPrompts) * 24 * 60 * 60
            // A date in the future means the clock was moved back; that also
            // fails this check, so the wait is not skipped.
            guard now.timeIntervalSince(lastPromptedDate) >= spacing else {
                return false
            }
        }

        return true
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
