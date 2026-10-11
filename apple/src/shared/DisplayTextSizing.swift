import CoreGraphics

/// Scales the display's result and operation text up to use the room the
/// display actually has (#136).
///
/// Long values already shrink to fit the width through `minimumScaleFactor`,
/// but nothing grew the text when the display had extra height: a tall phone,
/// an iPad or Mac window, or a keypad resized smaller. This grows both lines
/// together until the result line plus one operation line fill `fillRatio` of
/// the height, and never shrinks them below their base sizes.
///
/// Callers pass a height that doesn't depend on the text being shown, so the
/// size holds still while typing.
public enum DisplayTextSizing {
    /// Share of the display height the result plus one operation line may take.
    /// The rest leaves room for a wrapped operation line.
    public static let fillRatio: CGFloat = 0.7

    /// Keeps the number in proportion to the keys on very large displays.
    public static let maximumScale: CGFloat = 1.6

    /// Line heights as a multiple of font size, matching the display's frames.
    static let resultLineHeightFactor: CGFloat = 1.12
    static let operationLineHeightFactor: CGFloat = 1.3

    /// The factor to multiply the base result and operation font sizes by.
    public static func scale(
        contentHeight: CGFloat,
        baseResultFontSize: CGFloat,
        baseOperationFontSize: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard baseResultFontSize > 0 else { return 1 }
        let operationRatio = baseOperationFontSize / baseResultFontSize
        let stackHeightPerPoint = resultLineHeightFactor + operationRatio * operationLineHeightFactor
        let fittedResultFontSize = (contentHeight * fillRatio - spacing) / stackHeightPerPoint
        return min(max(fittedResultFontSize / baseResultFontSize, 1), maximumScale)
    }
}
