//
//  Entry.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// A single spend, income, investment, or subsidy.
@Model
final class Entry {
    var kindRaw: String = EntryKind.spend.rawValue
    var title: String = ""
    /// Always positive; the kind decides the direction.
    var amountCents: Int = 0
    /// When the money moves: today or earlier is paid, later is scheduled, `nil` is unpaid.
    var date: Date?
    /// Deadline, if any.
    var dueDate: Date?
    var category: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    /// Set when this entry is an occurrence of a repeating series.
    var series: RecurringSeries?
    /// Position in its series (0 is the first). `nil` for one-offs and for occurrences made before
    /// this was stored.
    var occurrenceIndex: Int?

    init(
        kind: EntryKind,
        title: String,
        amountCents: Int,
        date: Date?,
        dueDate: Date? = nil,
        category: String = "",
        notes: String = ""
    ) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.amountCents = amountCents
        self.date = date
        self.dueDate = dueDate
        self.category = category
        self.notes = notes
        self.createdAt = .now
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .spend }
        set { kindRaw = newValue.rawValue }
    }

    var isRepeating: Bool { series != nil }

    /// Sort key by when it happens; entries with no date sort last.
    var sortDate: Date { date ?? dueDate ?? .distantFuture }
}

extension Entry: LedgerItem {}
