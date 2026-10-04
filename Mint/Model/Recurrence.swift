//
//  Recurrence.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation

/// How often a repeating entry happens.
enum Frequency: String, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 Weeks"
        case .monthly: "Monthly"
        case .quarterly: "Every 3 Months"
        case .yearly: "Yearly"
        }
    }

    /// The date `occurrences` repeats after `date` (before it, when negative).
    ///
    /// Pass the series' anchor, not the previous occurrence, so a series starting Jan 31 lands
    /// on Feb 28 and then back on Mar 31.
    func date(advancing date: Date, by occurrences: Int, calendar: Calendar) -> Date? {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: 7 * occurrences, to: date)
        case .biweekly: calendar.date(byAdding: .day, value: 14 * occurrences, to: date)
        case .monthly: calendar.date(byAdding: .month, value: occurrences, to: date)
        case .quarterly: calendar.date(byAdding: .month, value: 3 * occurrences, to: date)
        case .yearly: calendar.date(byAdding: .year, value: occurrences, to: date)
        }
    }
}

/// The dates of one occurrence in a repeating series.
struct Occurrence: Equatable {
    var index: Int
    var date: Date?
    var dueDate: Date?

    var primaryDate: Date? { date ?? dueDate }
}

enum Recurrence {
    /// The dates of occurrence `index`, when occurrence `anchorIndex` falls on the anchor dates.
    ///
    /// The date and due date each move on their own, so "paid on the 10th, due on the 15th"
    /// holds every month.
    static func occurrence(
        _ index: Int,
        frequency: Frequency,
        anchorDate: Date?,
        anchorDueDate: Date?,
        anchorIndex: Int = 0,
        calendar: Calendar
    ) -> Occurrence {
        let steps = index - anchorIndex
        return Occurrence(
            index: index,
            date: anchorDate.flatMap { frequency.date(advancing: $0, by: steps, calendar: calendar) },
            dueDate: anchorDueDate.flatMap { frequency.date(advancing: $0, by: steps, calendar: calendar) }
        )
    }

    /// Occurrences from `startIndex` through `limit`, or through `endDate` if that's earlier.
    static func occurrences(
        frequency: Frequency,
        anchorDate: Date?,
        anchorDueDate: Date?,
        anchorIndex: Int = 0,
        endDate: Date?,
        startingAt startIndex: Int,
        through limit: Date,
        calendar: Calendar
    ) -> [Occurrence] {
        let lastDay = calendar.startOfDay(for: min(limit, endDate ?? limit))
        var results: [Occurrence] = []
        var index = startIndex

        // Safety cap; a weekly series over the one-year horizon needs about 53.
        while results.count < 1_000 {
            let next = occurrence(
                index, frequency: frequency, anchorDate: anchorDate, anchorDueDate: anchorDueDate,
                anchorIndex: anchorIndex, calendar: calendar
            )
            guard let primary = next.primaryDate, calendar.startOfDay(for: primary) <= lastDay else { break }
            results.append(next)
            index += 1
        }
        return results
    }
}
