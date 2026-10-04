//
//  RecurrenceTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import Testing
@testable import Mint

@MainActor
struct RecurrenceTests {
    let calendar = Calendar.current

    private func dates(_ frequency: Frequency, from anchor: Date, through limit: Date, endDate: Date? = nil) -> [Date?] {
        Recurrence.occurrences(
            frequency: frequency, anchorDate: anchor, anchorDueDate: nil, endDate: endDate,
            startingAt: 0, through: limit, calendar: calendar
        ).map(\.date)
    }

    @Test func monthlyStaysOnTheEndOfTheMonth() {
        #expect(dates(.monthly, from: day(2026, 1, 31), through: day(2026, 4, 30))
            == [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30)])
    }

    @Test func biweeklyStepsFourteenDays() {
        #expect(dates(.biweekly, from: day(2026, 10, 2), through: day(2026, 11, 13))
            == [day(2026, 10, 2), day(2026, 10, 16), day(2026, 10, 30), day(2026, 11, 13)])
    }

    @Test func quarterlyAndYearly() {
        #expect(dates(.quarterly, from: day(2026, 1, 15), through: day(2026, 12, 31))
            == [day(2026, 1, 15), day(2026, 4, 15), day(2026, 7, 15), day(2026, 10, 15)])
        #expect(dates(.yearly, from: day(2024, 2, 29), through: day(2026, 12, 31))
            == [day(2024, 2, 29), day(2025, 2, 28), day(2026, 2, 28)])
    }

    @Test func stopsAtTheEndDate() {
        #expect(dates(.weekly, from: day(2026, 10, 1), through: day(2027, 1, 1), endDate: day(2026, 10, 20))
            == [day(2026, 10, 1), day(2026, 10, 8), day(2026, 10, 15)])
    }

    @Test func paymentAndDueDatesBothMoveForward() {
        let occurrences = Recurrence.occurrences(
            frequency: .monthly, anchorDate: day(2026, 10, 10), anchorDueDate: day(2026, 10, 15), endDate: nil,
            startingAt: 1, through: day(2026, 12, 31), calendar: calendar
        )
        #expect(occurrences.map(\.index) == [1, 2])
        #expect(occurrences.map(\.date) == [day(2026, 11, 10), day(2026, 12, 10)])
        #expect(occurrences.map(\.dueDate) == [day(2026, 11, 15), day(2026, 12, 15)])
    }

    @Test func anchorCanBeALaterOccurrence() {
        let occurrences = Recurrence.occurrences(
            frequency: .monthly, anchorDate: day(2026, 3, 31), anchorDueDate: nil, anchorIndex: 2, endDate: nil,
            startingAt: 1, through: day(2026, 5, 31), calendar: calendar
        )
        #expect(occurrences.map(\.index) == [1, 2, 3, 4])
        #expect(occurrences.map(\.date) == [day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30), day(2026, 5, 31)])
    }

    @Test func needsADateToRepeat() {
        let occurrences = Recurrence.occurrences(
            frequency: .weekly, anchorDate: nil, anchorDueDate: nil, endDate: nil,
            startingAt: 0, through: day(2027, 1, 1), calendar: calendar
        )
        #expect(occurrences.isEmpty)
    }
}
