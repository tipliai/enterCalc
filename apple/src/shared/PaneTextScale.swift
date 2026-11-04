import SwiftUI

/// How the overlay panes (VAT, Tip, rounding, and any pane added later) follow
/// the Text Size setting (#152).
///
/// Each platform works out one scale from the setting, or from the system's
/// text size when Use System Text Size is on, and puts it in the environment
/// around its panes with `paneTextScale(_:)`. Pane text reads it through
/// `paneFont`, and controls that hold text read it to grow with it. A pane's
/// height comes from its content, so larger text makes the pane taller, and
/// `paneHeightLimit` makes an overly tall pane scroll instead of clipping.
public enum PaneTextScale {
    /// Extra Small, the smallest the setting goes.
    public static let minimum: CGFloat = 14.0 / 17.0
    /// Past this (the system's accessibility sizes) the panes keep their
    /// layout and scroll instead of growing further.
    public static let maximum: CGFloat = 2.0

    /// The scale for `preference`, or `systemScale` when following the system,
    /// kept within the panes' range.
    public static func resolved(_ preference: TextSizePreference, systemScale: CGFloat) -> CGFloat {
        let scale = preference.relativeScale ?? systemScale
        guard scale.isFinite, scale > 0 else { return 1 }
        return min(max(scale, minimum), maximum)
    }

    /// `base` scaled for pane text. Used for sizes tied to text, such as a
    /// marker drawn beside a label.
    public static func scaled(_ base: CGFloat, by scale: CGFloat) -> CGFloat {
        (base * scale).rounded(.toNearestOrAwayFromZero)
    }

    /// `base` scaled up with the text but never shrunk below it, for controls
    /// and tap targets that must stay at least their standard size.
    public static func grown(_ base: CGFloat, by scale: CGFloat) -> CGFloat {
        max(base, scaled(base, by: scale))
    }
}

private struct PaneTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

public extension EnvironmentValues {
    /// The overlay panes' text scale (#152); 1 at the standard text size.
    var paneTextScale: CGFloat {
        get { self[PaneTextScaleKey.self] }
        set { self[PaneTextScaleKey.self] = newValue }
    }
}

private struct PaneFontModifier: ViewModifier {
    @Environment(\.paneTextScale) private var scale
    let size: CGFloat
    let weight: Font.Weight?
    let usesAppFont: Bool

    func body(content: Content) -> some View {
        let scaledSize = PaneTextScale.scaled(size, by: scale)
        if usesAppFont {
            content.font(EnterCalcFont.appFont(size: scaledSize))
        } else {
            content.font(.system(size: scaledSize, weight: weight ?? .regular))
        }
    }
}

/// Caps a pane's height; content taller than the cap scrolls instead of being
/// clipped or squeezed.
private struct PaneHeightLimit: ViewModifier {
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        PaneHeightLayout(maxHeight: maxHeight) {
            ViewThatFits(in: .vertical) {
                content
                ScrollView(.vertical) {
                    content
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}

/// Sizes a pane to its content's own height, up to `maxHeight`. Panes sit in
/// a full-height container, and a plain frame would let them take all of it.
private struct PaneHeightLayout: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let natural = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

public extension View {
    /// Sets the text scale for the overlay panes below this view (#152).
    func paneTextScale(_ scale: CGFloat) -> some View {
        environment(\.paneTextScale, scale)
    }

    /// Pane text: `size` at the standard text size, scaled with the setting.
    func paneFont(size: CGFloat, weight: Font.Weight? = nil) -> some View {
        modifier(PaneFontModifier(size: size, weight: weight, usesAppFont: false))
    }

    /// Pane text in the app's font: `size` at the standard text size, scaled
    /// with the setting.
    func paneAppFont(size: CGFloat) -> some View {
        modifier(PaneFontModifier(size: size, weight: nil, usesAppFont: true))
    }

    /// Lets a pane grow upward with its text up to `maxHeight`, then scroll.
    func paneHeightLimit(_ maxHeight: CGFloat) -> some View {
        modifier(PaneHeightLimit(maxHeight: max(0, maxHeight)))
    }
}
