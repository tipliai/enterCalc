import CoreGraphics

public enum CalculatorDisplayMetrics {
    // Keep operation-line text readable even when the expression is long.
    public static let operationLineMinimumFontSize: CGFloat = 11

    public static func operationLineMinScaleFactor(for baseFontSize: CGFloat) -> CGFloat {
        guard baseFontSize > 0 else { return 1 }
        return min(1, operationLineMinimumFontSize / baseFontSize)
    }
}