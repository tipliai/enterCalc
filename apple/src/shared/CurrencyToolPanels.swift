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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(closeLabel))
            }

            content
        }
        .padding(16)
    }
}

/// A row of quick-choice rates plus a stepper for anything not on the list.
///
/// A stepper rather than a text field: a keyboard over a calculator is
/// awkward, and the rates that are not preset — 19, 21, 23 — are all a tap or
/// two from one that is.
private struct RateChooser: View {
    let rates: [Decimal]
    let selected: Decimal
    let stepLabel: String
    let decreaseLabel: String
    let increaseLabel: String
    let palette: Palette
    let format: (Decimal) -> String
    let onSelect: (Decimal) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        onSelect(rate)
                    } label: {
                        Text("\(format(rate))%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(rate == selected ? palette.accentText : palette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(rate == selected ? palette.accent : palette.buttonFunction)
                    )
                    .accessibilityAddTraits(rate == selected ? [.isSelected] : [])
                }
            }

            HStack(spacing: 10) {
                Text(stepLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)

                Spacer(minLength: 8)

                StepperControl(
                    value: "\(format(selected))%",
                    decreaseLabel: decreaseLabel,
                    increaseLabel: increaseLabel,
                    palette: palette,
                    onDecrease: { onSelect(selected - 1) },
                    onIncrease: { onSelect(selected + 1) }
                )
            }
        }
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

    var body: some View {
        HStack(spacing: 0) {
            button("minus", label: decreaseLabel, action: onDecrease)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 56)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            button("plus", label: increaseLabel, action: onIncrease)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.buttonFunction)
        )
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
    private let isRemoving: Bool
    private let palette: Palette
    private let localized: (String) -> String
    private let format: (Decimal) -> String
    private let formatRate: (Decimal) -> String
    private let onRateChange: (Decimal) -> Void
    private let onDirectionChange: (Bool) -> Void
    private let onApply: (Decimal) -> Void
    private let onDismiss: () -> Void

    public init(
        value: Decimal,
        rate: Decimal,
        isRemoving: Bool,
        palette: Palette,
        localized: @escaping (String) -> String,
        format: @escaping (Decimal) -> String,
        formatRate: @escaping (Decimal) -> String,
        onRateChange: @escaping (Decimal) -> Void,
        onDirectionChange: @escaping (Bool) -> Void,
        onApply: @escaping (Decimal) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.value = value
        self.rate = rate
        self.isRemoving = isRemoving
        self.palette = palette
        self.localized = localized
        self.format = format
        self.formatRate = formatRate
        self.onRateChange = onRateChange
        self.onDirectionChange = onDirectionChange
        self.onApply = onApply
        self.onDismiss = onDismiss
    }

    private var breakdown: VATBreakdown? {
        isRemoving
            ? VATCalculation.removing(rate: rate, fromGross: value)
            : VATCalculation.adding(rate: rate, toNet: value)
    }

    public var body: some View {
        CurrencyToolChrome(
            title: localized("currency.vat.title"),
            closeLabel: localized("currency.tool.close"),
            palette: palette,
            onDismiss: onDismiss
        ) {
            VStack(spacing: 12) {
                directionPicker

                RateChooser(
                    rates: VATCalculation.presetRates,
                    selected: rate,
                    stepLabel: localized("currency.vat.rate"),
                    decreaseLabel: localized("currency.vat.rate.decrease"),
                    increaseLabel: localized("currency.vat.rate.increase"),
                    palette: palette,
                    format: formatRate,
                    onSelect: { onRateChange(max($0, 0)) }
                )

                if let breakdown {
                    VStack(spacing: 6) {
                        ResultRow(label: localized("currency.vat.net"), value: format(breakdown.net), isEmphasised: isRemoving, palette: palette)
                        ResultRow(label: localized("currency.vat.amount"), value: format(breakdown.vat), isEmphasised: false, palette: palette)
                        ResultRow(label: localized("currency.vat.gross"), value: format(breakdown.gross), isEmphasised: !isRemoving, palette: palette)
                    }

                    applyButton(for: isRemoving ? breakdown.net : breakdown.gross)
                }
            }
        }
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

    private func applyButton(for result: Decimal) -> some View {
        Button { onApply(result) } label: {
            Text(localized("currency.tool.use"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.accent)
        )
    }
}

// MARK: - Tip

/// Bill, tip percentage and party size, with the tip, total and each share
/// shown together (#92).
public struct CurrencyTipPanel: View {
    private let bill: Decimal
    private let rate: Decimal
    private let splitCount: Int
    private let palette: Palette
    private let localized: (String) -> String
    private let format: (Decimal) -> String
    private let formatRate: (Decimal) -> String
    private let onRateChange: (Decimal) -> Void
    private let onSplitChange: (Int) -> Void
    private let onApply: (Decimal) -> Void
    private let onDismiss: () -> Void

    public init(
        bill: Decimal,
        rate: Decimal,
        splitCount: Int,
        palette: Palette,
        localized: @escaping (String) -> String,
        format: @escaping (Decimal) -> String,
        formatRate: @escaping (Decimal) -> String,
        onRateChange: @escaping (Decimal) -> Void,
        onSplitChange: @escaping (Int) -> Void,
        onApply: @escaping (Decimal) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.bill = bill
        self.rate = rate
        self.splitCount = splitCount
        self.palette = palette
        self.localized = localized
        self.format = format
        self.formatRate = formatRate
        self.onRateChange = onRateChange
        self.onSplitChange = onSplitChange
        self.onApply = onApply
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
                ResultRow(label: localized("currency.tip.bill"), value: format(breakdown.bill), isEmphasised: false, palette: palette)

                RateChooser(
                    rates: TipBreakdown.presetRates,
                    selected: rate,
                    stepLabel: localized("currency.tip.rate"),
                    decreaseLabel: localized("currency.tip.rate.decrease"),
                    increaseLabel: localized("currency.tip.rate.increase"),
                    palette: palette,
                    format: formatRate,
                    onSelect: { onRateChange(max($0, 0)) }
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

                Button { onApply(breakdown.total) } label: {
                    Text(localized("currency.tool.use"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.accent)
                )
            }
        }
    }
}
