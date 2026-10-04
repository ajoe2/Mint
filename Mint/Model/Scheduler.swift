//
//  Scheduler.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// Starting, extending, editing, and ending repeating series.
enum Scheduler {
    /// Repeating entries are created this many days ahead.
    static let horizonDays = 365

    static func horizon(from today: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: today)) ?? today
    }

    /// Makes `first` occurrence 0 of a new series and creates the occurrences after it.
    static func startSeries(with first: Entry, frequency: Frequency, endDate: Date?, in context: ModelContext, today: Date, calendar: Calendar = .current) {
        let series = RecurringSeries(frequency: frequency, endDate: endDate, first: first)
        context.insert(series)
        first.series = series
        first.occurrenceIndex = 0
        series.createOccurrences(through: horizon(from: today, calendar: calendar), in: context, calendar: calendar)
    }

    /// Tops up every series to a year ahead. The user didn't do this, so it's kept out of Undo; if
    /// anything is added, Undo history is cleared, since undoing an older step could strand a new occurrence.
    static func extendAll(in context: ModelContext, today: Date, calendar: Calendar = .current) {
        guard let all = try? context.fetch(FetchDescriptor<RecurringSeries>()), !all.isEmpty else { return }
        let undoManager = context.undoManager
        undoManager?.disableUndoRegistration()
        let limit = horizon(from: today, calendar: calendar)
        let created = all.reduce(0) { $0 + $1.createOccurrences(through: limit, in: context, calendar: calendar) }
        try? context.save()
        undoManager?.enableUndoRegistration()
        if created > 0 {
            undoManager?.removeAllActions()
        }
    }

    /// Applies `draft` to `entry` and every later occurrence after today. Occurrences on or before
    /// today stay as they are: paid ones are history, and unpaid ones already came due.
    static func updateThisAndFuture(_ entry: Entry, with draft: EntryDraft, in context: ModelContext, today: Date, calendar: Calendar = .current) {
        guard let series = entry.series else {
            draft.apply(to: entry, calendar: calendar)
            return
        }
        let today = calendar.startOfDay(for: today)
        let pivotPlace = place(of: entry, in: series, calendar: calendar)
        let pivotDay = primaryDay(of: entry, calendar: calendar) ?? today
        let oldDates = (entry.date, entry.dueDate)
        let others = (series.entries ?? []).filter { $0 !== entry }
        let replaced = others.filter { other in
            isUpcoming(other, today: today, calendar: calendar)
                && isLater(other, than: entry, place: pivotPlace, in: series, calendar: calendar)
        }
        let kept = others.filter { other in !replaced.contains { $0 === other } }
        var taken = Set(kept.compactMap { place(of: $0, in: series, calendar: calendar) })
        replaced.forEach(context.delete)

        draft.apply(to: entry, calendar: calendar)
        entry.occurrenceIndex = entry.occurrenceIndex ?? pivotPlace

        guard let frequency = draft.frequency else {
            // Repeating was turned off: this entry stands alone and the series stops here.
            entry.series = nil
            entry.occurrenceIndex = nil
            series.endDate = calendar.date(byAdding: .day, value: -1, to: pivotDay)
            if kept.isEmpty { context.delete(series) }
            return
        }

        let frequencyChanged = frequency != series.frequency
        let datesChanged = entry.date != oldDates.0 || entry.dueDate != oldDates.1
        series.frequency = frequency
        series.endDate = draft.repeatEndDate(calendar: calendar)
        series.copyTemplate(from: entry)

        // New frequency or dates make this occurrence the anchor later ones are measured from.
        // Otherwise the anchor stays, so a series on the 31st keeps the 31st.
        if frequencyChanged || datesChanged || pivotPlace == nil, entry.date != nil || entry.dueDate != nil {
            let index = pivotPlace ?? ((taken.max() ?? -1) + 1)
            series.anchorDate = entry.date
            series.anchorDueDate = entry.dueDate
            series.anchorIndex = index
            entry.occurrenceIndex = index
            if frequencyChanged || pivotPlace == nil {
                // Places under the old rule don't line up with the new one.
                taken = []
                for other in kept where (other.occurrenceIndex ?? .min) > index {
                    other.occurrenceIndex = nil
                }
            }
        }

        series.nextIndex = (entry.occurrenceIndex ?? taken.max() ?? (series.anchorIndex - 1)) + 1
        series.createOccurrences(
            through: horizon(from: today, calendar: calendar),
            skipping: taken,
            after: today,
            in: context,
            calendar: calendar
        )
    }

    /// Deletes `entry` and every later occurrence that isn't paid yet, and ends the series.
    static func deleteThisAndFuture(_ entry: Entry, in context: ModelContext, today: Date, calendar: Calendar = .current) {
        guard let series = entry.series else {
            context.delete(entry)
            return
        }
        let today = calendar.startOfDay(for: today)
        let pivotPlace = place(of: entry, in: series, calendar: calendar)
        let pivotDay = primaryDay(of: entry, calendar: calendar) ?? today
        let all = series.entries ?? []
        let doomed = all.filter { other in
            other === entry
                || (!isPaid(other, today: today, calendar: calendar)
                    && isLater(other, than: entry, place: pivotPlace, in: series, calendar: calendar))
        }
        doomed.forEach(context.delete)
        series.endDate = calendar.date(byAdding: .day, value: -1, to: pivotDay)
        if all.count == doomed.count {
            context.delete(series)
        }
    }

    /// Where `entry` falls in `series`. Older occurrences without a stored place are matched by
    /// date; `nil` if none matches (for example, one that was moved).
    static func place(of entry: Entry, in series: RecurringSeries, calendar: Calendar) -> Int? {
        if let index = entry.occurrenceIndex { return index }
        guard let day = primaryDay(of: entry, calendar: calendar) else { return nil }
        let count = series.entries?.count ?? 0
        return ((series.anchorIndex - count - 1)...(series.nextIndex)).first { index in
            series.occurrence(index, calendar: calendar).primaryDate.map(calendar.startOfDay(for:)) == day
        }
    }

    private static func isLater(_ other: Entry, than entry: Entry, place pivotPlace: Int?, in series: RecurringSeries, calendar: Calendar) -> Bool {
        if let pivotPlace, let otherPlace = place(of: other, in: series, calendar: calendar) {
            return otherPlace > pivotPlace
        }
        guard let day = primaryDay(of: other, calendar: calendar) else { return false }
        guard let pivot = primaryDay(of: entry, calendar: calendar) else { return true }
        return day > pivot
    }

    private static func primaryDay(of entry: Entry, calendar: Calendar) -> Date? {
        (entry.date ?? entry.dueDate).map(calendar.startOfDay(for:))
    }

    private static func isPaid(_ entry: Entry, today: Date, calendar: Calendar) -> Bool {
        guard let date = entry.date else { return false }
        return calendar.startOfDay(for: date) <= today
    }

    /// Not paid yet: its date, or due date if it has none, is after today.
    private static func isUpcoming(_ entry: Entry, today: Date, calendar: Calendar) -> Bool {
        guard let day = primaryDay(of: entry, calendar: calendar) else { return false }
        return day > today
    }
}
