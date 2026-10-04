//
//  TransactionsView.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftData
import SwiftUI

/// A paid entry or balance adjustment in the month-by-month history.
enum HistoryItem: Identifiable {
    case entry(Entry)
    case adjustment(BalanceAdjustment)

    var id: PersistentIdentifier {
        switch self {
        case .entry(let entry): entry.persistentModelID
        case .adjustment(let adjustment): adjustment.persistentModelID
        }
    }

    var day: Date {
        switch self {
        case .entry(let entry): entry.sortDate
        case .adjustment(let adjustment): adjustment.day
        }
    }

    var createdAt: Date {
        switch self {
        case .entry(let entry): entry.createdAt
        case .adjustment(let adjustment): adjustment.createdAt
        }
    }

    var entry: Entry? {
        if case .entry(let entry) = self { entry } else { nil }
    }
}

/// Every transaction in one list: overdue, coming up, no date, then what already happened.
struct TransactionsView: View {
    let entries: [Entry]
    let adjustments: [BalanceAdjustment]
    let ledger: Ledger

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var showsLater = false
    @State private var selection = RowSelection()

    private var query: String {
        app.searchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        @Bindable var app = app
        let forecast = ledger.forecast(entries)
        let overdue = forecast.map(\.item).filter { ledger.isOverdue($0) && matches($0) }
        let upcoming = forecast.filter { !ledger.isOverdue($0.item) && matches($0.item) }
        let comingUpEnd = ledger.addingDays(Ledger.comingUpDays, to: ledger.today)
        let comingUp = upcoming.filter { $0.day <= comingUpEnd }
        let later = upcoming.filter { $0.day > comingUpEnd }
        // Running balances only add up when every entry is listed.
        let showsBalance = app.transactionFilter == .all && query.isEmpty
        let undated = entries
            .filter { ledger.status(of: $0) == .unpaid && $0.dueDate == nil && matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
        let months = historyByMonth()
        let isEmpty = overdue.isEmpty && upcoming.isEmpty && undated.isEmpty && months.isEmpty
        // Entry rows in display order, for keyboard navigation.
        let rows = overdue + comingUp.map(\.item) + (showsLater ? later.map(\.item) : [])
            + undated + months.flatMap { $0.items.compactMap(\.entry) }

        Page {
            LazyVStack(alignment: .leading, spacing: 26) {
                ChoiceBar(
                    label: "Show",
                    choices: TransactionFilter.allCases.map { .init(value: $0, title: $0.title) },
                    selection: $app.transactionFilter
                )

                if entries.isEmpty && query.isEmpty && app.transactionFilter != .adjustments {
                    ContentUnavailableView {
                        Label("No Transactions", systemImage: "tray")
                    } description: {
                        Text("Add what you spend, earn, invest, or receive, and it shows up here.")
                    } actions: {
                        Button("Add Entry") { app.editor = .new(app.newEntryKind) }
                    }
                    .frame(maxWidth: .infinity)
                } else if isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text(query.isEmpty ? "Nothing to show here yet." : "Nothing matches “\(query)”.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }

                if !overdue.isEmpty {
                    OverdueSection(entries: overdue, ledger: ledger)
                }

                if !upcoming.isEmpty {
                    TitledSection("Coming up") {
                        if comingUp.isEmpty {
                            Text("Nothing in the next four weeks.")
                                .foregroundStyle(.secondary)
                                .card(padding: 16)
                        } else {
                            upcomingRows(comingUp, showsBalance: showsBalance)
                        }
                        if !later.isEmpty && !showsLater {
                            Button("Show \(later.count) later") { showsLater = true }
                                .buttonStyle(.link)
                        }
                    }
                }

                if showsLater {
                    ForEach(laterByMonth(later), id: \.month) { group in
                        TitledSection(laterTitle(group.month)) {
                            Text(Money.format(group.steps.reduce(0) { $0 + $1.item.signedCents }, showPlus: true))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } content: {
                            upcomingRows(group.steps, showsBalance: showsBalance)
                        }
                    }
                }

                if !undated.isEmpty {
                    TitledSection("No date") {
                        RowCard(items: undated, id: \.persistentModelID) { entry in
                            EntryRowView(entry: entry, ledger: ledger)
                        }
                    }
                }

                ForEach(months, id: \.month) { group in
                    TitledSection(DayText.month(group.month)) {
                        if let net = monthNet(group.items) {
                            Text(net)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } content: {
                        RowCard(items: group.items, id: \.id) { item in
                            switch item {
                            case .entry(let entry):
                                EntryRowView(entry: entry, ledger: ledger)
                            case .adjustment(let adjustment):
                                AdjustmentRowView(adjustment: adjustment, today: ledger.today)
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            BalanceAdjustment.delete(adjustment, from: adjustments, in: context)
                                        }
                                        .disabled(adjustments.count <= 1)
                                    }
                            }
                        }
                    }
                }
            }
        }
        .keyboardRows(rows, selection: selection, ledger: ledger) { step in
            let filters = TransactionFilter.allCases
            let index = filters.firstIndex(of: app.transactionFilter) ?? 0
            withAnimation(.snappy(duration: 0.25)) {
                app.transactionFilter = filters[min(max(index + step, 0), filters.count - 1)]
            }
        }
    }

    private func upcomingRows(_ steps: [ForecastStep<Entry>], showsBalance: Bool) -> some View {
        RowCard(items: steps, id: \.item.persistentModelID) { step in
            EntryRowView(entry: step.item, ledger: ledger, balanceAfter: showsBalance ? step.balanceAfter : nil)
        }
    }

    private func matches(_ entry: Entry) -> Bool {
        switch app.transactionFilter {
        case .adjustments: return false
        case .kind(let kind) where entry.kind != kind: return false
        default: break
        }
        return query.isEmpty
            || entry.title.localizedStandardContains(query)
            || entry.category.localizedStandardContains(query)
            || entry.notes.localizedStandardContains(query)
    }

    private func matches(_ adjustment: BalanceAdjustment) -> Bool {
        guard app.transactionFilter == .all || app.transactionFilter == .adjustments else { return false }
        return query.isEmpty || adjustment.title.localizedStandardContains(query)
    }

    /// "Later in October" for the rest of this month, then "November 2026" and so on.
    private func laterTitle(_ month: Date) -> String {
        guard ledger.calendar.isDate(month, equalTo: ledger.today, toGranularity: .month) else { return DayText.month(month) }
        return "Later in \(month.formatted(.dateTime.month(.wide)))"
    }

    /// Groups upcoming items past the next four weeks by month. Expects them in date order.
    private func laterByMonth(_ steps: [ForecastStep<Entry>]) -> [(month: Date, steps: [ForecastStep<Entry>])] {
        var groups: [(month: Date, steps: [ForecastStep<Entry>])] = []
        for step in steps {
            if let last = groups.last, ledger.calendar.isDate(step.day, equalTo: last.month, toGranularity: .month) {
                groups[groups.count - 1].steps.append(step)
            } else {
                groups.append((ledger.calendar.dateInterval(of: .month, for: step.day)?.start ?? step.day, [step]))
            }
        }
        return groups
    }

    /// Paid entries and adjustments, newest first, grouped by month.
    private func historyByMonth() -> [(month: Date, items: [HistoryItem])] {
        let items = entries.filter { ledger.status(of: $0) == .paid && matches($0) }.map(HistoryItem.entry)
            + adjustments.filter(matches).map(HistoryItem.adjustment)
        // Compute each day once, not in every comparison.
        let sorted = items
            .map { (item: $0, day: ledger.day($0.day), createdAt: $0.createdAt) }
            .sorted { $0.day != $1.day ? $0.day > $1.day : $0.createdAt > $1.createdAt }
        var groups: [(month: Date, items: [HistoryItem])] = []
        for (item, day, _) in sorted {
            if let last = groups.last, day >= last.month {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((ledger.calendar.dateInterval(of: .month, for: day)?.start ?? day, [item]))
            }
        }
        return groups
    }

    /// A month's net, like "+$1,200.00", counting entries but not adjustments. `nil` if no entries.
    private func monthNet(_ items: [HistoryItem]) -> String? {
        let paid = items.compactMap(\.entry)
        guard !paid.isEmpty else { return nil }
        return Money.format(paid.reduce(0) { $0 + $1.signedCents }, showPlus: true)
    }
}
