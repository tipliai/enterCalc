import CoreGraphics

public enum CalculatorDisplayMetrics {
    // Keep operation-line text readable even when the expression is long.
    public static let operationLineMinimumFontSize: CGFloat = 11

    // Shared compaction curve used by iOS and macOS for operation-line-dependent UI.
    public static let operationTextCompactionStartLength = 20
    public static let operationTextCompactionRange = 14

    public static func operationLineMinScaleFactor(for baseFontSize: CGFloat) -> CGFloat {
        guard baseFontSize > 0 else { return 1 }
        return min(1, operationLineMinimumFontSize / baseFontSize)
    }

    public static func operationTextCompactionProgress(for expressionLength: Int) -> Double {
        let delta = expressionLength - operationTextCompactionStartLength
        guard operationTextCompactionRange > 0 else { return delta > 0 ? 1 : 0 }
        return min(1, max(0, Double(delta) / Double(operationTextCompactionRange)))
    }
}