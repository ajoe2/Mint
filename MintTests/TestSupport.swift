//
//  TestSupport.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData
@testable import Mint

/// A plain stand-in for `Entry` when testing the ledger math.
struct TestItem: LedgerItem {
    var kind: EntryKind
    var amountCents: Int
    var date: Date?
    var dueDate: Date? = nil
    var category: String = ""
}

/// Midnight at the start of the given day in the current calendar.
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
}

/// A fresh, empty in-memory store with every model.
@MainActor
func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Entry.self, RecurringSeries.self, BalanceAdjustment.self,
        configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

/// An empty settings suite for one test. Each test passes its own name, and the name stays the
/// same between runs, so they reuse one file instead of leaving a new one behind every time.
func testDefaults(_ name: String) -> UserDefaults {
    let suite = "com.ajoe.Mint.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

extension Ledger {
    /// A ledger with just a starting balance.
    init(startingBalanceCents: Int, startDate: Date, today: Date, calendar: Calendar = .current) {
        self.init(checkpoints: [BalanceCheckpoint(day: startDate, baseCents: startingBalanceCents)], today: today, calendar: calendar)
    }
}
