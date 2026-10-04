//
//  EntryDraft.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation

/// The editor's working copy of an entry, applied on Save.
struct EntryDraft: Equatable {
    var kind: EntryKind
    var title = ""
    var amountText = ""
    var category = ""
    /// New entries start unpaid, with no date.
    var hasDate = false
    var date: Date
    var hasDueDate = false
    var dueDate: Date
    var notes = ""
    /// `nil` means the entry doesn't repeat.
    var frequency: Frequency?
    var hasEndDate = false
    var endDate: Date

    init(kind: EntryKind, today: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: today)
        self.kind = kind
        self.date = day
        self.dueDate = day
        self.endDate = calendar.date(byAdding: .year, value: 1, to: day) ?? day
    }

    init(entry: Entry, today: Date, calendar: Calendar = .current) {
        self.init(kind: entry.kind, today: today, calendar: calendar)
        title = entry.title
        amountText = Money.editingText(fromCents: entry.amountCents)
        category = entry.category
        notes = entry.notes
        if let date = entry.date {
            hasDate = true
            self.date = date
        }
        if let due = entry.dueDate {
            hasDueDate = true
            dueDate = due
        }
        if let series = entry.series {
            frequency = series.frequency
            if let end = series.endDate {
                hasEndDate = true
                endDate = end
            }
        }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var amountCents: Int? {
        Money.parseCents(amountText)
    }

    /// Repeating needs at least one date to repeat from.
    var canRepeat: Bool {
        hasDate || hasDueDate
    }

    /// The date a repeat counts from: the payment date, else the due date.
    var repeatStart: Date? {
        hasDate ? date : hasDueDate ? dueDate : nil
    }

    var isValid: Bool {
        !trimmedTitle.isEmpty && (amountCents ?? 0) > 0
    }

    func repeatEndDate(calendar: Calendar = .current) -> Date? {
        frequency != nil && hasEndDate ? calendar.startOfDay(for: endDate) : nil
    }

    func hasSameRepeatRule(as other: EntryDraft) -> Bool {
        frequency == other.frequency
            && repeatEndDate() == other.repeatEndDate()
    }

    func status(today: Date, calendar: Calendar = .current) -> EntryStatus {
        guard hasDate else { return .unpaid }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: today) ? .paid : .scheduled
    }

    /// Switches the status, moving the date only if it no longer fits (paid can't be in the
    /// future; scheduled can't be today or earlier).
    mutating func setStatus(_ status: EntryStatus, today: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: today)
        switch status {
        case .paid:
            hasDate = true
            if calendar.startOfDay(for: date) > today { date = today }
        case .scheduled:
            hasDate = true
            if calendar.startOfDay(for: date) <= today {
                date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: today) ?? today)
            }
        case .unpaid:
            hasDate = false
        }
    }

    /// The date and due date to store on `entry`. Unchanged dates keep their exact stored value, so
    /// saving in another time zone can't shift the day.
    func storedDates(for entry: Entry, calendar: Calendar = .current) -> (date: Date?, dueDate: Date?) {
        func stored(_ value: Date, was old: Date?) -> Date {
            value == old ? value : calendar.startOfDay(for: value)
        }
        return (
            hasDate ? stored(date, was: entry.date) : nil,
            hasDueDate ? stored(dueDate, was: entry.dueDate) : nil
        )
    }

    func apply(to entry: Entry, calendar: Calendar = .current) {
        let dates = storedDates(for: entry, calendar: calendar)
        entry.kind = kind
        entry.title = trimmedTitle
        entry.amountCents = amountCents ?? entry.amountCents
        entry.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.date = dates.date
        entry.dueDate = dates.dueDate
    }

    func makeEntry(calendar: Calendar = .current) -> Entry {
        let entry = Entry(kind: kind, title: "", amountCents: 0, date: nil)
        apply(to: entry, calendar: calendar)
        return entry
    }
}
