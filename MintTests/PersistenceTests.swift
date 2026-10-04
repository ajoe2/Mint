//
//  PersistenceTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData
import Testing
@testable import Mint

/// Changes must reach disk right away, not on autosave. Each test makes a change, then
/// reopens the store the way a relaunch would.
///
/// A class, so `deinit` can delete each test's store when it finishes.
@MainActor
final class PersistenceTests {
    let schema = Schema([Entry.self, RecurringSeries.self, BalanceAdjustment.self])
    /// Holds the store and the files SQLite keeps beside it.
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container: ModelContainer
    let ledger = Ledger(startingBalanceCents: 0, startDate: day(2026, 10, 1), today: day(2026, 10, 15))

    var url: URL { folder.appending(path: "Mint.store") }

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: folder.appending(path: "Mint.store")))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private var actions: EntryActions {
        EntryActions(context: container.mainContext, app: AppModel(), ledger: ledger)
    }

    /// What a relaunched app would find on disk.
    private func entriesOnDisk() throws -> [Entry] {
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        return try ModelContext(reopened).fetch(FetchDescriptor<Entry>())
    }

    @Test func saveNowWritesImmediately() throws {
        container.mainContext.insert(Entry(kind: .spend, title: "Lunch", amountCents: 12_00, date: day(2026, 10, 15)))
        #expect(try entriesOnDisk().isEmpty)
        container.mainContext.saveNow()
        #expect(try entriesOnDisk().map(\.title) == ["Lunch"])
    }

    @Test func markingPaidIsSavedRightAway() throws {
        let bill = Entry(kind: .spend, title: "Phone", amountCents: 65_00, date: nil, dueDate: day(2026, 10, 18))
        container.mainContext.insert(bill)
        container.mainContext.saveNow()

        actions.complete(bill)
        #expect(try entriesOnDisk().first?.date == day(2026, 10, 15))

        actions.uncomplete(bill)
        #expect(try entriesOnDisk().first?.date == nil)
    }

    @Test func deletingIsSavedRightAway() throws {
        let lunch = Entry(kind: .spend, title: "Lunch", amountCents: 12_00, date: day(2026, 10, 15))
        container.mainContext.insert(lunch)
        container.mainContext.saveNow()

        actions.delete(lunch)
        #expect(try entriesOnDisk().isEmpty)
    }

    @Test func deletingFutureRepeatsIsSavedRightAway() throws {
        let rent = Entry(kind: .spend, title: "Rent", amountCents: 1_500_00, date: day(2026, 11, 1))
        container.mainContext.insert(rent)
        Scheduler.startSeries(with: rent, frequency: .monthly, endDate: nil, in: container.mainContext, today: ledger.today)
        container.mainContext.saveNow()
        #expect(try entriesOnDisk().count == 12)

        actions.deleteThisAndFuture(rent)
        #expect(try entriesOnDisk().isEmpty)
    }
}
