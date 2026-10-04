//
//  Ledger.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation

/// The fields the ledger math needs. `LedgerEntry` (the plain copy the views use), `Entry` and
/// the tests' `TestItem` conform.
protocol LedgerItem {
    var kind: EntryKind { get }
    var amountCents: Int { get }
    var date: Date? { get }
    var dueDate: Date? { get }
    var category: String { get }
}

extension LedgerItem {
    /// Positive when money comes in, negative when it goes out.
    var signedCents: Int { kind.sign * amountCents }

    /// Sort key by when it happens; entries with no date sort last.
    var sortDate: Date { date ?? dueDate ?? .distantFuture }
}

/// Where an entry stands, worked out from its date alone.
enum EntryStatus: CaseIterable {
    /// No date yet, so nothing's scheduled.
    case unpaid
    /// Dated in the future; counts as paid automatically on that day.
    case scheduled
    /// Dated today or earlier: the money has moved.
    case paid
}

struct BalancePoint: Equatable {
    var day: Date
    var cents: Int
    var isProjected: Bool
}

struct ForecastStep<Item: LedgerItem> {
    var item: Item
    /// The day the money is expected to move.
    var day: Date
    /// The projected balance right after this entry.
    var balanceAfter: Int
}

struct Totals: Equatable {
    var income = 0
    var subsidies = 0
    var spending = 0
    var investments = 0

    subscript(kind: EntryKind) -> Int {
        get {
            switch kind {
            case .income: income
            case .subsidy: subsidies
            case .spend: spending
            case .investment: investments
            }
        }
        set {
            switch kind {
            case .income: income = newValue
            case .subsidy: subsidies = newValue
            case .spend: spending = newValue
            case .investment: investments = newValue
            }
        }
    }

    var moneyIn: Int { income + subsidies }
    var moneyOut: Int { spending + investments }
    var net: Int { moneyIn - moneyOut }
}

struct CategoryTotal: Equatable {
    var name: String
    var cents: Int
}

struct MonthTotals: Equatable {
    var month: Date
    var totals: Totals
}

/// A point the balance counts from: the starting balance or a manual adjustment.
struct BalanceCheckpoint: Equatable {
    var day: Date
    /// The balance at the start of `day`, before that day's entries.
    var baseCents: Int
    /// Breaks ties between checkpoints on the same day; the newer one wins.
    var createdAt: Date = .distantPast
}

/// All balance and statistics math, as plain functions of the entries.
///
/// The balance counts from the newest checkpoint. Paid entries dated before that day are history:
/// they show up in statistics but are already part of the balance that was entered.
struct Ledger: Equatable {
    /// How many days ahead Coming up looks.
    static let comingUpDays = 28
    /// Unpaid entries due within this many days are due soon.
    static let dueSoonDays = 7

    /// Oldest first. Never empty.
    let checkpoints: [BalanceCheckpoint]
    let today: Date
    let calendar: Calendar
    /// The start of tomorrow, and of the day after the due-soon window. Comparing dates against
    /// these is much cheaper than finding the start of each entry's day.
    private let tomorrow: Date
    private let dueSoonEnd: Date

    init(checkpoints: [BalanceCheckpoint], today: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: today)
        let sorted = checkpoints
            .map { BalanceCheckpoint(day: calendar.startOfDay(for: $0.day), baseCents: $0.baseCents, createdAt: $0.createdAt) }
            .sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        self.checkpoints = sorted.isEmpty ? [BalanceCheckpoint(day: today, baseCents: 0)] : sorted
        self.today = today
        self.calendar = calendar
        let nextDay = { (days: Int) in calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: today) ?? today) }
        self.tomorrow = nextDay(1)
        self.dueSoonEnd = nextDay(Self.dueSoonDays + 1)
    }

    /// The checkpoint the current balance counts from.
    var currentCheckpoint: BalanceCheckpoint {
        checkpoints[checkpoints.count - 1]
    }

    /// Paid entries from this day on change the balance; earlier ones are history.
    var balanceStartDay: Date {
        currentCheckpoint.day
    }

    func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The start of the day `days` after `date`. Counts from, and snaps back to, the start of the
    /// day so it works where daylight saving time starts at midnight.
    func addingDays(_ days: Int, to date: Date) -> Date {
        day(calendar.date(byAdding: .day, value: days, to: day(date)) ?? date)
    }

    // MARK: - Status

    func status(of item: some LedgerItem) -> EntryStatus {
        guard let date = item.date else { return .unpaid }
        return date < tomorrow ? .paid : .scheduled
    }

    /// Unpaid, and its due date has passed.
    func isOverdue(_ item: some LedgerItem) -> Bool {
        guard status(of: item) == .unpaid, let due = item.dueDate else { return false }
        return due < today
    }

    /// Unpaid, and due between today and `dueSoonDays` from now.
    func isDueSoon(_ item: some LedgerItem) -> Bool {
        guard status(of: item) == .unpaid, let due = item.dueDate else { return false }
        return due >= today && due < dueSoonEnd
    }

    /// Scheduled for a day after it's due.
    func isScheduledLate(_ item: some LedgerItem) -> Bool {
        guard status(of: item) == .scheduled, let date = item.date, let due = item.dueDate else { return false }
        return day(date) > day(due)
    }

    /// Paid and dated on or after the day the balance counts from.
    func countsTowardBalance(_ item: some LedgerItem) -> Bool {
        guard let date = item.date, date < tomorrow else { return false }
        return date >= balanceStartDay
    }

    /// When a pending entry should move money: its scheduled date, else its due date (or today if
    /// that's passed). `nil` if it's paid or has neither date.
    func expectedDay(of item: some LedgerItem) -> Date? {
        switch status(of: item) {
        case .paid: nil
        case .scheduled: item.date.map(day)
        case .unpaid: item.dueDate.map { max(day($0), today) }
        }
    }

    // MARK: - Balance

    func currentBalance<Item: LedgerItem>(_ items: [Item]) -> Int {
        items.reduce(currentCheckpoint.baseCents) { total, item in
            countsTowardBalance(item) ? total + item.signedCents : total
        }
    }

    /// The actual balance at the end of a past day or today. `nil` for future days and days
    /// before the first checkpoint.
    func actualBalance<Item: LedgerItem>(atEndOf date: Date, _ items: [Item]) -> Int? {
        let target = day(date)
        guard target <= today, target >= checkpoints[0].day else { return nil }
        return dailyBalances(items, from: target, through: target).first { !$0.isProjected }?.cents
    }

    /// The start-of-day balance to store when someone says their balance was `amountCents` on `date`.
    /// Entries already paid that day count as part of that amount.
    func checkpointBase<Item: LedgerItem>(forBalance amountCents: Int, on date: Date, _ items: [Item]) -> Int {
        let target = day(date)
        let paidThatDay = items.reduce(0) { total, item in
            guard status(of: item) == .paid, let date = item.date, day(date) == target else { return total }
            return total + item.signedCents
        }
        return amountCents - paidThatDay
    }

    /// Pending entries in the order they're expected, each with the balance right after it.
    /// Entries with no dates are left out, since there's no telling when they'll happen.
    func forecast<Item: LedgerItem>(_ items: [Item]) -> [ForecastStep<Item>] {
        // Each entry's fields are read once, not on every comparison.
        let pending = items.compactMap { item in
            expectedDay(of: item).map { (item: item, day: $0, isInflow: item.kind.isInflow, cents: item.amountCents, signed: item.signedCents) }
        }
        let ordered = pending.sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            // Same day: money in first, then larger amounts first.
            if a.isInflow != b.isInflow { return a.isInflow }
            return a.cents > b.cents
        }
        var balance = currentBalance(items)
        return ordered.map { step in
            balance += step.signed
            return ForecastStep(item: step.item, day: step.day, balanceAfter: balance)
        }
    }

    /// End-of-day balances from `start` through `end`. Days up to today are actual; days from today
    /// on are projected. Today appears twice: as it is, and with today's pending entries (such as
    /// overdue bills) counted. A checkpoint resets the balance on its day. Days before the first
    /// checkpoint are worked out backward from it.
    func dailyBalances<Item: LedgerItem>(_ items: [Item], from start: Date, through end: Date) -> [BalancePoint] {
        let origin = checkpoints[0].day
        let first = day(start)
        let last = day(end)
        guard first <= last else { return [] }

        // Paid entries before both the range and the first checkpoint never change a shown day.
        let oldestNeeded = min(first, origin)
        var paid: [Date: Int] = [:]
        var pending: [Date: Int] = [:]
        for item in items {
            if status(of: item) == .paid, let date = item.date {
                guard date >= oldestNeeded else { continue }
                paid[day(date), default: 0] += item.signedCents
            } else if let expected = expectedDay(of: item) {
                pending[expected, default: 0] += item.signedCents
            }
        }
        // Checkpoints are oldest first, so the newest one on a day wins.
        var baseByDay: [Date: Int] = [:]
        for checkpoint in checkpoints {
            baseByDay[checkpoint.day] = checkpoint.baseCents
        }

        var points: [BalancePoint] = []

        // Before the first checkpoint: its opening balance is the previous day's closing balance,
        // and each earlier day's closing balance subtracts what was paid the day after.
        if first < origin {
            var earlier: [BalancePoint] = []
            var balance = checkpoints[0].baseCents
            var current = addingDays(-1, to: origin)
            while current >= first {
                if current <= min(last, today) {
                    earlier.append(BalancePoint(day: current, cents: balance, isProjected: false))
                }
                balance -= paid[current] ?? 0
                current = addingDays(-1, to: current)
            }
            points += earlier.reversed()
        }

        var balance = 0
        var current = origin
        while current <= min(last, today) {
            if let base = baseByDay[current] {
                balance = base
            }
            balance += paid[current] ?? 0
            if current >= first {
                points.append(BalancePoint(day: current, cents: balance, isProjected: false))
            }
            current = addingDays(1, to: current)
        }

        let projectionStart = max(first, today)
        // When the range starts after today, entries expected before it still count.
        var projected = currentBalance(items) + pending.filter { $0.key < projectionStart }.values.reduce(0, +)
        current = projectionStart
        while current <= last {
            projected += pending[current] ?? 0
            points.append(BalancePoint(day: current, cents: projected, isProjected: true))
            current = addingDays(1, to: current)
        }
        return points
    }

    /// The lowest projected balance among `points`, from today on, and the first day it happens.
    func lowestBalance(in points: [BalancePoint]) -> BalancePoint? {
        points.filter { $0.isProjected && $0.day >= today }.min { $0.cents < $1.cents }
    }

    // MARK: - Statistics

    /// Totals of paid entries, optionally limited to a range of days.
    func totals<Item: LedgerItem>(_ items: [Item], in range: ClosedRange<Date>? = nil) -> Totals {
        let span = range.map(span(of:))
        var totals = Totals()
        for item in items where status(of: item) == .paid {
            guard let date = item.date else { continue }
            if let span, !span.contains(date) { continue }
            totals[item.kind] += item.amountCents
        }
        return totals
    }

    /// Totals of pending entries expected within a range of days.
    func pendingTotals<Item: LedgerItem>(_ items: [Item], in range: ClosedRange<Date>? = nil) -> Totals {
        var totals = Totals()
        for item in items {
            guard let expected = expectedDay(of: item) else { continue }
            if let range, !range.contains(expected) { continue }
            totals[item.kind] += item.amountCents
        }
        return totals
    }

    /// Paid spending by category, largest first. Categories differing only in capitalization are
    /// merged under the first spelling seen; blank ones go under "Uncategorized".
    func spendingByCategory<Item: LedgerItem>(_ items: [Item], in range: ClosedRange<Date>? = nil) -> [CategoryTotal] {
        let span = range.map(span(of:))
        var totals: [String: CategoryTotal] = [:]
        for item in items where item.kind == .spend && status(of: item) == .paid {
            guard let date = item.date else { continue }
            if let span, !span.contains(date) { continue }
            let trimmed = item.category.trimmingCharacters(in: .whitespaces)
            let name = trimmed.isEmpty ? "Uncategorized" : trimmed
            totals[name.lowercased(), default: CategoryTotal(name: name, cents: 0)].cents += item.amountCents
        }
        return totals.values.sorted { $0.cents != $1.cents ? $0.cents > $1.cents : $0.name < $1.name }
    }

    /// Paid totals for each of the last `count` months, oldest first, ending with this month.
    func monthlyTotals<Item: LedgerItem>(_ items: [Item], months count: Int) -> [MonthTotals] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: today)?.start else { return [] }
        let months = (0..<max(count, 0)).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        guard let first = months.first else { return [] }
        var byMonth = Array(repeating: Totals(), count: months.count)
        for item in items where status(of: item) == .paid {
            // Months are oldest first, so the entry's month is the last one starting on or before it.
            guard let date = item.date, date >= first,
                  let index = months.lastIndex(where: { $0 <= date })
            else { continue }
            byMonth[index][item.kind] += item.amountCents
        }
        return zip(months, byMonth).map { MonthTotals(month: $0, totals: $1) }
    }

    /// The instants a range of days covers, from the start of its first day to the start of the
    /// day after its last.
    private func span(of range: ClosedRange<Date>) -> Range<Date> {
        let start = day(range.lowerBound)
        return start..<max(addingDays(1, to: range.upperBound), start)
    }
}

/// The time span the statistics screen covers.
enum StatsPeriod: String, CaseIterable, Identifiable {
    case month
    case year
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "This Month"
        case .year: "This Year"
        case .allTime: "All Time"
        }
    }

    /// The days in this period, or `nil` for all time.
    func range(today: Date, calendar: Calendar) -> ClosedRange<Date>? {
        switch self {
        case .month: Self.dayRange(of: .month, containing: today, calendar: calendar)
        case .year: Self.dayRange(of: .year, containing: today, calendar: calendar)
        case .allTime: nil
        }
    }

    /// First day through last day of the month or year containing `date`.
    private static func dayRange(of component: Calendar.Component, containing date: Date, calendar: Calendar) -> ClosedRange<Date>? {
        guard let interval = calendar.dateInterval(of: component, for: date),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return nil }
        return interval.start...calendar.startOfDay(for: lastDay)
    }
}
