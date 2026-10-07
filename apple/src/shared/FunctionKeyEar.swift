import SwiftUI

// MARK: - Dog-ear on changeable keys (#131)
//
// A key whose function can be changed has its top-right corner turned down,
// like the corner of a page: the corner is cut off on the diagonal and the
// cut-off piece lies folded over the key. The folded piece keeps a rounded
// tip, standing in for the key's own rounded corner turned over.

public enum FunctionKeyEar {
    /// Size of the ear for a key of the given height: about a fifth of a full
    /// keypad key, a little over a quarter of a small action-row key.
    public static func size(forKeyHeight height: CGFloat, isActionRow: Bool) -> CGFloat {
        #if os(macOS)
        let (ratio, range): (CGFloat, ClosedRange<CGFloat>) = isActionRow ? (0.27, 4...8) : (0.18, 8...14)
        #else
        let (ratio, range): (CGFloat, ClosedRange<CGFloat>) = isActionRow ? (0.27, 4...8) : (0.19, 12...18)
        #endif
        return min(max((height * ratio).rounded(), range.lowerBound), range.upperBound)
    }
}

/// A key's rounded rectangle with its top-right corner cut off on the
/// diagonal. With no ear it is the plain rounded rectangle.
public struct FunctionKeyShape: Shape {
    public var cornerRadius: CGFloat
    public var ear: CGFloat

    public init(cornerRadius: CGFloat, ear: CGFloat) {
        self.cornerRadius = cornerRadius
        self.ear = ear
    }

    public func path(in rect: CGRect) -> Path {
        let rounded = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        guard ear > 0 else { return rounded }

        var keep = Path()
        keep.move(to: CGPoint(x: rect.minX, y: rect.minY))
        keep.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY))
        keep.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + ear))
        keep.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        keep.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        keep.closeSubpath()
        return rounded.intersection(keep)
    }
}

/// The folded-down corner itself: the triangle under the cut, its right-angle
/// tip rounded to half the ear's size, kept inside the key's outline.
public struct FunctionKeyEarFlap: Shape {
    public var cornerRadius: CGFloat
    public var ear: CGFloat

    public init(cornerRadius: CGFloat, ear: CGFloat) {
        self.cornerRadius = cornerRadius
        self.ear = ear
    }

    public func path(in rect: CGRect) -> Path {
        guard ear > 0 else { return Path() }
        let left = rect.maxX - ear
        let tip = CGPoint(x: left, y: rect.minY + ear)

        var flap = Path()
        flap.move(to: CGPoint(x: left, y: rect.minY))
        flap.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + ear))
        flap.addArc(tangent1End: tip, tangent2End: CGPoint(x: left, y: rect.minY), radius: ear / 2)
        flap.closeSubpath()

        let key = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        return flap.intersection(key)
    }
}

extension View {
    /// Draws the folded-down corner over a changeable key. `ear` of 0 draws
    /// nothing, so fixed keys can share the same code path.
    public func functionKeyEar(cornerRadius: CGFloat, ear: CGFloat, color: Color) -> some View {
        overlay {
            if ear > 0 {
                FunctionKeyEarFlap(cornerRadius: cornerRadius, ear: ear)
                    .fill(color)
                    .shadow(color: Color.black.opacity(0.16), radius: 0.75, x: -1, y: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
