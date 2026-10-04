//
//  OverviewView.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftData
import SwiftUI

/// The home screen: how much you have, where it's heading, and what's coming up.
struct OverviewView: View {
    let entries: [Entry]
    let ledger: Ledger

    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.lowBalanceLimit) private var lowBalanceLimit = ReminderSettings.standard.limitCents
    @State private var selection = RowSelection()

    /// Days the chart shows before and after today.
    private static let chartDaysBack = 30
    private static let chartDaysAhead = 90

    var body: some View {
        let today = ledger.today
        let balance = ledger.currentBalance(entries)
        let points = ledger.dailyBalances(
            entries,
            from: ledger.addingDays(-Self.chartDaysBack, to: today),
            through: ledger.addingDays(Self.chartDaysAhead, to: today)
        )
        let comingUpEnd = ledger.addingDays(Ledger.comingUpDays, to: today)
        let inFourWeeks = points.last { $0.isProjected && $0.day <= comingUpEnd }?.cents ?? balance
        let lowest = ledger.lowestBalance(in: points) ?? BalancePoint(day: today, cents: balance, isProjected: false)
        let forecast = ledger.forecast(entries)
        // Overdue entries get their own section. Everything else expected in the next four weeks,
        // scheduled or just due, goes in Coming up with the balance after it.
        let overdue = forecast.map(\.item).filter(ledger.isOverdue)
        let comingUp = forecast.filter { !ledger.isOverdue($0.item) && $0.day <= comingUpEnd }

        Page {
            VStack(spacing: 20) {
                BalancePanel(
                    balance: balance,
                    inFourWeeks: inFourWeeks,
                    lowest: lowest,
                    isLow: lowest.cents < lowBalanceLimit,
                    points: points,
                    ledger: ledger,
                    onAdjust: { app.isAdjustingBalance = true }
                )

                if lowest.cents < lowBalanceLimit {
                    Label {
                        Text(lowBalanceWarning(lowest))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
                }

                if !overdue.isEmpty {
                    OverdueSection(entries: overdue, ledger: ledger)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        comingUpSection(comingUp)
                        ThisMonthCard(entries: entries, ledger: ledger)
                            .frame(width: 340)
                    }
                    VStack(spacing: 20) {
                        comingUpSection(comingUp)
                        ThisMonthCard(entries: entries, ledger: ledger)
                    }
                }
            }
        }
        .keyboardRows(overdue + comingUp.map(\.item), selection: selection, ledger: ledger)
    }

    /// "Your balance is projected to drop to $320.00 on Oct 14, 2026, below your $500.00 limit."
    private func lowBalanceWarning(_ lowest: BalancePoint) -> String {
        var text = "Your balance is projected to drop to \(Money.format(lowest.cents)) on \(DayText.full(lowest.day))"
        if lowBalanceLimit != 0 {
            text += ", below your \(Money.format(lowBalanceLimit)) limit"
        }
        return text + "."
    }

    private func comingUpSection(_ steps: [ForecastStep<Entry>]) -> some View {
        TitledSection("Coming up") {
            Button("See all") { app.selection = .transactions }
                .buttonStyle(.link)
        } content: {
            if steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nothing in the next four weeks.")
                        .foregroundStyle(.secondary)
                    if entries.isEmpty {
                        Text("Add your paycheck and regular bills to see where your balance is heading.")
                        HStack {
                            Button("Add Income") { app.editor = .new(.income) }
                            Button("Add a Bill") { app.editor = .new(.spend) }
                        }
                        .buttonBorderShape(.capsule)
                    }
                }
                .card()
            } else {
                RowCard(items: steps, id: \.item.persistentModelID) { step in
                    EntryRowView(entry: step.item, ledger: ledger, balanceAfter: step.balanceAfter)
                }
            }
        }
        .frame(minWidth: 420)
    }
}

/// Unpaid entries past their due date, each with a button to mark it paid or received.
struct OverdueSection: View {
    let entries: [Entry]
    let ledger: Ledger

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        TitledSection("Overdue", tint: Theme.unpaidText) {
            if entries.count > 1 {
                Text(Money.format(entries.reduce(0) { $0 + $1.signedCents }, showPlus: true))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } content: {
            RowCard(items: entries, id: \.persistentModelID) { entry in
                EntryRowView(entry: entry, ledger: ledger) {
                    Button("Mark \(entry.kind.completedLabel)") {
                        EntryActions(context: context, app: app, ledger: ledger).complete(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help(EntryActions.completeTitle(for: entry.kind))
                }
            }
        }
    }
}

/// The balance, where it's heading, and a slim chart.
private struct BalancePanel: View {
    let balance: Int
    let inFourWeeks: Int
    let lowest: BalancePoint
    /// The lowest balance ahead is below the limit set in Settings.
    let isLow: Bool
    let points: [BalancePoint]
    let ledger: Ledger
    let onAdjust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Balance")
                            .foregroundStyle(.secondary)
                        Button("Adjust…", action: onAdjust)
                            .buttonStyle(.link)
                            .help("Set your balance to what your bank shows (⇧⌘B)")
                    }
                    .font(.subheadline.weight(.medium))
                    MoneyText(cents: balance, size: 38)
                        .foregroundStyle(balance < 0 ? Theme.unpaidText : Color.primary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Stat(
                    title: "In 4 weeks",
                    value: Money.format(inFourWeeks),
                    detail: inFourWeeks == balance ? "No change" : Money.format(inFourWeeks - balance, showPlus: true)
                )
                Stat(
                    title: "Lowest ahead",
                    value: Money.format(lowest.cents),
                    detail: DayText.short(lowest.day, today: ledger.today, calendar: ledger.calendar),
                    isWarning: isLow
                )
            }

            // Mark the low point only if it's below today's balance.
            BalanceChart(points: points, today: ledger.today, lowest: lowest.cents < balance ? lowest : nil)
                .frame(height: 130)
        }
        .card()
    }

    private struct Stat: View {
        let title: String
        let value: String
        let detail: String
        var isWarning = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isWarning ? Theme.unpaidText : Color.primary)
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// This month so far, what's still expected before it ends, and the top spending categories.
private struct ThisMonthCard: View {
    let entries: [Entry]
    let ledger: Ledger

    var body: some View {
        let month = StatsPeriod.month.range(today: ledger.today, calendar: ledger.calendar)
        let paid = ledger.totals(entries, in: month)
        let pending = ledger.pendingTotals(entries, in: month.map { ledger.today...$0.upperBound })
        let monthEnd = paid.net + pending.net
        let largest = Double(max(paid.moneyIn + pending.moneyIn, paid.moneyOut + pending.moneyOut, 1))
        let categories = Array(ledger.spendingByCategory(entries, in: month).prefix(4))

        TitledSection("This month") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("By month end")
                            .foregroundStyle(.secondary)
                        Spacer()
                        MoneyText(cents: monthEnd, size: 22, showPlus: true)
                            .foregroundStyle(Theme.signed(monthEnd))
                    }
                    Text("So far \(Money.format(paid.net, showPlus: true))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)

                BarRow(
                    title: "In",
                    detail: flow(paid.moneyIn, pending.moneyIn, "expected"),
                    fraction: Double(paid.moneyIn) / largest,
                    pending: Double(pending.moneyIn) / largest,
                    color: .green
                )
                BarRow(
                    title: "Out",
                    detail: flow(paid.moneyOut, pending.moneyOut, "to go"),
                    fraction: Double(paid.moneyOut) / largest,
                    pending: Double(pending.moneyOut) / largest,
                    color: EntryKind.spend.color
                )

                if !categories.isEmpty {
                    Divider()
                    let top = Double(max(categories[0].cents, 1))
                    VStack(spacing: 10) {
                        ForEach(categories, id: \.name) { category in
                            BarRow(
                                title: category.name,
                                symbol: EntryKind.spend.symbol(forCategory: category.name),
                                detail: Money.format(category.cents),
                                fraction: Double(category.cents) / top,
                                color: EntryKind.spend.color
                            )
                        }
                    }
                }
            }
            .card()
        }
    }

    /// "$1,650.00 · $1,269.39 to go", or just the amount when nothing more is expected.
    private func flow(_ paid: Int, _ pending: Int, _ pendingWords: String) -> String {
        pending == 0 ? Money.format(paid) : "\(Money.format(paid)) · \(Money.format(pending)) \(pendingWords)"
    }
}
