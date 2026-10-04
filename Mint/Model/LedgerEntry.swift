//
//  LedgerEntry.swift
//  Mint
//
//  Created by Andy Joe on 10/3/26.
//

import Foundation
import SwiftData

/// A plain copy of an entry's fields, made each time the entries change. Reading a SwiftData
/// property is many times slower than reading a plain one, and the math reads each entry's fields
/// many times per screen, so it works on these copies instead.
struct LedgerEntry: LedgerItem, Equatable {
    /// The entry itself, for showing and changing it.
    let entry: Entry
    let kind: EntryKind
    let amountCents: Int
    let date: Date?
    let dueDate: Date?
    let title: String
    let category: String
    let notes: String
    let createdAt: Date

    init(_ entry: Entry) {
        self.entry = entry
        kind = entry.kind
        amountCents = entry.amountCents
        date = entry.date
        dueDate = entry.dueDate
        title = entry.title
        category = entry.category
        notes = entry.notes
        createdAt = entry.createdAt
    }

    var id: PersistentIdentifier { entry.persistentModelID }

    /// Sort key by when it happens; entries with no date sort last.
    var sortDate: Date { date ?? dueDate ?? .distantFuture }
}
