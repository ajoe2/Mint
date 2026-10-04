//
//  BalanceAdjustmentTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData
import Testing
@testable import Mint

/// Today is Oct 15, 2026. The starting balance is $1,000 as of Oct 1.
@MainActor
struct BalanceAdjustmentTests {
    let today = day(2026, 10, 15)
    let start = BalanceCheckpoint(day: day(2026, 10, 1), baseCents: 1_000_00)

    let paycheck = TestItem(kind: .income, amountCents: 2_000_00, date: day(2026, 10, 2))
    let groceries = TestItem(kind: .spend, amountCents: 100_00, date: day(2026, 10, 10))
    let coffee = TestItem(kind: .spend, amountCents: 5_00, date: day(2026, 10, 15))
    let rent = TestItem(kind: .spend, amountCents: 1_500_00, date: day(2026, 11, 1))
    let phone = TestItem(kind: .spend, amountCents: 60_00, date: nil, dueDate: day(2026, 10, 18))

    var items: [TestItem] { [paycheck, groceries, coffee, rent, phone] }

    /// What the Adjust Balance sheet stores when the bank shows `cents` on `date`.
    private func adjust(to cents: Int, on date: Date, items: [TestItem], createdAt: Date = .now) -> Ledger {
        let before = Ledger(checkpoints: [start], today: today)
        let base = before.checkpointBase(forBalance: cents, on: date, items)
        return Ledger(checkpoints: [start, BalanceCheckpoint(day: date, baseCents: base, createdAt: createdAt)], today: today)
    }

    @Test func adjustingTodaySetsTheBalance() {
        #expect(Ledger(checkpoints: [start], today: today).currentBalance(items) == 2_895_00)
        // The bank already reflects today's coffee.
        let ledger = adjust(to: 2_850_00, on: today, items: items)
        #expect(ledger.currentBalance(items) == 2_850_00)
        #expect(ledger.balanceStartDay == today)
    }

    @Test func laterEntriesChangeTheAdjustedBalance() {
        let ledger = adjust(to: 2_850_00, on: today, items: items)

        // Added after adjusting, dated today.
        let lunch = TestItem(kind: .spend, amountCents: 20_00, date: today)
        #expect(ledger.currentBalance(items + [lunch]) == 2_830_00)

        // Phone bill paid today, after adjusting.
        var paidPhone = phone
        paidPhone.date = today
        #expect(ledger.currentBalance([paycheck, groceries, coffee, rent, paidPhone]) == 2_790_00)

        // Projections start from the adjusted balance.
        #expect(ledger.projectedBalance(on: day(2026, 11, 30), items) == 2_850_00 - 60_00 - 1_500_00)
    }

    @Test func entriesBeforeTheAdjustmentAreHistory() {
        let ledger = adjust(to: 2_850_00, on: today, items: items)
        let forgotten = TestItem(kind: .spend, amountCents: 30_00, date: day(2026, 10, 12))
        #expect(!ledger.countsTowardBalance(forgotten))
        #expect(ledger.currentBalance(items + [forgotten]) == 2_850_00)
        // Statistics still count it: groceries, coffee, and the forgotten $30.
        #expect(ledger.totals(items + [forgotten]).spending == 135_00)
    }

    @Test func adjustingAPastDayKeepsLaterEntries() {
        // The bank says $2,950 at the end of Oct 10, after groceries.
        let ledger = adjust(to: 2_950_00, on: day(2026, 10, 10), items: items)
        #expect(ledger.actualBalance(atEndOf: day(2026, 10, 10), items) == 2_950_00)
        // Today's $5 coffee still comes off.
        #expect(ledger.currentBalance(items) == 2_945_00)
    }

    @Test func chartResetsOnTheAdjustmentDay() {
        let ledger = adjust(to: 2_850_00, on: today, items: items)
        let actual = ledger.dailyBalances(items, from: day(2026, 10, 1), through: today).filter { !$0.isProjected }
        #expect(actual.first { $0.day == day(2026, 10, 1) }?.cents == 1_000_00)
        #expect(actual.first { $0.day == day(2026, 10, 14) }?.cents == 2_900_00)
        #expect(actual.first { $0.day == today }?.cents == 2_850_00)
    }

    @Test func newestAdjustmentOnTheSameDayWins() {
        let earlier = BalanceCheckpoint(day: today, baseCents: 500_00, createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let later = BalanceCheckpoint(day: today, baseCents: 700_00, createdAt: Date(timeIntervalSinceReferenceDate: 200))
        let ledger = Ledger(checkpoints: [later, start, earlier], today: today)
        #expect(ledger.currentCheckpoint == later)
        #expect(ledger.currentBalance([coffee]) == 695_00)
    }

    @Test func noBalanceBeforeTheFirstCheckpoint() {
        let ledger = Ledger(checkpoints: [start], today: today)
        #expect(ledger.actualBalance(atEndOf: day(2026, 9, 15), items) == nil)
        #expect(ledger.actualBalance(atEndOf: day(2026, 10, 1), items) == 1_000_00)
    }
}

@MainActor
struct BalanceAdjustmentStoreTests {
    let context: ModelContext
    let today = day(2026, 10, 15)

    init() throws {
        context = try makeContext()
    }

    private func adjustments() throws -> [BalanceAdjustment] {
        try context.save()
        return try context.fetch(FetchDescriptor<BalanceAdjustment>(sortBy: [SortDescriptor(\.day)]))
    }

    @Test func adjustingAnEarlierDayReplacesLaterBalances() throws {
        let start = BalanceAdjustment(day: day(2026, 10, 10), amountCents: 1_000_00, baseCents: 1_000_00)
        context.insert(start)
        let entries = [
            Entry(kind: .spend, title: "Shoes", amountCents: 100_00, date: day(2026, 10, 5)),
            Entry(kind: .income, title: "Paycheck", amountCents: 500_00, date: day(2026, 10, 12)),
        ]
        entries.forEach(context.insert)
        try context.save()
        let before = Ledger(checkpoints: [start.checkpoint], today: today)
        #expect(before.currentBalance(entries) == 1_500_00)

        let earlier = BalanceAdjustment.record(2_000_00, on: day(2026, 10, 1), replacing: [start], entries: entries, ledger: before, in: context)

        let remaining = try adjustments()
        #expect(remaining.count == 1)
        #expect(earlier.isStartingBalance)
        let after = Ledger(checkpoints: remaining.map(\.checkpoint), today: today)
        // $2,000 on Oct 1, then the shoes and the paycheck after it.
        #expect(after.currentBalance(entries) == 2_400_00)
    }

    @Test func adjustingTheSameDayAgainReplacesIt() throws {
        context.insert(BalanceAdjustment(day: day(2026, 10, 1), amountCents: 1_000_00, baseCents: 1_000_00))

        func adjust(to cents: Int) throws -> [BalanceAdjustment] {
            let existing = try adjustments()
            let ledger = Ledger(checkpoints: existing.map(\.checkpoint), today: today)
            // The recorded previous balance matches what the sheet showed.
            let previous = BalanceAdjustment.previousCents(on: day(2026, 10, 10), keeping: existing, entries: [], ledger: ledger)
            let recorded = BalanceAdjustment.record(cents, on: day(2026, 10, 10), replacing: existing, entries: [], ledger: ledger, in: context)
            #expect(recorded.previousCents == previous)
            return try adjustments()
        }

        let first = try adjust(to: 900_00)
        #expect(first.map(\.amountCents) == [1_000_00, 900_00])
        #expect(first.last?.changeCents == -100_00)

        let second = try adjust(to: 950_00)
        #expect(second.map(\.amountCents) == [1_000_00, 950_00])
        #expect(second.last?.changeCents == -50_00)
    }

    @Test func deletingTheStartingBalanceMakesTheNextOneTheStart() throws {
        let start = BalanceAdjustment(day: day(2026, 10, 1), amountCents: 1_000_00, baseCents: 1_000_00)
        let adjustment = BalanceAdjustment(day: day(2026, 10, 10), amountCents: 900_00, baseCents: 900_00, previousCents: 1_000_00)
        context.insert(start)
        context.insert(adjustment)

        BalanceAdjustment.delete(start, from: [start, adjustment], in: context)

        let remaining = try adjustments()
        #expect(remaining.count == 1)
        #expect(remaining.first?.isStartingBalance == true)
        #expect(remaining.first?.title == "Starting balance")
    }

    @Test func startingBalanceIsNotUndoable() throws {
        let undoManager = UndoManager()
        context.undoManager = undoManager
        BalanceAdjustment.setStartingBalance(1_234_00, on: today, in: context)
        #expect(!undoManager.canUndo)
        #expect(try adjustments().map(\.amountCents) == [1_234_00])
    }
}

@MainActor
struct AppResetTests {
    @Test func erasesAllDataAndSettings() throws {
        let context = try makeContext()
        let suite = "com.ajoe.Mint.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("year", forKey: SettingsKey.statsPeriod)
        defaults.set(500_00, forKey: SettingsKey.lowBalanceLimit)

        let today = day(2026, 10, 15)
        context.insert(BalanceAdjustment(day: today, amountCents: 100_00, baseCents: 100_00))
        let rent = Entry(kind: .spend, title: "Rent", amountCents: 1_500_00, date: day(2026, 11, 1))
        context.insert(rent)
        Scheduler.startSeries(with: rent, frequency: .monthly, endDate: nil, in: context, today: today)
        try context.save()

        AppReset.eraseAll(in: context, defaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecurringSeries>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BalanceAdjustment>()) == 0)
        for key in SettingsKey.all {
            #expect(defaults.object(forKey: key) == nil, "\(key)")
        }
    }
}
