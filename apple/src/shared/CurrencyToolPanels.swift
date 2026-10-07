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
    let palette: Palette
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    #if os(macOS)
    @State private var isCloseHovering = false
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
    /// secondary colour, and the close button at the trailing edge.
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
                Spacer(minLength: 0)
                closeButton
            }
        }
        #if os(macOS)
        .frame(height: 32)
        #else
        .frame(height: 44)
        #endif
    }

    @ViewBuilder
    private var closeButton: some View {
        #if os(macOS)
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .frame(width: 16, height: 16, alignment: .center)
                .padding(8)
                .background(isCloseHovering ? palette.headerHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(closeLabel)
        .accessibilityLabel(Text(closeLabel))
        .onHover { isCloseHovering = $0 }
        #else
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(EnterCalcFont.appFont(size: 18))
                .frame(width: 28, height: 28)
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: 44, height: 44, alignment: .center)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel(Text(closeLabel))
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

    private func presetButton(slot: Int, rate: Decimal) -> some View {
        let isSelected = rate == selected
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
            .onTapGesture { onSelect(rate) }
            .onLongPressGesture(minimumDuration: 0.45) { beginEditingPreset(slot) }
            .accessibilityElement()
            .accessibilityLabel(Text("\(format(rate))%"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityHint(Text(labels.presetHint))
            .accessibilityAction { onSelect(rate) }
            .accessibilityAction(named: Text(labels.editPreset)) { beginEditingPreset(slot) }
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
            palette: palette,
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

/// Bill, tip percentage and party size, with the tip, total and each share
/// shown together (#92).
public struct CurrencyTipPanel: View {
    private let bill: Decimal
    private let rate: Decimal
    private let presets: RatePresets
    private let splitCount: Int
    private let palette: Palette
    private let localized: (String) -> String
    private let format: (Decimal) -> String
    private let formatRate: (Decimal) -> String
    private let onRateChange: (Decimal) -> Void
    @ObservedObject private var rateEditor: RateEditor
    private let onPresetEdited: (Int, Decimal?) -> Void
    private let onSplitChange: (Int) -> Void
    private let onResult: (Decimal) -> Void
    private let onDismiss: () -> Void

    public init(
        bill: Decimal,
        rate: Decimal,
        presets: RatePresets,
        splitCount: Int,
        palette: Palette,
        localized: @escaping (String) -> String,
        format: @escaping (Decimal) -> String,
        formatRate: @escaping (Decimal) -> String,
        onRateChange: @escaping (Decimal) -> Void,
        rateEditor: RateEditor,
        onPresetEdited: @escaping (Int, Decimal?) -> Void,
        onSplitChange: @escaping (Int) -> Void,
        onResult: @escaping (Decimal) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.bill = bill
        self.rate = rate
        self.presets = presets
        self.splitCount = splitCount
        self.palette = palette
        self.localized = localized
        self.format = format
        self.formatRate = formatRate
        self.onRateChange = onRateChange
        self.rateEditor = rateEditor
        self.onPresetEdited = onPresetEdited
        self.onSplitChange = onSplitChange
        self.onResult = onResult
        self.onDismiss = onDismiss
    }

    private var breakdown: TipBreakdown {
        TipBreakdown(bill: bill, rate: rate, splitCount: splitCount)
    }

    public var body: some View {
        CurrencyToolChrome(
            title: localized("currency.tip.title"),
            closeLabel: localized("currency.tool.close"),
            palette: palette,
            onDismiss: onDismiss
        ) {
            VStack(spacing: 12) {
                RateChooser(
                    rates: presets.rates,
                    selected: rate,
                    stepLabel: localized("currency.tip.rate"),
                    decreaseLabel: localized("currency.tip.rate.decrease"),
                    increaseLabel: localized("currency.tip.rate.increase"),
                    labels: RateEditingLabels(localized: localized),
                    decimalSeparator: presets.decimalSeparator,
                    palette: palette,
                    format: formatRate,
                    editor: rateEditor,
                    onSelect: { onRateChange(max($0, 0)) },
                    onPresetEdited: onPresetEdited
                )

                HStack(spacing: 10) {
                    Text(localized("currency.tip.split"))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)

                    Spacer(minLength: 8)

                    StepperControl(
                        value: "\(breakdown.splitCount)",
                        decreaseLabel: localized("currency.tip.split.decrease"),
                        increaseLabel: localized("currency.tip.split.increase"),
                        palette: palette,
                        onDecrease: { onSplitChange(splitCount - 1) },
                        onIncrease: { onSplitChange(splitCount + 1) }
                    )
                }

                VStack(spacing: 6) {
                    ResultRow(label: localized("currency.tip.amount"), value: format(breakdown.tip), isEmphasised: false, palette: palette)
                    ResultRow(label: localized("currency.tip.total"), value: format(breakdown.total), isEmphasised: breakdown.splitCount == 1, palette: palette)
                    // Only meaningful once the bill is actually split.
                    if breakdown.splitCount > 1 {
                        ResultRow(label: localized("currency.tip.perPerson"), value: format(breakdown.perPerson), isEmphasised: true, palette: palette)
                    }
                }
            }
        }
        // Applied as soon as the panel opens, and again on every change.
        .onAppear(perform: sendResult)
        .onChange(of: breakdown.total) { _, _ in sendResult() }
    }

    private func sendResult() {
        guard bill != 0 else { return }
        onResult(breakdown.total)
    }
}
