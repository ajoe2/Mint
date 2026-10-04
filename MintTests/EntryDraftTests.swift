//
//  EntryDraftTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import Testing
@testable import Mint

@MainActor
struct EntryDraftTests {
    let today = day(2026, 10, 15)

    @Test func newEntriesStartUnpaid() {
        var draft = EntryDraft(kind: .spend, today: today)
        #expect(draft.status(today: today) == .unpaid)
        draft.hasDate = true
        #expect(draft.status(today: today) == .paid)
        draft.date = day(2026, 10, 20)
        #expect(draft.status(today: today) == .scheduled)
    }

    @Test func switchingStatusMovesDatesThatNoLongerFit() {
        var draft = EntryDraft(kind: .spend, today: today)
        draft.setStatus(.scheduled, today: today)
        #expect(draft.date == day(2026, 10, 16))

        draft.date = day(2026, 11, 1)
        draft.setStatus(.paid, today: today)
        #expect(draft.date == today)

        draft.date = day(2026, 10, 3)
        draft.setStatus(.paid, today: today)
        #expect(draft.date == day(2026, 10, 3))

        draft.setStatus(.unpaid, today: today)
        #expect(!draft.hasDate)
        draft.setStatus(.paid, today: today)
        #expect(draft.hasDate && draft.date == day(2026, 10, 3))
    }

    @Test func needsATitleAndAPositiveAmount() {
        var draft = EntryDraft(kind: .spend, today: today)
        #expect(!draft.isValid)
        draft.title = "  Lunch "
        draft.amountText = "0"
        #expect(!draft.isValid)
        draft.amountText = "12.40"
        #expect(draft.isValid)

        draft.frequency = .monthly
        #expect(!draft.canRepeat)
        draft.hasDueDate = true
        #expect(draft.canRepeat)
        #expect(draft.repeatStart == today)
    }

    @Test func applyingTrimsTextAndClearsTurnedOffDates() {
        var draft = EntryDraft(kind: .income, today: today)
        draft.title = " Paycheck "
        draft.amountText = "$2,000"
        draft.notes = "  "
        let entry = draft.makeEntry()
        #expect(entry.title == "Paycheck")
        #expect(entry.amountCents == 2_000_00)
        #expect(entry.kind == .income)
        #expect(entry.date == nil)
        #expect(entry.dueDate == nil)
        #expect(entry.notes.isEmpty)
    }

    @Test func roundTripsAnEntry() {
        let entry = Entry(kind: .investment, title: "Index fund", amountCents: 400_25, date: day(2026, 10, 20), dueDate: day(2026, 10, 25), category: "Retirement")
        let draft = EntryDraft(entry: entry, today: today)
        #expect(draft.amountCents == 400_25)
        #expect(draft.hasDate && draft.hasDueDate)
        #expect(draft.frequency == nil)

        let copy = draft.makeEntry()
        #expect(copy.date == entry.date)
        #expect(copy.dueDate == entry.dueDate)
        #expect(copy.category == "Retirement")
        #expect(copy.kind == .investment)
    }

    /// A date saved in another time zone isn't midnight here. Saving without touching it must
    /// keep it exactly, or the entry moves a day.
    @Test func unchangedDatesKeepTheirStoredValue() throws {
        let storedElsewhere = try #require(Calendar.current.date(byAdding: .hour, value: 3, to: day(2026, 10, 20)))
        let entry = Entry(kind: .spend, title: "Rent", amountCents: 1_500_00, date: storedElsewhere)
        var draft = EntryDraft(entry: entry, today: today)
        draft.title = "Rent (new)"
        draft.apply(to: entry)
        #expect(entry.date == storedElsewhere)

        draft.date = day(2026, 10, 22)
        draft.apply(to: entry)
        #expect(entry.date == day(2026, 10, 22))
    }
}
