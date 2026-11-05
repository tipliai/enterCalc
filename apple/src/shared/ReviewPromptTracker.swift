import Foundation

/// Tracks the usage the review prompt is gated on, and remembers when and for
/// which release the app last asked. Shared by the iOS and Mac apps.
///
/// Days are stored as a rolling set of day stamps rather than a counter so that
/// repeated use on one day counts once, which is the whole point of the gate.
/// Everything stays in `UserDefaults` on the device; nothing is sent anywhere.
@MainActor
public final class ReviewPromptTracker {
    public static let shared = ReviewPromptTracker()

    /// Launch argument that opens the gate in Debug builds, for QA. StoreKit
    /// shows the prompt every time in a Debug build, but never in TestFlight,
    /// so this is the only way to see it on demand.
    public static let forcePromptLaunchArgument = "-EnterCalcForceReviewPrompt"

    static let daysUsedKey = "review.daysUsed"
    static let lastPromptedVersionKey = "review.lastPromptedVersion"
    static let lastPromptedDateKey = "review.lastPromptedDate"
    static let completedCalculationsKey = "review.completedCalculations"
    static let currentVersionDaysKey = "review.currentVersionDays"
    static let currentVersionDaysVersionKey = "review.currentVersionDaysVersion"
    static let usesKey = "review.uses"
    static let lastLeftDateKey = "review.lastLeftDate"

    private let defaults: UserDefaults
    private let currentVersion: String
    private let forcesPrompt: Bool
    private var tally: CompletedCalculationTally
    /// Whether the current visit has already been counted. Kept in memory, so
    /// a cold launch always starts a new visit.
    private var isInUse = false

    public convenience init() {
        self.init(
            defaults: .standard,
            currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            forcesPrompt: Self.launchArgumentForcesPrompt
        )
    }

    init(defaults: UserDefaults, currentVersion: String, forcesPrompt: Bool = false, now: Date = Date()) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.forcesPrompt = forcesPrompt
        tally = CompletedCalculationTally(total: defaults.integer(forKey: Self.completedCalculationsKey))

        // 1.1.0 stored only the version it asked on, not when. Without a date
        // the spacing rule would let someone who was just asked on 1.1.0 be
        // asked again on the first days of 1.2.0, so count from now instead.
        if defaults.string(forKey: Self.lastPromptedVersionKey) != nil,
           defaults.object(forKey: Self.lastPromptedDateKey) == nil {
            defaults.set(now, forKey: Self.lastPromptedDateKey)
        }
    }

    private static var launchArgumentForcesPrompt: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains(forcePromptLaunchArgument)
#else
        false
#endif
    }

    /// Adds what a page has completed since it was last seen to the stored
    /// total, so calculations count across pages and relaunches. Returns
    /// whether anything was added, which is how callers tell that the key just
    /// pressed finished a calculation, the only moment worth asking.
    @discardableResult
    public func recordCompletedCalculations(_ count: Int, forPage page: UUID) -> Bool {
        let before = tally.total
        tally.record(count: count, forPage: page)
        guard tally.total != before else {
            return false
        }
        defaults.set(tally.total, forKey: Self.completedCalculationsKey)
        return true
    }

    /// Records that the app was opened or brought back to the front, and today
    /// as a day used. It is one more use when this is a cold launch, or when
    /// the app was left at least `minutesBetweenUses` ago; time spent in the
    /// app never counts as time away. Safe to call on every activation.
    public func recordUse(now: Date = Date(), calendar: Calendar = .current) {
        if !isInUse {
            isInUse = true
            let lastLeft = defaults.object(forKey: Self.lastLeftDateKey) as? Date
            let gap = ReviewPromptPolicy.minutesBetweenUses * 60
            // A launch with no recorded departure (first run, or the app was
            // ended while in front) counts; so does a clock moved back.
            if lastLeft.map({ now.timeIntervalSince($0) >= gap || now < $0 }) ?? true {
                defaults.set(defaults.integer(forKey: Self.usesKey) + 1, forKey: Self.usesKey)
            }
        }

        let today = Self.dayStamp(for: now, calendar: calendar)

        var days = defaults.stringArray(forKey: Self.daysUsedKey) ?? []
        if !days.contains(today) {
            days.append(today)
            // Only the count matters, so keep this from growing without bound.
            defaults.set(Array(days.suffix(30)), forKey: Self.daysUsedKey)
        }

        // Days on this version start again from nothing after an update.
        var versionDays = defaults.string(forKey: Self.currentVersionDaysVersionKey) == currentVersion
            ? defaults.stringArray(forKey: Self.currentVersionDaysKey) ?? []
            : []
        if !versionDays.contains(today) {
            versionDays.append(today)
            defaults.set(Array(versionDays.suffix(30)), forKey: Self.currentVersionDaysKey)
            defaults.set(currentVersion, forKey: Self.currentVersionDaysVersionKey)
        }
    }

    /// Records that the app went to the background (iOS) or stopped being the
    /// active app (macOS). The next use is measured from here.
    public func recordLeaving(now: Date = Date()) {
        isInUse = false
        defaults.set(now, forKey: Self.lastLeftDateKey)
    }

    public var uses: Int {
        defaults.integer(forKey: Self.usesKey)
    }

    public var distinctDaysUsed: Int {
        defaults.stringArray(forKey: Self.daysUsedKey)?.count ?? 0
    }

    public var distinctDaysOnCurrentVersion: Int {
        guard defaults.string(forKey: Self.currentVersionDaysVersionKey) == currentVersion else {
            return 0
        }
        return defaults.stringArray(forKey: Self.currentVersionDaysKey)?.count ?? 0
    }

    public func shouldRequestReview(lastResultWasError: Bool, now: Date = Date()) -> Bool {
        if forcesPrompt {
            return !lastResultWasError
        }

        return ReviewPromptPolicy.shouldRequestReview(
            completedCalculations: tally.total,
            uses: uses,
            distinctDaysUsed: distinctDaysUsed,
            distinctDaysOnCurrentVersion: distinctDaysOnCurrentVersion,
            lastPromptedVersion: defaults.string(forKey: Self.lastPromptedVersionKey),
            lastPromptedDate: defaults.object(forKey: Self.lastPromptedDateKey) as? Date,
            currentVersion: currentVersion,
            lastResultWasError: lastResultWasError,
            now: now
        )
    }

    /// Called once the prompt has been asked for, so this release does not ask
    /// again and the next one waits out the spacing. Recorded even though the
    /// system may choose not to show anything — the ask is spent either way.
    public func recordPromptShown(now: Date = Date()) {
        defaults.set(currentVersion, forKey: Self.lastPromptedVersionKey)
        defaults.set(now, forKey: Self.lastPromptedDateKey)
    }

    private static func dayStamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

/// Waits out `ReviewPromptPolicy.idleSecondsBeforeAsking` after a finished
/// calculation before the prompt is shown, so it never interrupts a run of sums.
///
/// There is one wait for the whole app: a calculation finished anywhere, in any
/// page or window, starts it again from the beginning.
@MainActor
public final class ReviewPromptIdleWait {
    public static let shared = ReviewPromptIdleWait()

    private var pending: DispatchWorkItem?
    /// What the calculator showed when the running wait started.
    private var startedFrom: ReviewPromptIdleSnapshot?

    public init() {}

    /// Starts the wait, replacing any wait already running. When it ends,
    /// `ask` runs only if `isStillIdle` says nothing has happened since; the
    /// platform also re-checks there that no sheet or pane has opened.
    public func start(
        after delay: TimeInterval = ReviewPromptPolicy.idleSecondsBeforeAsking,
        from snapshot: ReviewPromptIdleSnapshot? = nil,
        isStillIdle: @escaping @MainActor () -> Bool,
        ask: @escaping @MainActor () -> Void
    ) {
        pending?.cancel()
        startedFrom = snapshot
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = nil
                self?.startedFrom = nil
                guard isStillIdle() else { return }
                ask()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
        startedFrom = nil
    }

    /// Ends the wait if the calculator no longer shows what it did when the
    /// wait started. Change notifications can repeat for one key press, and
    /// those must not end a wait that the same press started.
    public func cancel(ifChangedFrom snapshot: ReviewPromptIdleSnapshot) {
        guard pending != nil, startedFrom != snapshot else { return }
        cancel()
    }

    public var isWaiting: Bool {
        pending != nil
    }
}

/// What the calculator shows, for telling whether anyone has touched it since a
/// calculation finished. Any key press changes at least one of these.
public struct ReviewPromptIdleSnapshot: Equatable {
    let completedCalculations: Int
    let display: String
    let expression: String
    let expressionDisplay: String
    let editCursor: Int?
    let isErrorState: Bool
}

extension CalculatorViewModel {
    public var reviewPromptIdleSnapshot: ReviewPromptIdleSnapshot {
        ReviewPromptIdleSnapshot(
            completedCalculations: completedCalculationCount,
            display: display,
            expression: expression,
            expressionDisplay: expressionDisplay,
            editCursor: displayEditCursorIndex,
            isErrorState: isErrorState
        )
    }
}
