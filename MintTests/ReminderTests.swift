//
//  ReminderTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/3/26.
//

import Foundation
import SwiftData
import Testing
@testable import Mint

@MainActor
struct ReminderTests {
    let today = day(2026, 10, 2)

    /// Saves the entries so each gets its permanent ID.
    private func saved(_ entries: [Entry]) throws -> [Entry] {
        let context = try makeContext()
        entries.forEach(context.insert)
        try context.save()
        return entries
    }

    private func plan(_ entries: [Entry], balance: Int = 1_000_00, settings: ReminderSettings? = nil) -> [Reminder] {
        let ledger = Ledger(startingBalanceCents: balance, startDate: today, today: today)
        return ReminderPlanner.plan(entries: entries, ledger: ledger, settings: settings ?? .standard)
    }

    private func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }

    @Test func remindsBeforeSomethingIsDueAndAgainWhenItsOverdue() throws {
        let bill = try saved([
            Entry(kind: .spend, title: "Phone bill", amountCents: 45_00, date: nil, dueDate: day(2026, 10, 9), category: "Utilities"),
        ])[0]

        let reminders = plan([bill])

        #expect(reminders.map(\.title) == ["Phone bill is due tomorrow", "Phone bill is overdue"])
        #expect(reminders.map(\.date) == [at(day(2026, 10, 8), 9), at(day(2026, 10, 10), 9)])
        #expect(reminders.map(\.body) == ["\(Money.format(45_00)) · Utilities", "\(Money.format(45_00)) was due yesterday."])
        for reminder in reminders {
            #expect(reminder.kind == .spend)
            #expect(reminder.entryKey.flatMap(Reminder.entryID(forKey:)) == bill.persistentModelID)
        }
    }

    @Test func onlyUnpaidEntriesWithADueDate() throws {
        let entries = try saved([
            Entry(kind: .spend, title: "Scheduled", amountCents: 10_00, date: day(2026, 10, 5), dueDate: day(2026, 10, 9)),
            Entry(kind: .spend, title: "Paid", amountCents: 10_00, date: day(2026, 10, 1), dueDate: day(2026, 10, 9)),
            Entry(kind: .spend, title: "No due date", amountCents: 10_00, date: nil),
        ])
        #expect(plan(entries).isEmpty)
    }

    @Test func followTheChosenDayAndTime() throws {
        let bill = try saved([Entry(kind: .spend, title: "Rent", amountCents: 120_00, date: nil, dueDate: day(2026, 10, 9))])

        var settings = ReminderSettings.standard
        settings.daysBefore = 0
        settings.minuteOfDay = 18 * 60 + 30
        let onTheDay = plan(bill, settings: settings)
        #expect(onTheDay.first?.title == "Rent is due today")
        #expect(onTheDay.map(\.date) == [at(day(2026, 10, 9), 18, 30), at(day(2026, 10, 10), 18, 30)])

        settings.daysBefore = 7
        let weekBefore = plan(bill, settings: settings)
        #expect(weekBefore.first?.date == at(day(2026, 10, 2), 18, 30))
        #expect(weekBefore.first?.title == "Rent is due on " + day(2026, 10, 9).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))

        settings.dueDates = false
        #expect(plan(bill, settings: settings).isEmpty)
    }

    @Test func warnsBeforeTheBalanceDropsBelowZero() throws {
        let bill = try saved([Entry(kind: .spend, title: "Rent", amountCents: 150_00, date: nil, dueDate: day(2026, 10, 9))])
        var settings = ReminderSettings.standard
        settings.dueDates = false

        let reminders = plan(bill, balance: 100_00, settings: settings)

        #expect(reminders.count == 1)
        #expect(reminders.first?.id == "low-balance-2026-10-09")
        #expect(reminders.first?.date == at(day(2026, 10, 8), 9))
        #expect(reminders.first?.title == "Low balance ahead")
        #expect(reminders.first?.body == "Your balance is expected to drop to \(Money.format(-50_00)) tomorrow.")
        #expect(reminders.first?.entryKey == nil)

        settings.lowBalance = false
        #expect(plan(bill, balance: 100_00, settings: settings).isEmpty)
    }

    @Test func warnsBeforeTheBalanceDropsBelowTheLimit() throws {
        let bill = try saved([Entry(kind: .spend, title: "Rent", amountCents: 600_00, date: nil, dueDate: day(2026, 10, 9))])
        var settings = ReminderSettings.standard
        settings.dueDates = false

        settings.limitCents = 500_00
        let reminders = plan(bill, settings: settings)
        #expect(reminders.map(\.id) == ["low-balance-2026-10-09"])
        #expect(reminders.first?.body.hasSuffix("That's below your \(Money.format(500_00)) limit.") == true)

        // $400 is left, which is above this limit.
        settings.limitCents = 300_00
        #expect(plan(bill, settings: settings).isEmpty)
    }

    @Test func warnsOnceForEachDip() throws {
        let entries = try saved([
            Entry(kind: .spend, title: "Rent", amountCents: 150_00, date: nil, dueDate: day(2026, 10, 9)),
            Entry(kind: .income, title: "Paycheck", amountCents: 200_00, date: day(2026, 10, 12)),
            Entry(kind: .spend, title: "Insurance", amountCents: 200_00, date: day(2026, 10, 20)),
        ])
        var settings = ReminderSettings.standard
        settings.dueDates = false

        #expect(plan(entries, balance: 100_00, settings: settings).map(\.id) == ["low-balance-2026-10-09", "low-balance-2026-10-20"])
        // Already below the limit, so the only warning is for the dip after the paycheck.
        #expect(plan(entries, balance: -10_00, settings: settings).map(\.id) == ["low-balance-2026-10-20"])
    }

    @Test func plansAreStableAndInOrder() throws {
        let entries = try saved([
            Entry(kind: .spend, title: "Later", amountCents: 10_00, date: nil, dueDate: day(2026, 10, 20)),
            Entry(kind: .spend, title: "Sooner", amountCents: 10_00, date: nil, dueDate: day(2026, 10, 9)),
        ])
        let first = plan(entries)
        #expect(first == plan(entries))
        #expect(first.map(\.date) == first.map(\.date).sorted())
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func leadTimesHaveNames() {
        #expect(ReminderSettings.leadTimes.map(ReminderSettings.title(forDaysBefore:))
            == ["On the day", "1 day before", "2 days before", "3 days before", "1 week before"])
    }
}
