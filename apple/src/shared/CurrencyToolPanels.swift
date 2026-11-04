import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    @Environment(\.paneTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        #if os(macOS)
        // Content lines up with the keypad: 8pt in from the window's sides and
        // 10pt up from its bottom, the same as the rounding pane.
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        #else
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
        #endif
    }

    /// Laid out like the rounding pane's header: the title centred in the
    /// secondary colour, the trash (take the result back off the display and
    /// close) at the leading edge, and the close button at the trailing edge.
    private var header: some View {
        ZStack {
            Text(title)
                #if os(macOS)
                .paneAppFont(size: 15)
                #else
                .paneAppFont(size: 13)
                #endif
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                // Leaves room for the trash and close buttons on either side.
                .padding(.horizontal, headerButtonTarget)

            HStack(spacing: 0) {
                headerButton(symbol: "trash", label: removeLabel, isHovering: trashHoverBinding, action: onRemove)
                Spacer(minLength: 0)
                headerButton(symbol: "xmark", label: closeLabel, isHovering: closeHoverBinding, action: onDismiss)
            }
        }
        .frame(minHeight: headerButtonTarget)
    }

    /// The header's buttons: 32pt on the Mac and 44pt on iOS at the standard
    /// size, growing with the text but never below that (#152).
    private var headerButtonTarget: CGFloat {
        #if os(macOS)
        PaneTextScale.grown(32, by: textScale)
        #else
        PaneTextScale.grown(44, by: textScale)
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
        let iconSize = PaneTextScale.grown(16, by: textScale)
        Button(action: action) {
            Image(systemName: symbol)
                .paneFont(size: 13)
                .frame(width: iconSize, height: iconSize, alignment: .center)
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
        let iconSize = PaneTextScale.grown(28, by: textScale)
        Button(action: action) {
            Image(systemName: symbol)
                .paneAppFont(size: 18)
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: headerButtonTarget, height: headerButtonTarget, alignment: .center)
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
    /// Reuses the calculator's own error messages for a rate that can't be used.
    public let invalidInput: String
    public let outOfRange: String

    public init(localized: (String) -> String) {
        typeRate = localized("currency.rate.type")
        editPreset = localized("currency.rate.editPreset")
        presetHint = localized("currency.rate.presetHint")
        done = localized("currency.rate.done")
        cancel = localized("currency.rate.cancel")
        invalidInput = localized("error.invalidInput")
        outOfRange = localized("error.outOfRange")
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
    /// The preset whose press-and-hold just opened the editor, so the release
    /// that ends the hold isn't also taken as a tap.
    @State private var heldSlot: Int?
    /// Shown after Done when the typed rate can't be used.
    @State private var rateError: String?

    var body: some View {
        choosingView
            .background(
                Color.clear
                    .alert(rateError ?? "", isPresented: Binding(
                        get: { rateError != nil },
                        set: { if !$0 { rateError = nil } }
                    )) {
                        Button(labels.done, role: .cancel) { rateError = nil }
                    }
            )
            .alert(alertTitle, isPresented: isEditingBinding) {
                // The current rate as the placeholder, with a % sign so it reads
                // as a percentage; the person types just the number.
                TextField("\(RateEntry.displayText(for: editor.entry.value ?? 0, decimalSeparator: decimalSeparator))%", text: $typedText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Button(labels.cancel, role: .cancel) { editor.cancel() }

                Button(labels.done) { commitTypedText() }
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

    /// Applies the alert's text. An empty field keeps the rate it opened on.
    /// Text that can't be used changes nothing and says why, with the
    /// calculator's own messages: Out of range at 1000% or more, Invalid input
    /// for anything that isn't a number.
    private func commitTypedText() {
        let text = typedText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || editor.setTypedText(text, decimalSeparator: decimalSeparator, notifyingLive: false) {
            editor.press(.done)
            return
        }
        let message = RateEntry.isOutOfRange(text, decimalSeparator: decimalSeparator)
            ? labels.outOfRange
            : labels.invalidInput
        editor.cancel()
        // Let the edit alert finish dismissing before presenting the error.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            rateError = message
        }
    }

    /// The presets and the rate stepper share one row; the stepper's value is
    /// the rate in use, so it needs no label of its own. When larger text
    /// leaves the row too narrow for both (#152), the stepper moves onto a
    /// row of its own below the presets.
    private var choosingView: some View {
        ViewThatFits(in: .horizontal) {
            // ViewThatFits measures each layout at its natural width, so this
            // one is used only when every label fits at full size.
            HStack(spacing: 6) {
                presetButtons

                if showsStepper {
                    stepper
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) { presetButtons }
                if showsStepper { stepper }
            }
        }
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach(Array(rates.enumerated()), id: \.offset) { slot, rate in
            presetButton(slot: slot, rate: rate)
        }
    }

    private var stepper: some View {
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
    }

    /// A real `Button`, so it can be focused and pressed from a keyboard (Tab and
    /// Space on Mac, Full Keyboard Access on iPad) and by VoiceOver. Press and
    /// hold opens the editor; the press that ends that hold doesn't also pick
    /// the preset.
    private func presetButton(slot: Int, rate: Decimal) -> some View {
        let isSelected = pressedSlot.map { $0 == slot } ?? (rate == selected)
        return Button {
            if heldSlot == slot {
                heldSlot = nil
                return
            }
            choose(slot: slot, rate: rate)
        } label: {
            Text("\(format(rate))%")
                .paneFont(size: 13, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? palette.accentText : palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(palette.accentGradient) : AnyShapeStyle(palette.buttonFunction))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                heldSlot = slot
                beginEditingPreset(slot)
            }
        )
        .accessibilityLabel(Text("\(format(rate))%"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(Text(labels.presetHint))
        .accessibilityAction(named: Text(labels.editPreset)) { beginEditingPreset(slot) }
    }

    private func choose(slot: Int, rate: Decimal) {
        onPresetChosen?(slot)
        onSelect(rate)
    }

    private func beginTypingRate() {
        typedText = ""
        editor.begin(
            .rate,
            value: selected,
            onLive: { _ in },
            onCommit: onSelect,
            onCancel: {}
        )
    }

    private func beginEditingPreset(_ slot: Int) {
        guard rates.indices.contains(slot) else { return }
        typedText = ""
        editor.begin(
            .preset(slot),
            value: rates[slot],
            onLive: { _ in },
            onCommit: { rate in
                onPresetEdited(slot, rate)
                onPresetChosen?(slot)
                onSelect(rate)
            },
            onCancel: {}
        )
    }
}

/// Minus / value / plus, used for the VAT rate.
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
    @Environment(\.paneTextScale) private var textScale

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
            .paneFont(size: 14, weight: .medium)
            .foregroundStyle(palette.textPrimary)
            .frame(minWidth: PaneTextScale.grown(56, by: textScale))
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
                .paneFont(size: 12, weight: .semibold)
                .foregroundStyle(palette.textPrimary)
                .frame(width: PaneTextScale.grown(34, by: textScale), height: PaneTextScale.grown(30, by: textScale))
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
                .paneFont(size: 13)
                .foregroundStyle(palette.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .paneFont(size: isEmphasised ? 17 : 14, weight: isEmphasised ? .semibold : .regular)
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
        // Applied on open and whenever the rate or direction changes — not when
        // the amount underneath changes, so the pane never re-applies over
        // something the person has since typed. Keyed on the rate rather than
        // the result, so a rate change that rounds to the same figure still
        // updates the operation line.
        .onAppear(perform: sendResult)
        .onChange(of: ApplyKey(rate: rate, isRemoving: isRemoving)) { _, _ in sendResult() }
    }

    private struct ApplyKey: Equatable {
        let rate: Decimal
        let isRemoving: Bool
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
        // Both buttons take the taller one's height when a label wraps.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func directionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .paneFont(size: 13, weight: .medium)
                .foregroundStyle(isSelected ? palette.accentText : palette.textPrimary)
                // Long translations wrap rather than truncate at large sizes.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(palette.accentGradient) : AnyShapeStyle(palette.buttonFunction))
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
                    offLabel: localized("currency.tip.off"),
                    palette: palette,
                    formatRate: formatRate,
                    onChange: { newRate in
                        pressedPreset = nil
                        onRateChange(newRate)
                    }
                )
            }
        }
        // Applied as soon as the panel opens, and again on every change.
        .onAppear {
            // A preset is shown as chosen only after it is pressed in this
            // presentation of the pane, never just because its value matches.
            pressedPreset = nil
            // Opening at 0% (Off) applies nothing and clears nothing.
            if rate != 0 { sendResult() }
        }
        // Applied whenever the rate changes, not when the bill changes, so the
        // pane never re-applies over something the person has since typed.
        .onChange(of: rate) { _, _ in sendResult() }
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
    let offLabel: String
    let palette: Palette
    let formatRate: (Decimal) -> String
    let onChange: (Decimal) -> Void
    @Environment(\.paneTextScale) private var textScale

    private var markerRowHeight: CGFloat { PaneTextScale.grown(14, by: textScale) }
    private var offMarkerWidth: CGFloat { PaneTextScale.grown(14, by: textScale) }

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
            .tint(palette.sliderTint)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(rate == 0 ? offLabel : "\(formatRate(rate))%"))

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(0...notchCount, id: \.self) { index in
                        // Drawn exactly like the rounding pane's markers: the
                        // same power icon and the same 2×5 ticks, in the same
                        // colours, on each platform.
                        if index == 0 {
                            Image(systemName: "power")
                                #if os(macOS)
                                .paneFont(size: NSFont.smallSystemFontSize)
                                .foregroundStyle(.secondary)
                                #else
                                .paneAppFont(size: 12)
                                .foregroundStyle(palette.textSecondary)
                                #endif
                                .frame(width: offMarkerWidth)
                                .offset(x: offset(for: index, width: geometry.size.width, markerWidth: offMarkerWidth), y: -3)
                        } else {
                            Capsule(style: .continuous)
                                #if os(macOS)
                                .fill(Color.secondary.opacity(0.35))
                                #else
                                .fill(palette.textSecondary.opacity(0.35))
                                #endif
                                .frame(width: 2, height: 5)
                                .offset(x: offset(for: index, width: geometry.size.width, markerWidth: 2))
                        }
                    }
                }
            }
            .frame(height: markerRowHeight)
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
