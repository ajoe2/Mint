//
//  StatisticsView.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Charts
import SwiftUI

/// Totals by kind, where the spending went, and money in and out by month.
struct StatisticsView: View {
    let entries: [LedgerEntry]
    let adjustments: [BalanceAdjustment]
    let ledger: Ledger

    @AppStorage(SettingsKey.statsPeriod) private var period: StatsPeriod = .month
    @FocusState private var isFocused: Bool

    private static let tileKinds: [EntryKind] = [.income, .subsidy, .spend, .investment]

    private func kindTile(_ kind: EntryKind, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KindIcon(kind: kind, size: 26)
                Text(kind.pluralTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            MoneyText(cents: cents, size: 24)
                .fixedSize()
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        let range = period.range(today: ledger.today, calendar: ledger.calendar)
        let totals = ledger.totals(entries, in: range)
        let categories = ledger.spendingByCategory(entries, in: range)
        let adjusted = adjustments
            .filter { range?.contains(ledger.day($0.day)) ?? true }
            .compactMap(\.changeCents)
            .reduce(0, +)
        let hasHistory = entries.contains { ledger.status(of: $0) == .paid }

        Page {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    ChoiceBar(
                        label: "Period",
                        choices: StatsPeriod.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $period
                    )
                    Spacer()
                    if hasHistory {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Net")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.secondary)
                            MoneyText(cents: totals.net, size: 26, showPlus: true)
                                .foregroundStyle(Theme.signed(totals.net))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if hasHistory {
                    // One row if it fits, else two by two so big amounts aren't squeezed.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            ForEach(Self.tileKinds) { kind in
                                kindTile(kind, cents: totals[kind])
                            }
                        }
                        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                            GridRow {
                                kindTile(.income, cents: totals[.income])
                                kindTile(.subsidy, cents: totals[.subsidy])
                            }
                            GridRow {
                                kindTile(.spend, cents: totals[.spend])
                                kindTile(.investment, cents: totals[.investment])
                            }
                        }
                    }

                    if adjusted != 0 {
                        Text("Manual adjustments changed your balance by \(Money.format(adjusted, showPlus: true)). They aren't counted as income or spending.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TitledSection("Spending by category") {
                        Group {
                            if categories.isEmpty {
                                Text("No spending in this period.")
                                    .foregroundStyle(.secondary)
                            } else {
                                CategoryBreakdown(categories: categories)
                            }
                        }
                        .card()
                    }

                    TitledSection("Money in and out, last 12 months") {
                        MonthlyChart(months: ledger.monthlyTotals(entries, months: 12))
                            .card()
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Statistics Yet", systemImage: "chart.bar")
                    } description: {
                        Text("Totals appear here once something has been paid or received.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .animation(Motion.standard, value: period)
        }
        // ← and → change the period without tabbing to it first.
        .focusable(interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let periods = StatsPeriod.allCases
            let index = periods.firstIndex(of: period) ?? 0
            withAnimation(Motion.quick) {
                period = periods[min(max(index + (press.key == .leftArrow ? -1 : 1), 0), periods.count - 1)]
            }
            return .handled
        }
        .onAppear { isFocused = true }
    }
}

/// One row per category: name, a bar relative to the largest, amount, and share of the total.
private struct CategoryBreakdown: View {
    let categories: [CategoryTotal]

    var body: some View {
        let largest = Double(max(categories.first?.cents ?? 1, 1))
        let total = Double(max(categories.reduce(0) { $0 + $1.cents }, 1))
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            ForEach(categories, id: \.name) { category in
                GridRow {
                    Label {
                        Text(category.name)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: EntryKind.spend.symbol(forCategory: category.name))
                            .foregroundStyle(EntryKind.spend.color)
                    }
                    Bar(fraction: Double(category.cents) / largest, color: EntryKind.spend.color)
                    Text(Money.format(category.cents))
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Text(Double(category.cents) / total, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

private struct MonthlyChart: View {
    let months: [MonthTotals]

    var body: some View {
        Chart {
            ForEach(months, id: \.month) { month in
                BarMark(
                    x: .value("Month", month.month, unit: .month),
                    y: .value("Amount", Money.chartValue(fromCents: month.totals.moneyIn))
                )
                .foregroundStyle(by: .value("Flow", "Money in"))
                .position(by: .value("Flow", "Money in"))
                .cornerRadius(4)

                BarMark(
                    x: .value("Month", month.month, unit: .month),
                    y: .value("Amount", Money.chartValue(fromCents: month.totals.moneyOut))
                )
                .foregroundStyle(by: .value("Flow", "Money out"))
                .position(by: .value("Flow", "Money out"))
                .cornerRadius(4)
            }
        }
        .chartForegroundStyleScale(["Money in": Color.green, "Money out": EntryKind.spend.color])
        .chartLegend(position: .top, alignment: .trailing)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let dollars = value.as(Double.self) {
                        Text(Money.compact(dollars))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .frame(height: 220)
    }
}
