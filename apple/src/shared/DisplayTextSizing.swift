import CoreGraphics

/// Sizes the display's result and operation text to use the room the display
/// actually has (#136, #148).
///
/// Long values already shrink to fit the width through `minimumScaleFactor`,
/// but nothing grew the text when the display had extra room: a tall phone, an
/// iPad or Mac window, or a keypad dragged smaller. The text grows with the
/// display, with no fixed ceiling, until the result line plus one operation
/// line fill `fillRatio` of the height or a typical result fills the width,
/// whichever comes first. It never shrinks below its base size for lack of
/// room.
///
/// The Text Size setting (or the OS text size) then scales that up or down,
/// and the result is held to what still fits the display's height.
///
/// Callers pass a size that doesn't depend on the text being shown, so the
/// size holds still while typing.
public enum DisplayTextSizing {
    /// Share of the display height the result plus one operation line take at
    /// the default text size. The rest leaves room for a wrapped operation line.
    public static let fillRatio: CGFloat = 0.7

    /// Share of the display height the two lines may never exceed, however
    /// large the chosen text size.
    public static let maximumFillRatio: CGFloat = 0.95

    /// The width of a typical result, in ems: about seven digits and a grouping
    /// separator. Growth for space stops once that would no longer fit, so a
    /// narrow window keeps a sensible size and widening it lets the text grow.
    /// Longer values still shrink to fit.
    public static let referenceResultWidthInEms: CGFloat = 4.2

    /// Keeps a long operation line from taking over the display: it grows with
    /// the result up to this multiple of its base size, times the text scale.
    public static let maximumOperationScale: CGFloat = 1.6

    /// Line heights as a multiple of font size, matching the display's frames.
    static let resultLineHeightFactor: CGFloat = 1.12
    static let operationLineHeightFactor: CGFloat = 1.3

    public struct FontSizes: Equatable {
        public let result: CGFloat
        public let operation: CGFloat
    }

    /// How much the base sizes can grow for the room the display has, before
    /// any text-size preference. At least 1.
    public static func scale(
        contentHeight: CGFloat,
        contentWidth: CGFloat,
        baseResultFontSize: CGFloat,
        baseOperationFontSize: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard baseResultFontSize > 0 else { return 1 }
        let heightFitted = resultFontSize(
            fillingShare: fillRatio,
            of: contentHeight,
            baseResultFontSize: baseResultFontSize,
            baseOperationFontSize: baseOperationFontSize,
            spacing: spacing
        )
        let widthFitted = contentWidth / referenceResultWidthInEms
        return max(min(heightFitted, widthFitted) / baseResultFontSize, 1)
    }

    /// The result and operation font sizes for a display of this size, with
    /// `textScale` from the Text Size setting or the OS (1 is the default).
    public static func fontSizes(
        contentHeight: CGFloat,
        contentWidth: CGFloat,
        baseResultFontSize: CGFloat,
        baseOperationFontSize: CGFloat,
        spacing: CGFloat,
        textScale: CGFloat
    ) -> FontSizes {
        guard baseResultFontSize > 0 else {
            return FontSizes(result: baseResultFontSize, operation: baseOperationFontSize)
        }
        let spaceScale = scale(
            contentHeight: contentHeight,
            contentWidth: contentWidth,
            baseResultFontSize: baseResultFontSize,
            baseOperationFontSize: baseOperationFontSize,
            spacing: spacing
        )
        let wanted = baseResultFontSize * spaceScale * textScale
        let mostThatFits = resultFontSize(
            fillingShare: maximumFillRatio,
            of: contentHeight,
            baseResultFontSize: baseResultFontSize,
            baseOperationFontSize: baseOperationFontSize,
            spacing: spacing
        )
        // A display too small for even the base size keeps the base size scaled
        // down by a smaller text setting, as before (#136).
        let floor = baseResultFontSize * min(textScale, 1)
        let result = max(min(wanted, mostThatFits), floor)
        let operationScale = min(
            result / baseResultFontSize,
            maximumOperationScale * textScale
        )
        return FontSizes(result: result, operation: baseOperationFontSize * operationScale)
    }

    /// The result font size at which the result plus one operation line (the
    /// operation scaled in proportion) fill `share` of `height`.
    private static func resultFontSize(
        fillingShare share: CGFloat,
        of height: CGFloat,
        baseResultFontSize: CGFloat,
        baseOperationFontSize: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let operationRatio = baseOperationFontSize / baseResultFontSize
        let stackHeightPerPoint = resultLineHeightFactor + operationRatio * operationLineHeightFactor
        return (height * share - spacing) / stackHeightPerPoint
    }
}
