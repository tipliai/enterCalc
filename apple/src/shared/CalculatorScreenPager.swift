import SwiftUI

public struct CalculatorScreenPager<Content: View>: View {
    private struct DragState {
        var translation: CGFloat = 0
        var isPagingAxis: Bool = false
    }

    public let pagingAxis: Axis
    public let pageSpacing: CGFloat
    public let pageCount: Int
    public let activeIndex: Int
    public let canMoveBackward: Bool
    public let canMoveForward: Bool
    public let canCreateTrailingPage: Bool
    public let onMoveBackward: () -> Void
    public let onMoveForward: () -> Void
    public let onRequestCreateTrailingPage: () -> Void
    public let canCloseUpward: Bool
    public let upwardCloseThreshold: CGFloat
    public let onCloseUpward: (() -> Void)?
    public let activationThresholdRatio: CGFloat
    public let trailingPlaceholder: AnyView?
    public let transitionOverlayColor: Color?
    public let content: (Int) -> Content

    @GestureState private var dragState = DragState()
    @State private var isTransitionSettling = false
    @State private var settlingDisplayIndex: Int? = nil
    @State private var transitionGeneration: Int = 0

    public init(
        pagingAxis: Axis = .horizontal,
        pageSpacing: CGFloat = 0,
        pageCount: Int,
        activeIndex: Int,
        canMoveBackward: Bool,
        canMoveForward: Bool,
        canCreateTrailingPage: Bool,
        onMoveBackward: @escaping () -> Void,
        onMoveForward: @escaping () -> Void,
        onRequestCreateTrailingPage: @escaping () -> Void,
        canCloseUpward: Bool = false,
        upwardCloseThreshold: CGFloat = 90,
        onCloseUpward: (() -> Void)? = nil,
        activationThresholdRatio: CGFloat = 0.22,
        trailingPlaceholder: AnyView? = nil,
        transitionOverlayColor: Color? = nil,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.pagingAxis = pagingAxis
        self.pageSpacing = pageSpacing
        self.pageCount = pageCount
        self.activeIndex = activeIndex
        self.canMoveBackward = canMoveBackward
        self.canMoveForward = canMoveForward
        self.canCreateTrailingPage = canCreateTrailingPage
        self.onMoveBackward = onMoveBackward
        self.onMoveForward = onMoveForward
        self.onRequestCreateTrailingPage = onRequestCreateTrailingPage
        self.canCloseUpward = canCloseUpward
        self.upwardCloseThreshold = upwardCloseThreshold
        self.onCloseUpward = onCloseUpward
        self.activationThresholdRatio = activationThresholdRatio
        self.trailingPlaceholder = trailingPlaceholder
        self.transitionOverlayColor = transitionOverlayColor
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            pagerStack(in: geometry.size)
            .contentShape(Rectangle())
            .clipped()
            .animation(pageSnapAnimation, value: activeIndex)
            .animation(pageSnapAnimation, value: pageCount)
            .animation(.easeOut(duration: 0.12), value: isTransitionSettling)
            .animation(.easeOut(duration: 0.12), value: settlingDisplayIndex)
            .simultaneousGesture(dragGesture(pageDimension: pagingDimension(for: geometry.size)), including: .all)
        }
    }

    private var displayPageCount: Int {
        pageCount + (showsTrailingPlaceholder ? 1 : 0)
    }

    private var showsTrailingPlaceholder: Bool {
        canCreateTrailingPage && trailingPlaceholder != nil
    }

    @ViewBuilder
    private func pagerStack(in size: CGSize) -> some View {
        if pagingAxis == .horizontal {
            HStack(spacing: pageSpacing) {
                pageViews(in: size)
            }
            .frame(
                width: (size.width * CGFloat(max(displayPageCount, 1)))
                    + (pageSpacing * CGFloat(max(displayPageCount - 1, 0))),
                alignment: .leading
            )
            .offset(x: -CGFloat(activeIndex) * (size.width + pageSpacing) + adjustedTranslation(for: size.width))
        } else {
            VStack(spacing: pageSpacing) {
                pageViews(in: size)
            }
            .frame(
                height: (size.height * CGFloat(max(displayPageCount, 1)))
                    + (pageSpacing * CGFloat(max(displayPageCount - 1, 0))),
                alignment: .top
            )
            .offset(y: -CGFloat(activeIndex) * (size.height + pageSpacing) + adjustedTranslation(for: size.height))
        }
    }

    @ViewBuilder
    private func pageViews(in size: CGSize) -> some View {
        ForEach(0..<displayPageCount, id: \.self) { index in
            page(at: index)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(!isInteractionLocked)
                .overlay {
                    if let overlayColor = transitionOverlayColor,
                       destinationDisplayIndex == index {
                        Rectangle()
                            .fill(overlayColor.opacity(isTransitionSettling ? 0.18 : 0.26))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
        }
    }

    private var isDraggingOnPagingAxis: Bool {
        dragState.isPagingAxis && abs(dragState.translation) > 6
    }

    private var isInteractionLocked: Bool {
        isDraggingOnPagingAxis || isTransitionSettling
    }

    private var destinationDisplayIndex: Int? {
        if isTransitionSettling {
            return settlingDisplayIndex
        }

        guard isDraggingOnPagingAxis else { return nil }

        if dragState.translation < 0 {
            if canMoveForward {
                return activeIndex + 1
            }
            if showsTrailingPlaceholder {
                return pageCount
            }
            return nil
        }

        if dragState.translation > 0, canMoveBackward {
            return activeIndex - 1
        }

        return nil
    }

    private var pageSnapAnimation: Animation {
        .interactiveSpring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.16)
    }

    @ViewBuilder
    private func page(at index: Int) -> some View {
        if index < pageCount {
            content(index)
        } else if let trailingPlaceholder {
            trailingPlaceholder
        }
    }

    private func pagingDimension(for size: CGSize) -> CGFloat {
        pagingAxis == .horizontal ? size.width : size.height
    }

    private func adjustedTranslation(for pageDimension: CGFloat) -> CGFloat {
        guard pageCount > 0 else { return 0 }
        let translation = dragState.translation

        if translation > 0, !canMoveBackward {
            return rubberBandDistance(translation, dimension: max(pageDimension * 0.22, 44))
        }

        if translation < 0,
           !canMoveForward,
           !(activeIndex == pageCount - 1 && canCreateTrailingPage) {
            return rubberBandDistance(translation, dimension: max(pageDimension * 0.22, 44))
        }

        return translation
    }

    private func dragGesture(pageDimension: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .updating($dragState) { value, state, _ in
                let followsPagingAxis = isPredominantlyAlongPagingAxis(translation: value.translation)
                state = DragState(
                    translation: followsPagingAxis ? pagingTranslation(from: value.translation) : 0,
                    isPagingAxis: followsPagingAxis
                )
            }
            .onEnded { value in
                guard pageDimension > 0 else { return }

                if pagingAxis == .horizontal,
                   canCloseUpward,
                   isPredominantlyVertical(translation: value.translation),
                   value.translation.height <= -upwardCloseThreshold {
                    onCloseUpward?()
                    return
                }

                guard isPredominantlyAlongPagingAxis(translation: value.translation) else { return }

                let targetTranslation = pagingTranslation(from: value.translation)
                let predictedTranslation = pagingTranslation(from: value.predictedEndTranslation)
                let threshold = pageDimension * activationThresholdRatio
                let momentumAssistThreshold = pageDimension * 0.24

                let commitsForward = targetTranslation <= -threshold
                    || (targetTranslation <= -momentumAssistThreshold && predictedTranslation <= -threshold)
                let commitsBackward = targetTranslation >= threshold
                    || (targetTranslation >= momentumAssistThreshold && predictedTranslation >= threshold)

                if commitsForward {
                    lockTransition(to: canMoveForward ? activeIndex + 1 : (showsTrailingPlaceholder ? pageCount : nil))
                    if canMoveForward {
                        onMoveForward()
                    } else if activeIndex == pageCount - 1 && canCreateTrailingPage {
                        onRequestCreateTrailingPage()
                    }
                    return
                }

                if commitsBackward, canMoveBackward {
                    lockTransition(to: activeIndex - 1)
                    onMoveBackward()
                }
            }
    }

    private func pagingTranslation(from translation: CGSize) -> CGFloat {
        pagingAxis == .horizontal ? translation.width : translation.height
    }

    private func lockTransition(to displayIndex: Int?) {
        guard let displayIndex else { return }

        transitionGeneration += 1
        let generation = transitionGeneration

        settlingDisplayIndex = displayIndex
        isTransitionSettling = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard generation == transitionGeneration else { return }
            isTransitionSettling = false
            settlingDisplayIndex = nil
        }
    }

    private func isPredominantlyAlongPagingAxis(translation: CGSize) -> Bool {
        if pagingAxis == .horizontal {
            return abs(translation.width) > 8 && abs(translation.width) > abs(translation.height) * 1.15
        }

        return abs(translation.height) > 8 && abs(translation.height) > abs(translation.width) * 1.15
    }

    private func isPredominantlyVertical(translation: CGSize) -> Bool {
        translation.height < 0 && abs(translation.height) > 20 && abs(translation.height) > abs(translation.width) * 1.25
    }

    private func rubberBandDistance(_ translation: CGFloat, dimension: CGFloat) -> CGFloat {
        let magnitude = abs(translation)
        let resisted = (1 - (1 / ((magnitude * 0.55 / dimension) + 1))) * dimension
        return translation.sign == .minus ? -resisted : resisted
    }
}

public struct CalculatorScreenPageIndicator: View {
    public let axis: Axis
    public let pageCount: Int
    public let activeIndex: Int
    public let activeColor: Color
    public let inactiveColor: Color
    public let dotSize: CGFloat
    public let spacing: CGFloat

    public init(
        axis: Axis = .horizontal,
        pageCount: Int,
        activeIndex: Int,
        activeColor: Color,
        inactiveColor: Color,
        dotSize: CGFloat = 7,
        spacing: CGFloat = 8
    ) {
        self.axis = axis
        self.pageCount = pageCount
        self.activeIndex = activeIndex
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.dotSize = dotSize
        self.spacing = spacing
    }

    public var body: some View {
        if pageCount > 1 {
            indicatorStack
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityStatusText))
        }
    }

    @ViewBuilder
    private var indicatorStack: some View {
        if axis == .horizontal {
            HStack(spacing: spacing) {
                indicatorDots
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: spacing) {
                indicatorDots
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var indicatorDots: some View {
        ForEach(0..<pageCount, id: \.self) { index in
            Circle()
                .fill(dotColor(for: index))
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityStatusText: String {
        String(format: localized("screen.pageStatus"), String(activeIndex + 1), String(pageCount))
    }

    private func dotColor(for index: Int) -> Color {
        return index == activeIndex ? activeColor : inactiveColor
    }
}