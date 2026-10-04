//
//  Reminders.swift
//  Mint
//
//  Created by Andy Joe on 10/3/26.
//

import Foundation
import SwiftData

/// What to send reminders about, and when. Stored in user defaults under the `SettingsKey` names.
struct ReminderSettings: Equatable {
    /// Before something unpaid is due, and again the day after if it's still unpaid.
    var dueDates = true
    /// Before the balance is expected to drop below `limitCents`.
    var lowBalance = true
    /// The Overview also warns about a balance below this.
    var limitCents = 0
    /// How many days ahead to remind; 0 means on the day.
    var daysBefore = 1
    /// When reminders arrive, in minutes after midnight.
    var minuteOfDay = 9 * 60

    static let standard = ReminderSettings()

    /// The choices for `daysBefore`.
    static let leadTimes = [0, 1, 2, 3, 7]

    static func title(forDaysBefore days: Int) -> String {
        switch days {
        case 0: "On the day"
        case 1: "1 day before"
        case 7: "1 week before"
        default: "\(days) days before"
        }
    }
}

/// A notification to deliver later: something coming due, something overdue, or a low balance ahead.
struct Reminder: Equatable {
    /// Stable across plans, so a delivered reminder can be recognized and cleared once it no longer applies.
    var id: String
    var date: Date
    var title: String
    var body: String
    /// The entry it's about, so the notification can open it or mark it paid. `nil` (like `kind`)
    /// for a low balance.
    var entryKey: String?
    var kind: EntryKind?

    /// A string that identifies an entry, so a notification can find it later.
    static func key(for id: PersistentIdentifier) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(id).base64EncodedString()) ?? String(describing: id)
    }

    static func entryID(forKey key: String) -> PersistentIdentifier? {
        guard let data = Data(base64Encoded: key) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}

/// Works out every reminder the entries call for. `ReminderCenter` delivers them.
enum ReminderPlanner {
    /// How far ahead to look for a low balance; matches the Overview's chart.
    static let lookAheadDays = 90

    /// Every reminder, soonest first, including past ones. Those aren't sent, but they tell which
    /// delivered notifications still apply.
    static func plan(entries: [LedgerEntry], ledger: Ledger, settings: ReminderSettings) -> [Reminder] {
        var reminders: [Reminder] = []
        if settings.dueDates {
            for entry in entries where ledger.status(of: entry) == .unpaid {
                guard let due = entry.dueDate else { continue }
                reminders += dueReminders(for: entry, due: ledger.day(due), ledger: ledger, settings: settings)
            }
        }
        if settings.lowBalance {
            reminders += lowBalanceReminders(entries, ledger: ledger, settings: settings)
        }
        return reminders.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    private static func dueReminders(for entry: LedgerEntry, due: Date, ledger: Ledger, settings: ReminderSettings) -> [Reminder] {
        let key = Reminder.key(for: entry.id)
        let amount = Money.format(entry.amountCents)
        let remindDay = ledger.addingDays(-settings.daysBefore, to: due)
        let stamp = stamp(due, calendar: ledger.calendar)
        return [
            Reminder(
                id: "due-\(stamp)-\(key)",
                date: time(settings, on: remindDay, calendar: ledger.calendar),
                title: "\(entry.title) is due \(when(due, seenFrom: remindDay, calendar: ledger.calendar))",
                body: entry.category.isEmpty ? amount : "\(amount) · \(entry.category)",
                entryKey: key,
                kind: entry.kind
            ),
            Reminder(
                id: "overdue-\(stamp)-\(key)",
                date: time(settings, on: ledger.addingDays(1, to: due), calendar: ledger.calendar),
                title: "\(entry.title) is overdue",
                body: "\(amount) was due yesterday.",
                entryKey: key,
                kind: entry.kind
            ),
        ]
    }

    /// One for each time the projected balance crosses below the limit.
    private static func lowBalanceReminders(_ entries: [LedgerEntry], ledger: Ledger, settings: ReminderSettings) -> [Reminder] {
        let limit = settings.limitCents
        let points = ledger.dailyBalances(entries, from: ledger.today, through: ledger.addingDays(lookAheadDays, to: ledger.today))
        var previous = ledger.currentBalance(entries)
        var reminders: [Reminder] = []
        for point in points where point.isProjected {
            if point.cents < limit && previous >= limit {
                let remindDay = ledger.addingDays(-settings.daysBefore, to: point.day)
                var body = "Your balance is expected to drop to \(Money.format(point.cents)) \(when(point.day, seenFrom: remindDay, calendar: ledger.calendar))."
                if limit != 0 {
                    body += " That's below your \(Money.format(limit)) limit."
                }
                reminders.append(Reminder(
                    id: "low-balance-\(stamp(point.day, calendar: ledger.calendar))",
                    date: time(settings, on: remindDay, calendar: ledger.calendar),
                    title: "Low balance ahead",
                    body: body
                ))
            }
            previous = point.cents
        }
        return reminders
    }

    /// The reminder time on `day`.
    private static func time(_ settings: ReminderSettings, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: settings.minuteOfDay / 60, minute: settings.minuteOfDay % 60, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(settings.minuteOfDay * 60))
    }

    /// "today", "tomorrow" or "on Friday, Oct 9", relative to `reminderDay`.
    private static func when(_ day: Date, seenFrom reminderDay: Date, calendar: Calendar) -> String {
        switch calendar.dateComponents([.day], from: reminderDay, to: day).day ?? 0 {
        case 0: "today"
        case 1: "tomorrow"
        default: "on " + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    /// "2026-10-09", for identifiers.
    private static func stamp(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
