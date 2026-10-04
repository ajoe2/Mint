//
//  DayTextTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import Testing
@testable import Mint

@MainActor
struct DayTextTests {
    @Test func relativeDatesNameNearbyDays() {
        let today = day(2026, 10, 15)
        #expect(DayText.relative(today, today: today) == "Today")
        #expect(DayText.relative(day(2026, 10, 16), today: today) == "Tomorrow")
        #expect(DayText.relative(day(2026, 10, 14), today: today) == "Yesterday")
        #expect(DayText.relative(day(2026, 10, 20), today: today) != DayText.short(day(2026, 10, 20), today: today))
    }
}
