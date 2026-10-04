//
//  RecurringSeries.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// The rule behind a repeating entry. Occurrences are ordinary entries created up to a year ahead,
/// so they show up in Coming up and the projected balance like everything else.
@Model
final class RecurringSeries {
    var frequencyRaw: String = Frequency.monthly.rawValue
    /// Dates of occurrence `anchorIndex`; other occurrences are counted from these.
    var anchorDate: Date?
    var anchorDueDate: Date?
    var anchorIndex: Int = 0
    /// No occurrences after this day.
    var endDate: Date?
    /// Index of the next occurrence not yet created.
    var nextIndex: Int = 1

    // Copied into each new occurrence.
    var kindRaw: String = EntryKind.spend.rawValue
    var title: String = ""
    var amountCents: Int = 0
    var category: String = ""
    var notes: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Entry.series)
    var entries: [Entry]? = []

    init(frequency: Frequency, endDate: Date?, first: Entry) {
        self.frequencyRaw = frequency.rawValue
        self.endDate = endDate
        self.anchorDate = first.date
        self.anchorDueDate = first.dueDate
        self.anchorIndex = 0
        self.nextIndex = 1
        copyTemplate(from: first)
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    func copyTemplate(from entry: Entry) {
        kindRaw = entry.kindRaw
        title = entry.title
        amountCents = entry.amountCents
        category = entry.category
        notes = entry.notes
    }

    /// The dates occurrence `index` falls on under the current rule.
    func occurrence(_ index: Int, calendar: Calendar = .current) -> Occurrence {
        Recurrence.occurrence(
            index, frequency: frequency, anchorDate: anchorDate, anchorDueDate: anchorDueDate,
            anchorIndex: anchorIndex, calendar: calendar
        )
    }

    /// Creates occurrences from `nextIndex` through `limit` (and the end date, if any), skipping
    /// indexes in `taken` and anything on or before `earliest`. Skipped ones still advance
    /// `nextIndex`. Returns how many were created.
    @discardableResult
    func createOccurrences(
        through limit: Date,
        skipping taken: Set<Int> = [],
        after earliest: Date? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Int {
        let upcoming = Recurrence.occurrences(
            frequency: frequency,
            anchorDate: anchorDate,
            anchorDueDate: anchorDueDate,
            anchorIndex: anchorIndex,
            endDate: endDate,
            startingAt: nextIndex,
            through: limit,
            calendar: calendar
        )
        var created = 0
        for occurrence in upcoming {
            nextIndex = occurrence.index + 1
            if taken.contains(occurrence.index) { continue }
            if let earliest, let primary = occurrence.primaryDate, calendar.startOfDay(for: primary) <= earliest { continue }
            let entry = Entry(
                kind: EntryKind(rawValue: kindRaw) ?? .spend,
                title: title,
                amountCents: amountCents,
                date: occurrence.date,
                dueDate: occurrence.dueDate,
                category: category,
                notes: notes
            )
            entry.occurrenceIndex = occurrence.index
            context.insert(entry)
            entry.series = self
            created += 1
        }
        return created
    }
}
