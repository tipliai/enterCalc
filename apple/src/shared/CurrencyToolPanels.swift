import SwiftUI

/// Shared chrome for the Currency-mode tools (#92).
///
/// Both panels live here rather than in each platform's view file so VAT and
/// tipping cannot drift apart between macOS and iOS — the platforms supply the
/// palette, the strings and the surrounding presentation, and the panel itself
/// is the same code.
private struct CurrencyToolChrome<Content: View>: View {
    let title: String
    let closeLabel: String
    let removeLabel: String
    let palette: Palette
    let onRemove: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    #if os(macOS)
    @State private var isCloseHovering = false
    @State private var isTrashHovering = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    /// Laid out like the rounding pane's header: the title centred in the
    /// secondary colour, the trash (take the result back off the display and
    /// close) at the leading edge, and the close button at the trailing edge.
    private var header: some View {
        ZStack {
            Text(title)
                #if os(macOS)
                .font(EnterCalcFont.subheadline)
                #else
                .font(EnterCalcFont.appFont(size: 13))
                #endif
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 0) {
                headerButton(symbol: "trash", label: removeLabel, isHovering: trashHoverBinding, action: onRemove)
                Spacer(minLength: 0)
                headerButton(symbol: "xmark", label: closeLabel, isHovering: closeHoverBinding, action: onDismiss)
            }
        }
        #if os(macOS)
        .frame(height: 32)
        #else
        .frame(height: 44)
        #endif
    }

    #if os(macOS)
    private var trashHoverBinding: Binding<Bool> { $isTrashHovering }
    private var closeHoverBinding: Binding<Bool> { $isCloseHovering }
    #else
    private var trashHoverBinding: Binding<Bool> { .constant(false) }
    private var closeHoverBinding: Binding<Bool> { .constant(false) }
    #endif

    @ViewBuilder
    private func headerButton(symbol: String, label: String, isHovering: Binding<Bool>, action: @escaping () -> Void) -> some View {
        #if os(macOS)
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16, alignment: .center)
                .padding(8)
                .background(isHovering.wrappedValue ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(label)
        .accessibilityLabel(Text(label))
        .onHover { isHovering.wrappedValue = $0 }
        #else
        Button(action: action) {
            Image(systemName: symbol)
                .font(EnterCalcFont.appFont(size: 18))
                .frame(width: 28, height: 28)
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: 44, height: 44, alignment: .center)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        #endif
    }
}

/// Strings the rate chooser needs beyond each panel's own labels (#124).
public struct RateEditingLabels {
    public let typeRate: String
    public let editPreset: String
    public let presetHint: String
    public let done: String
    public let cancel: String
    public let rateRange: String

    public init(localized: (String) -> String) {
        typeRate = localized("currency.rate.type")
        editPreset = localized("currency.rate.editPreset")
        presetHint = localized("currency.rate.presetHint")
        done = localized("currency.rate.done")
        cancel = localized("currency.rate.cancel")
        rateRange = localized("currency.rate.range")
    }
}

/// Quick-choice rates, a stepper, and typed entry (#124).
///
/// Tap the rate to type one; press and hold a preset to type a new value for
/// it, which is kept (typing the preset's default value restores it). Typing happens in a system alert with a text field — a
/// lightbox over the panel rather than inline, since it is a rare action and
/// editing in place was confusing. On iPhone the field brings up the decimal
/// pad; iPad has no number-only pad and shows its numbers layout.
private struct RateChooser: View {
    let rates: [Decimal]
    let selected: Decimal
    let stepLabel: String
    let decreaseLabel: String
    let increaseLabel: String
    let labels: RateEditingLabels
    let decimalSeparator: String
    let palette: Palette
    let format: (Decimal) -> String
    @ObservedObject var editor: RateEditor
    let onSelect: (Decimal) -> Void
    let onPresetEdited: (Int, Decimal?) -> Void
    /// The Tip pane uses a slider instead of the − rate + selector.
    var showsStepper: Bool = true
    /// When set, only this preset is shown as selected, rather than whichever
    /// preset equals the rate. The Tip pane uses it so a preset lights up only
    /// when pressed, not as the slider passes over its value.
    var pressedSlot: Int?? = nil
    /// Told which preset was pressed or edited.
    var onPresetChosen: ((Int) -> Void)? = nil

    @State private var typedText = ""

    var body: some View {
        choosingView
            .alert(alertTitle, isPresented: isEditingBinding) {
                TextField(editor.entry.displayText(decimalSeparator: decimalSeparator), text: $typedText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Button(labels.cancel, role: .cancel) { editor.cancel() }

                Button(labels.done) { commitTypedText() }
            } message: {
                Text(labels.rateRange)
            }
    }

    private var alertTitle: String {
        editor.target == .rate ? stepLabel : labels.editPreset
    }

    /// Presented while an edit is open. Dismissing the alert by any route the
    /// buttons do not handle abandons the edit.
    private var isEditingBinding: Binding<Bool> {
        Binding(
            get: { editor.isEditing },
            set: { isPresented in
                if !isPresented, editor.isEditing { editor.cancel() }
            }
        )
    }

    /// Applies the alert's text. An empty field keeps the rate it opened on;
    /// text that is not a valid rate leaves everything unchanged.
    private func commitTypedText() {
        let text = typedText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || editor.setTypedText(text, decimalSeparator: decimalSeparator) {
            editor.press(.done)
        } else {
            editor.cancel()
        }
    }

    /// The presets and the rate stepper share one row; the stepper's value is
    /// the rate in use, so it needs no label of its own.
    private var choosingView: some View {
        HStack(spacing: 6) {
            ForEach(Array(rates.enumerated()), id: \.offset) { slot, rate in
                presetButton(slot: slot, rate: rate)
            }

            if showsStepper {
                StepperControl(
                    value: "\(format(selected))%",
                    decreaseLabel: decreaseLabel,
                    increaseLabel: increaseLabel,
                    palette: palette,
                    onDecrease: { onSelect(RateEntry.stepped(selected, up: false)) },
                    onIncrease: { onSelect(RateEntry.stepped(selected, up: true)) },
                    valueActionLabel: labels.typeRate,
                    onValueTap: beginTypingRate
                )
                .layoutPriority(1)
            }
        }
    }

    private func presetButton(slot: Int, rate: Decimal) -> some View {
        let isSelected = pressedSlot.map { $0 == slot } ?? (rate == selected)
        return Text("\(format(rate))%")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? palette.accentText : palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.accent : palette.buttonFunction)
            )
            .contentShape(Rectangle())
            .onTapGesture { choose(slot: slot, rate: rate) }
            .onLongPressGesture(minimumDuration: 0.45) { beginEditingPreset(slot) }
            .accessibilityElement()
            .accessibilityLabel(Text("\(format(rate))%"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityHint(Text(labels.presetHint))
            .accessibilityAction { choose(slot: slot, rate: rate) }
            .accessibilityAction(named: Text(labels.editPreset)) { beginEditingPreset(slot) }
    }

    private func choose(slot: Int, rate: Decimal) {
        onPresetChosen?(slot)
        onSelect(rate)
    }

    private func beginTypingRate() {
        typedText = ""
        let original = selected
        editor.begin(
            .rate,
            value: selected,
            onLive: onSelect,
            onCommit: onSelect,
            onCancel: { onSelect(original) }
        )
    }

    private func beginEditingPreset(_ slot: Int) {
        guard rates.indices.contains(slot) else { return }
        typedText = ""
        let original = selected
        editor.begin(
            .preset(slot),
            value: rates[slot],
            onLive: onSelect,
            onCommit: { rate in
                onPresetEdited(slot, rate)
                onPresetChosen?(slot)
                onSelect(rate)
            },
            onCancel: { onSelect(original) }
        )
    }
}

/// Minus / value / plus, used for both the custom rate and the party size.
private struct StepperControl: View {
    let value: String
    let decreaseLabel: String
    let increaseLabel: String
    let palette: Palette
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    /// When set, the value itself is a button (tapping the rate types one).
    var valueActionLabel: String? = nil
    var onValueTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            button("minus", label: decreaseLabel, action: onDecrease)

            valueView

            button("plus", label: increaseLabel, action: onIncrease)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.buttonFunction)
        )
    }

    @ViewBuilder
    private var valueView: some View {
        let text = Text(value)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(palette.textPrimary)
            .frame(minWidth: 56)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        if let onValueTap {
            Button(action: onValueTap) {
                text
                    .underline(true, pattern: .dot, color: palette.textSecondary)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(value))
            .accessibilityHint(Text(valueActionLabel ?? ""))
        } else {
            text
        }
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// One labelled figure in a panel's results block.
private struct ResultRow: View {
    let label: String
    let value: String
    let isEmphasised: Bool
    let palette: Palette

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: isEmphasised ? 17 : 14, weight: isEmphasised ? .semibold : .regular))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        // Read as one phrase — "Inc VAT, $120" — rather than as two fragments.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - VAT

/// VAT in both directions, including the reverse case from #25: the value on
/// screen is treated as the gross and the tax is backed out of it.
public struct CurrencyVATPanel: View {
    private let value: Decimal
    private let rate: Decimal
    private let presets: RatePresets
    private let currencyFractionDigits: Int
    private let isRemoving: Bool
    private let palette: Palette
    private let localized: (String) -> String
    private let format: (Decimal) -> String
    private let formatRate: (Decimal) -> String
    private let onRateChange: (Decimal) -> Void
    @ObservedObject private var rateEditor: RateEditor
    private let onPresetEdited: (Int, Decimal?) -> Void
    private let onDirectionChange: (Bool) -> Void
    private let onResult: (Decimal) -> Void
    private let onRemove: () -> Void
    private let onDismiss: () -> Void

    public init(
        value: Decimal,
        rate: Decimal,
        presets: RatePresets,
        currencyFractionDigits: Int = 2,
        isRemoving: Bool,
        palette: Palette,
        localized: @escaping (String) -> String,
        format: @escaping (Decimal) -> String,
        formatRate: @escaping (Decimal) -> String,
        onRateChange: @escaping (Decimal) -> Void,
        rateEditor: RateEditor,
        onPresetEdited: @escaping (Int, Decimal?) -> Void,
        onDirectionChange: @escaping (Bool) -> Void,
        onResult: @escaping (Decimal) -> Void,
        onRemove: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.value = value
        self.rate = rate
        self.presets = presets
        self.currencyFractionDigits = currencyFractionDigits
        self.isRemoving = isRemoving
        self.palette = palette
        self.localized = localized
        self.format = format
        self.formatRate = formatRate
        self.onRateChange = onRateChange
        self.rateEditor = rateEditor
        self.onPresetEdited = onPresetEdited
        self.onDirectionChange = onDirectionChange
        self.onResult = onResult
        self.onRemove = onRemove
        self.onDismiss = onDismiss
    }

    /// Rounded to the currency's minor units: VAT is always money, so the
    /// figures shown and the result applied carry two decimals for most
    /// currencies and none for the yen, won and the like.
    private var breakdown: VATBreakdown? {
        let exact = isRemoving
            ? VATCalculation.removing(rate: rate, fromGross: value)
            : VATCalculation.adding(rate: rate, toNet: value)
        return exact?.rounded(toScale: currencyFractionDigits, isRemoving: isRemoving)
    }

    public var body: some View {
        CurrencyToolChrome(
            title: localized("currency.vat.title"),
            closeLabel: localized("currency.tool.close"),
            removeLabel: localized("currency.vat.clear"),
            palette: palette,
            onRemove: onRemove,
            onDismiss: onDismiss
        ) {
            VStack(spacing: 12) {
                RateChooser(
                    rates: presets.rates,
                    selected: rate,
                    stepLabel: localized("currency.vat.rate"),
                    decreaseLabel: localized("currency.vat.rate.decrease"),
                    increaseLabel: localized("currency.vat.rate.increase"),
                    labels: RateEditingLabels(localized: localized),
                    decimalSeparator: presets.decimalSeparator,
                    palette: palette,
                    format: formatRate,
                    editor: rateEditor,
                    onSelect: { onRateChange(max($0, 0)) },
                    onPresetEdited: onPresetEdited
                )

                directionPicker

                if let breakdown {
                    VStack(spacing: 6) {
                        ResultRow(label: localized("currency.vat.net"), value: format(breakdown.net), isEmphasised: isRemoving, palette: palette)
                        ResultRow(label: localized("currency.vat.amount"), value: format(breakdown.vat), isEmphasised: false, palette: palette)
                        ResultRow(label: localized("currency.vat.gross"), value: format(breakdown.gross), isEmphasised: !isRemoving, palette: palette)
                    }
                }
            }
        }
        // Applied as soon as the panel opens, and again on every change: there
        // is no Use Result step. Reopening the panel adjusts the same result.
        .onAppear(perform: sendResult)
        .onChange(of: appliedResult) { _, _ in sendResult() }
    }

    /// The figure written to the display: the gross when adding VAT, the net
    /// when removing it.
    private var appliedResult: Decimal? {
        breakdown.map { isRemoving ? $0.net : $0.gross }
    }

    private func sendResult() {
        guard value != 0, let appliedResult else { return }
        onResult(appliedResult)
    }

    private var directionPicker: some View {
        HStack(spacing: 6) {
            directionButton(title: localized("currency.vat.add"), isSelected: !isRemoving) { onDirectionChange(false) }
            directionButton(title: localized("currency.vat.remove"), isSelected: isRemoving) { onDirectionChange(true) }
        }
    }

    private func directionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? palette.accentText : palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? palette.accent : palette.buttonFunction)
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Tip

/// The tip percentage, with the tip and the total shown together (#92). The
/// tip is rounded to the currency's minor units, as it would be paid, and the
/// total is the bill plus that tip.
public struct CurrencyTipPanel: View {
    private let bill: Decimal
    private let rate: Decimal
    private let presets: RatePresets
    private let currencyFractionDigits: Int
    private let palette: Palette
    private let localized: (String) -> String
    private let format: (Decimal) -> String
    private let formatRate: (Decimal) -> String
    private let onRateChange: (Decimal) -> Void
    @ObservedObject private var rateEditor: RateEditor
    private let onPresetEdited: (Int, Decimal?) -> Void
    private let onResult: (Decimal) -> Void
    private let onTipOff: () -> Void
    private let onRemove: () -> Void
    private let onDismiss: () -> Void

    /// The preset last pressed in this pane. Moving the slider clears it, so a
    /// preset is shown as selected only when it was actually pressed.
    @State private var pressedPreset: Int?

    public init(
        bill: Decimal,
        rate: Decimal,
        presets: RatePresets,
        currencyFractionDigits: Int = 2,
        palette: Palette,
        localized: @escaping (String) -> String,
        format: @escaping (Decimal) -> String,
        formatRate: @escaping (Decimal) -> String,
        onRateChange: @escaping (Decimal) -> Void,
        rateEditor: RateEditor,
        onPresetEdited: @escaping (Int, Decimal?) -> Void,
        onResult: @escaping (Decimal) -> Void,
        onTipOff: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.bill = bill
        self.rate = rate
        self.presets = presets
        self.currencyFractionDigits = currencyFractionDigits
        self.palette = palette
        self.localized = localized
        self.format = format
        self.formatRate = formatRate
        self.onRateChange = onRateChange
        self.rateEditor = rateEditor
        self.onPresetEdited = onPresetEdited
        self.onResult = onResult
        self.onTipOff = onTipOff
        self.onRemove = onRemove
        self.onDismiss = onDismiss
    }

    private var tip: Decimal {
        TipBreakdown.roundedTip(bill: bill, rate: rate, scale: currencyFractionDigits)
    }

    private var total: Decimal { bill + tip }

    public var body: some View {
        CurrencyToolChrome(
            title: localized("currency.tip.title"),
            closeLabel: localized("currency.tool.close"),
            removeLabel: localized("currency.tip.clear"),
            palette: palette,
            onRemove: onRemove,
            onDismiss: onDismiss
        ) {
            VStack(spacing: 12) {
                RateChooser(
                    rates: presets.rates,
                    selected: rate,
                    stepLabel: localized("currency.tip.rate"),
                    decreaseLabel: "",
                    increaseLabel: "",
                    labels: RateEditingLabels(localized: localized),
                    decimalSeparator: presets.decimalSeparator,
                    palette: palette,
                    format: formatRate,
                    editor: rateEditor,
                    onSelect: { onRateChange(max($0, 0)) },
                    onPresetEdited: onPresetEdited,
                    showsStepper: false,
                    pressedSlot: .some(pressedPreset),
                    onPresetChosen: { pressedPreset = $0 }
                )

                VStack(spacing: 6) {
                    ResultRow(
                        label: "\(localized("currency.tip.amount")) (\(formatRate(rate))%)",
                        value: format(tip),
                        isEmphasised: false,
                        palette: palette
                    )
                    ResultRow(label: localized("currency.tip.total"), value: format(total), isEmphasised: true, palette: palette)
                }

                TipRateSlider(
                    rate: rate,
                    label: localized("currency.tip.rate"),
                    palette: palette,
                    onChange: { newRate in
                        pressedPreset = nil
                        onRateChange(newRate)
                    }
                )
            }
        }
        // Applied as soon as the panel opens, and again on every change.
        .onAppear {
            // Reopening after choosing a preset shows it as chosen.
            pressedPreset = presets.rates.firstIndex(of: rate)
            sendResult()
        }
        .onChange(of: total) { _, _ in sendResult() }
    }

    /// A 0% tip is the slider's Off position: the tip is taken back off the
    /// display rather than applied as a zero.
    private func sendResult() {
        guard bill != 0 else { return }
        if rate == 0 {
            onTipOff()
        } else {
            onResult(total)
        }
    }
}

/// The Tip pane's slider, styled like the rounding pane's: Off (a power icon)
/// at the left, then a notch every 2% up to 40%. It moves in whole steps of
/// 2%; a preset or a long-press edit can still set any rate, which the slider
/// shows between notches (and at the end for anything above 40%).
private struct TipRateSlider: View {
    static let range: ClosedRange<Double> = 0...40
    static let step: Double = 2

    let rate: Decimal
    let label: String
    let palette: Palette
    let onChange: (Decimal) -> Void

    private var notchCount: Int { Int((Self.range.upperBound - Self.range.lowerBound) / Self.step) }

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { min(max(NSDecimalNumber(decimal: rate).doubleValue, Self.range.lowerBound), Self.range.upperBound) },
                    set: { newValue in
                        let snapped = (newValue / Self.step).rounded() * Self.step
                        let whole = Decimal(Int(min(max(snapped, Self.range.lowerBound), Self.range.upperBound)))
                        if whole != rate { onChange(whole) }
                    }
                ),
                in: Self.range,
                step: Self.step
            )
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text("\(NSDecimalNumber(decimal: rate).stringValue)%"))

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(0...notchCount, id: \.self) { index in
                        if index == 0 {
                            Image(systemName: "power")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 14)
                                .offset(x: offset(for: index, width: geometry.size.width, markerWidth: 14), y: -3)
                        } else {
                            Capsule(style: .continuous)
                                .fill(palette.textSecondary.opacity(index % 5 == 0 ? 0.6 : 0.35))
                                .frame(width: 2, height: index % 5 == 0 ? 7 : 5)
                                .offset(x: offset(for: index, width: geometry.size.width, markerWidth: 2))
                        }
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
        }
    }

    /// Lines a marker up under the slider thumb's centre for notch `index`.
    private func offset(for index: Int, width: CGFloat, markerWidth: CGFloat) -> CGFloat {
        #if os(macOS)
        let inset: CGFloat = 10
        #else
        let inset: CGFloat = 14
        #endif
        let usable = max(width - inset * 2, 0)
        let position = CGFloat(index) / CGFloat(max(notchCount, 1))
        return inset + position * usable - markerWidth / 2
    }
}
