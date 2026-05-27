import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct EditableDisplayResultText: View {
    public let text: String
    public let fontSize: CGFloat
    public let foregroundColor: Color
    public let minScaleFactor: CGFloat
    public let caretBoundaryIndex: Int?
    public let caretColor: Color
    public let onTapBoundary: (Int) -> Void
    @State private var caretBlinkStartDate = Date()

    public init(
        text: String,
        fontSize: CGFloat,
        foregroundColor: Color,
        minScaleFactor: CGFloat,
        caretBoundaryIndex: Int?,
        caretColor: Color,
        onTapBoundary: @escaping (Int) -> Void
    ) {
        self.text = text
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
        self.minScaleFactor = minScaleFactor
        self.caretBoundaryIndex = caretBoundaryIndex
        self.caretColor = caretColor
        self.onTapBoundary = onTapBoundary
    }

    public var body: some View {
        GeometryReader { geometry in
            let layout = EditableDisplayResultTextLayout(
                text: text,
                fontSize: fontSize,
                availableWidth: geometry.size.width,
                minScaleFactor: minScaleFactor
            )

            ZStack(alignment: .topLeading) {
                Text(text)
                    .font(EnterCalcFont.appFont(size: layout.resolvedFontSize))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1)
                    .layoutPriority(1)

                ForEach(Array(layout.tapRegions.enumerated()), id: \.offset) { index, region in
                    Color.clear
                        .frame(width: region.width, height: max(layout.lineHeight, geometry.size.height))
                        .contentShape(Rectangle())
                        .position(x: region.midX, y: max(layout.lineHeight, geometry.size.height) / 2)
                        .onTapGesture {
                            onTapBoundary(index)
                        }
                }

                if let caretBoundaryIndex,
                   layout.boundaryXPositions.indices.contains(caretBoundaryIndex) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        Rectangle()
                            .fill(caretColor)
                            .frame(width: layout.caretWidth, height: layout.caretHeight)
                            .opacity(caretOpacity(at: context.date))
                            .offset(
                                x: layout.boundaryXPositions[caretBoundaryIndex],
                                y: layout.caretTopInset
                            )
                    }
                }
            }
            .onAppear {
                resetCaretBlink()
            }
            .editableDisplayOnChange(of: caretBoundaryIndex) {
                resetCaretBlink()
            }
        }
    }

    private func resetCaretBlink() {
        caretBlinkStartDate = Date()
    }

    private func caretOpacity(at date: Date) -> Double {
        guard caretBoundaryIndex != nil else { return 0 }
        let cycleDuration: TimeInterval = 1.0
        let visibleDuration: TimeInterval = 0.55
        let elapsed = date.timeIntervalSince(caretBlinkStartDate)
        let cycleOffset = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        return cycleOffset < visibleDuration ? 1 : 0
    }
}

struct EditableDisplayResultTextLayout {
    struct TapRegion {
        let midX: CGFloat
        let width: CGFloat
    }

    let resolvedFontSize: CGFloat
    let lineHeight: CGFloat
    let textWidth: CGFloat
    let caretWidth: CGFloat
    let caretHeight: CGFloat
    let caretTopInset: CGFloat
    let boundaryXPositions: [CGFloat]
    let tapRegions: [TapRegion]

    init(text: String, fontSize: CGFloat, availableWidth: CGFloat, minScaleFactor: CGFloat) {
        let normalizedWidth = max(availableWidth, 1)
        let maximumIterations = 4
        var resolvedScale: CGFloat
        let measuredWidth = editableDisplayMeasureText(text, fontSize: fontSize)
        if measuredWidth > 0 {
            resolvedScale = min(1, max(minScaleFactor, normalizedWidth / measuredWidth))
        } else {
            resolvedScale = 1
        }

        let characters = Array(text)
        var widths: [CGFloat] = [0]
        var totalWidth: CGFloat = 0

        for _ in 0..<maximumIterations {
            let candidateFontSize = fontSize * resolvedScale
            widths = Self.measureBoundaryWidths(characters: characters, fontSize: candidateFontSize)
            totalWidth = widths.last ?? 0

            guard totalWidth > normalizedWidth,
                  resolvedScale > minScaleFactor else {
                break
            }

            let fittedScale = max(minScaleFactor, resolvedScale * (normalizedWidth / totalWidth))
            guard fittedScale < resolvedScale else { break }
            resolvedScale = fittedScale
        }

        let resolvedFontSize = fontSize * resolvedScale
        self.resolvedFontSize = resolvedFontSize
        lineHeight = editableDisplayPlatformLineHeight(fontSize: resolvedFontSize)
        textWidth = totalWidth
        caretWidth = max(1.25, resolvedFontSize * 0.04)
        caretHeight = lineHeight * 0.88
        caretTopInset = lineHeight * 0.06
        let leadingX = max(0, normalizedWidth - totalWidth)
        boundaryXPositions = widths.map { leadingX + $0 }
        tapRegions = Self.makeTapRegions(
            boundaryXPositions: boundaryXPositions,
            availableWidth: normalizedWidth,
            trailingTextWidth: totalWidth
        )
    }

    private static func measureBoundaryWidths(characters: [Character], fontSize: CGFloat) -> [CGFloat] {
        var widths: [CGFloat] = [0]
        var prefix = ""
        for character in characters {
            prefix.append(character)
            widths.append(editableDisplayMeasureText(prefix, fontSize: fontSize))
        }
        return widths
    }

    private static func makeTapRegions(
        boundaryXPositions: [CGFloat],
        availableWidth: CGFloat,
        trailingTextWidth: CGFloat
    ) -> [TapRegion] {
        guard !boundaryXPositions.isEmpty else { return [] }
        let leadingEdge = max(0, boundaryXPositions.first ?? 0)
        let trailingEdge = min(availableWidth, leadingEdge + trailingTextWidth)
        let edgePadding: CGFloat = 8

        return boundaryXPositions.indices.map { index in
            let left: CGFloat
            if index == 0 {
                left = max(0, leadingEdge - edgePadding)
            } else {
                left = (boundaryXPositions[index - 1] + boundaryXPositions[index]) * 0.5
            }

            let right: CGFloat
            if index == boundaryXPositions.count - 1 {
                right = min(availableWidth, trailingEdge + edgePadding)
            } else {
                right = (boundaryXPositions[index] + boundaryXPositions[index + 1]) * 0.5
            }

            return TapRegion(
                midX: (left + right) * 0.5,
                width: max(18, right - left)
            )
        }
    }
}

private func editableDisplayMeasureText(_ text: String, fontSize: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    #if canImport(UIKit)
    let attributes: [NSAttributedString.Key: Any] = [.font: EnterCalcFont.platformFont(size: fontSize)]
    return ceil((text as NSString).size(withAttributes: attributes).width)
    #elseif canImport(AppKit)
    let attributes: [NSAttributedString.Key: Any] = [.font: EnterCalcFont.platformFont(size: fontSize)]
    return ceil((text as NSString).size(withAttributes: attributes).width)
    #else
    return 0
    #endif
}

private func editableDisplayPlatformLineHeight(fontSize: CGFloat) -> CGFloat {
    #if canImport(UIKit)
    EnterCalcFont.platformFont(size: fontSize).lineHeight
    #elseif canImport(AppKit)
    EnterCalcFont.platformFont(size: fontSize).ascender - EnterCalcFont.platformFont(size: fontSize).descender
    #else
    fontSize * 1.2
    #endif
}

private struct EditableDisplayOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: () -> Void
    @State private var previousValue: Value?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.onChange(of: value) {
                action()
            }
        } else {
            content.onReceive(Just(value)) { newValue in
                guard previousValue != newValue else { return }
                previousValue = newValue
                action()
            }
        }
    }
}

private extension View {
    func editableDisplayOnChange<Value: Equatable>(of value: Value, perform action: @escaping () -> Void) -> some View {
        modifier(EditableDisplayOnChangeModifier(value: value, action: action))
    }
}
