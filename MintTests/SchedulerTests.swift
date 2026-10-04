//
//  SchedulerTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData
import Testing
@testable import Mint

/// Repeating series in a real in-memory store. Today is Oct 15, 2026, so occurrences run
/// through Oct 15, 2027.
@MainActor
struct SchedulerTests {
    let context: ModelContext
    let today = day(2026, 10, 15)

    init() throws {
        context = try makeContext()
    }

    private func entries() throws -> [Entry] {
        try context.save()
        return try context.fetch(FetchDescriptor<Entry>()).sorted { $0.sortDate < $1.sortDate }
    }

    private func seriesCount() throws -> Int {
        try context.save()
        return try context.fetchCount(FetchDescriptor<RecurringSeries>())
    }

    @discardableResult
    private func monthlyRent(from date: Date) -> Entry {
        let rent = Entry(kind: .spend, title: "Rent", amountCents: 1_500_00, date: date, category: "Housing")
        context.insert(rent)
        Scheduler.startSeries(with: rent, frequency: .monthly, endDate: nil, in: context, today: today)
        return rent
    }

    private func occurrence(on date: Date) throws -> Entry {
        try #require(try entries().first { $0.date == date })
    }

    private func saveForFuture(_ entry: Entry, _ change: (inout EntryDraft) -> Void) {
        var draft = EntryDraft(entry: entry, today: today)
        change(&draft)
        Scheduler.updateThisAndFuture(entry, with: draft, in: context, today: today)
    }

    @Test func startingASeriesFillsAYearAhead() throws {
        monthlyRent(from: day(2026, 9, 1))
        let all = try entries()
        #expect(all.count == 14)
        #expect(all.first?.date == day(2026, 9, 1))
        #expect(all.last?.date == day(2027, 10, 1))
        #expect(all.allSatisfy { $0.series != nil && $0.amountCents == 1_500_00 && $0.category == "Housing" })
    }

    @Test func extendingAgainDoesNotDuplicate() throws {
        monthlyRent(from: day(2026, 9, 1))
        Scheduler.extendAll(in: context, today: today)
        Scheduler.extendAll(in: context, today: today)
        #expect(try entries().count == 14)
    }

    @Test func extendingLaterAddsTheNextOccurrences() throws {
        monthlyRent(from: day(2026, 9, 1))
        Scheduler.extendAll(in: context, today: day(2026, 12, 15))
        let all = try entries()
        #expect(all.count == 16)
        #expect(all.last?.date == day(2027, 12, 1))
    }

    @Test func deletedOccurrenceStaysDeleted() throws {
        monthlyRent(from: day(2026, 9, 1))
        context.delete(try #require(try entries().last))
        Scheduler.extendAll(in: context, today: today)
        #expect(try entries().count == 13)
    }

    @Test func dueDateOnlyRepeatsStayUnpaid() throws {
        let phone = Entry(kind: .spend, title: "Phone", amountCents: 65_00, date: nil, dueDate: day(2026, 10, 22))
        context.insert(phone)
        Scheduler.startSeries(with: phone, frequency: .monthly, endDate: day(2026, 12, 31), in: context, today: today)
        let all = try entries()
        #expect(all.map(\.dueDate) == [day(2026, 10, 22), day(2026, 11, 22), day(2026, 12, 22)])
        #expect(all.allSatisfy { $0.date == nil })
    }

    @Test func savingForFutureChangesOnlyWhatHasNotHappened() throws {
        monthlyRent(from: day(2026, 9, 1))
        let november = try occurrence(on: day(2026, 11, 1))
        saveForFuture(november) { $0.amountText = "1600" }

        let all = try entries()
        #expect(all.count == 14)
        #expect(all.filter { $0.amountCents == 1_500_00 }.map(\.date) == [day(2026, 9, 1), day(2026, 10, 1)])
        #expect(all.filter { $0.amountCents == 1_600_00 }.count == 12)
    }

    @Test func savingFutureFromAPaidOccurrenceKeepsLaterPaidOnes() throws {
        monthlyRent(from: day(2026, 9, 1))
        let september = try occurrence(on: day(2026, 9, 1))
        saveForFuture(september) { $0.amountText = "1700" }

        let all = try entries()
        #expect(all.count == 14)
        #expect(Set(all.compactMap(\.date)).count == 14)
        #expect(try occurrence(on: day(2026, 10, 1)).amountCents == 1_500_00)
        #expect(try occurrence(on: day(2026, 11, 1)).amountCents == 1_700_00)
    }

    @Test func movingTheDayMovesLaterOccurrences() throws {
        monthlyRent(from: day(2026, 9, 1))
        let november = try occurrence(on: day(2026, 11, 1))
        saveForFuture(november) { $0.date = day(2026, 11, 5) }

        let dates = try entries().compactMap(\.date)
        #expect(dates.count == 14)
        #expect(dates.contains(day(2026, 12, 5)))
        #expect(!dates.contains(day(2026, 12, 1)))
        #expect(dates.last == day(2027, 10, 5))
    }

    @Test func changingTheFrequencyRebuildsTheFuture() throws {
        monthlyRent(from: day(2026, 9, 1))
        let november = try occurrence(on: day(2026, 11, 1))
        saveForFuture(november) { $0.frequency = .quarterly }

        #expect(try entries().compactMap(\.date) == [
            day(2026, 9, 1), day(2026, 10, 1), day(2026, 11, 1),
            day(2027, 2, 1), day(2027, 5, 1), day(2027, 8, 1),
        ])
    }

    @Test func turningRepeatOffEndsTheSeries() throws {
        monthlyRent(from: day(2026, 9, 1))
        let november = try occurrence(on: day(2026, 11, 1))
        saveForFuture(november) { $0.frequency = nil }

        #expect(try entries().compactMap(\.date) == [day(2026, 9, 1), day(2026, 10, 1), day(2026, 11, 1)])
        #expect(november.series == nil)
        Scheduler.extendAll(in: context, today: day(2027, 3, 1))
        #expect(try entries().count == 3)
    }

    @Test func deletingThisAndFutureKeepsHistory() throws {
        monthlyRent(from: day(2026, 9, 1))
        Scheduler.deleteThisAndFuture(try occurrence(on: day(2026, 11, 1)), in: context, today: today)

        #expect(try entries().compactMap(\.date) == [day(2026, 9, 1), day(2026, 10, 1)])
        Scheduler.extendAll(in: context, today: day(2027, 6, 1))
        #expect(try entries().count == 2)
        #expect(try seriesCount() == 1)
    }

    @Test func deletingEveryOccurrenceRemovesTheSeries() throws {
        let rent = monthlyRent(from: day(2026, 11, 1))
        Scheduler.deleteThisAndFuture(rent, in: context, today: today)
        #expect(try entries().isEmpty)
        #expect(try seriesCount() == 0)
    }

    // MARK: Editing from the past

    @Test func movingAPastOccurrenceDoesNotCreatePaidCopies() throws {
        monthlyRent(from: day(2026, 9, 1))
        saveForFuture(try occurrence(on: day(2026, 9, 1))) { $0.date = day(2026, 9, 3) }

        let dates = try entries().compactMap(\.date)
        #expect(dates.count == 14)
        #expect(dates.filter { $0 <= today } == [day(2026, 9, 3), day(2026, 10, 1)])
        #expect(dates.contains(day(2026, 11, 3)))
        #expect(!dates.contains(day(2026, 10, 3)))
    }

    @Test func changingTheFrequencyFromThePastOnlyAddsFutureOccurrences() throws {
        monthlyRent(from: day(2026, 9, 1))
        saveForFuture(try occurrence(on: day(2026, 9, 1))) { $0.frequency = .biweekly }

        let dates = try entries().compactMap(\.date)
        #expect(dates.filter { $0 <= today } == [day(2026, 9, 1), day(2026, 10, 1)])
        #expect(dates.filter { $0 > today }.prefix(2) == [day(2026, 10, 27), day(2026, 11, 10)])
    }

    @Test func anOccurrencePaidEarlyIsNotCreatedAgain() throws {
        monthlyRent(from: day(2026, 9, 1))
        try occurrence(on: day(2026, 12, 1)).date = today
        saveForFuture(try occurrence(on: day(2026, 11, 1))) { $0.amountText = "1600" }

        let dates = try entries().compactMap(\.date)
        #expect(dates.count == 14)
        #expect(!dates.contains(day(2026, 12, 1)))
        #expect(try occurrence(on: day(2027, 1, 1)).amountCents == 1_600_00)
    }

    @Test func anOccurrenceMarkedUnpaidIsKept() throws {
        monthlyRent(from: day(2026, 9, 1))
        try occurrence(on: day(2026, 10, 1)).date = nil
        saveForFuture(try occurrence(on: day(2026, 9, 1))) { $0.amountText = "1700" }

        let all = try entries()
        #expect(all.count == 14)
        #expect(all.filter { $0.date == nil }.count == 1)
        #expect(!all.contains { $0.date == day(2026, 10, 1) })
    }

    @Test func changingOnlyTheAmountKeepsTheEndOfTheMonth() throws {
        let rent = Entry(kind: .spend, title: "Rent", amountCents: 1_500_00, date: day(2026, 1, 31))
        context.insert(rent)
        Scheduler.startSeries(with: rent, frequency: .monthly, endDate: nil, in: context, today: today)
        saveForFuture(try occurrence(on: day(2026, 2, 28))) { $0.amountText = "1600" }

        let dates = try entries().compactMap(\.date)
        #expect(dates.contains(day(2026, 10, 31)))
        #expect(dates.contains(day(2026, 11, 30)))
        #expect(!dates.contains(day(2026, 10, 28)))
        #expect(try occurrence(on: day(2026, 10, 31)).amountCents == 1_600_00)
    }

    @Test func occurrencesMadeBeforePlacesWereStoredAreMatchedByDate() throws {
        monthlyRent(from: day(2026, 9, 1))
        try entries().forEach { $0.occurrenceIndex = nil }
        saveForFuture(try occurrence(on: day(2026, 11, 1))) { $0.amountText = "1600" }

        let all = try entries()
        #expect(all.count == 14)
        #expect(all.filter { $0.amountCents == 1_600_00 }.count == 12)
    }
}
