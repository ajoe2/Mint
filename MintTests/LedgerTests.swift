//
//  LedgerTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import Testing
@testable import Mint

/// Today is Oct 15, 2026. The starting balance is $1,000 as of Oct 1.
@MainActor
struct LedgerTests {
    let ledger = Ledger(startingBalanceCents: 1_000_00, startDate: day(2026, 10, 1), today: day(2026, 10, 15))

    /// Paid before the start date, so it only counts in statistics.
    let history = TestItem(kind: .spend, amountCents: 50_00, date: day(2026, 9, 20))
    let paycheck = TestItem(kind: .income, amountCents: 2_000_00, date: day(2026, 10, 2), category: "Salary")
    let groceries = TestItem(kind: .spend, amountCents: 100_00, date: day(2026, 10, 15), category: "Groceries")
    let rent = TestItem(kind: .spend, amountCents: 1_500_00, date: day(2026, 11, 1), dueDate: day(2026, 11, 5), category: "Housing")
    let phone = TestItem(kind: .spend, amountCents: 60_00, date: nil, dueDate: day(2026, 10, 18))
    let electric = TestItem(kind: .spend, amountCents: 90_00, date: nil, dueDate: day(2026, 10, 10))
    let loan = TestItem(kind: .spend, amountCents: 45_00, date: nil)
    let insurance = TestItem(kind: .spend, amountCents: 300_00, date: day(2026, 10, 25), dueDate: day(2026, 10, 20))
    let subsidy = TestItem(kind: .subsidy, amountCents: 200_00, date: day(2026, 10, 20))

    var all: [TestItem] { [history, paycheck, groceries, rent, phone, electric, loan, insurance, subsidy] }

    @Test func statusFollowsTheDate() {
        #expect(ledger.status(of: groceries) == .paid)
        #expect(ledger.status(of: paycheck) == .paid)
        #expect(ledger.status(of: rent) == .scheduled)
        #expect(ledger.status(of: phone) == .unpaid)
        #expect(ledger.status(of: loan) == .unpaid)
    }

    @Test func scheduledEntryCountsOnceItsDayArrives() {
        let firstOfNovember = Ledger(startingBalanceCents: 1_000_00, startDate: day(2026, 10, 1), today: day(2026, 11, 1))
        #expect(firstOfNovember.status(of: rent) == .paid)
        #expect(firstOfNovember.currentBalance([rent]) == -500_00)
    }

    @Test func balanceSkipsUnpaidAndPreStartEntries() {
        // $1,000 + $2,000 paycheck - $100 groceries.
        #expect(ledger.currentBalance(all) == 2_900_00)
    }

    @Test func flagsBillsThatNeedAttention() {
        #expect(ledger.isOverdue(electric))
        #expect(!ledger.isOverdue(phone))
        #expect(ledger.isDueSoon(phone))
        #expect(ledger.isScheduledLate(insurance))
        for item in [rent, loan, groceries] {
            #expect(!ledger.isOverdue(item) && !ledger.isDueSoon(item) && !ledger.isScheduledLate(item))
        }
    }

    @Test func projectsScheduledEntriesAndUnpaidBills() {
        // Unpaid bills count on their due date (overdue ones today); the dateless loan is left out.
        #expect(ledger.dailyBalances(all, from: day(2026, 10, 31), through: day(2026, 10, 31)).last?.cents == 2_650_00)
        #expect(ledger.dailyBalances(all, from: day(2026, 11, 30), through: day(2026, 11, 30)).last?.cents == 1_150_00)
    }

    @Test func forecastRunsInDateOrderWithARunningBalance() {
        let forecast = ledger.forecast(all)
        #expect(forecast.map(\.item.amountCents) == [90_00, 60_00, 200_00, 300_00, 1_500_00])
        #expect(forecast.map(\.balanceAfter) == [2_810_00, 2_750_00, 2_950_00, 2_650_00, 1_150_00])
        #expect(forecast.first?.day == day(2026, 10, 15))
    }

    @Test func sameDayMoneyInCountsFirst() {
        let bill = TestItem(kind: .spend, amountCents: 500_00, date: day(2026, 10, 20))
        let pay = TestItem(kind: .income, amountCents: 400_00, date: day(2026, 10, 20))
        let forecast = ledger.forecast([bill, pay])
        #expect(forecast.map(\.item.kind) == [.income, .spend])
    }

    @Test func dailyBalancesSplitActualAndProjected() {
        let points = ledger.dailyBalances(all, from: day(2026, 9, 1), through: day(2026, 10, 20))
        let actual = points.filter { !$0.isProjected }
        let projected = points.filter(\.isProjected)

        // Before the start date, the chart works backward: the $50 spent on Sep 20 means the
        // balance was $1,050 before then.
        #expect(actual.first?.day == day(2026, 9, 1))
        #expect(actual.first?.cents == 1_050_00)
        #expect(actual.first { $0.day == day(2026, 9, 19) }?.cents == 1_050_00)
        #expect(actual.first { $0.day == day(2026, 9, 20) }?.cents == 1_000_00)
        #expect(actual.first { $0.day == day(2026, 10, 1) }?.cents == 1_000_00)
        #expect(actual.last?.day == day(2026, 10, 15))
        #expect(actual.last?.cents == 2_900_00)

        #expect(projected.first?.day == day(2026, 10, 15))
        #expect(projected.first?.cents == 2_810_00)
        #expect(projected.last?.day == day(2026, 10, 20))
        #expect(projected.last?.cents == 2_950_00)
    }

    @Test func lowestBalanceFindsTheDip() {
        let lowest = ledger.lowestBalance(through: day(2026, 11, 30), all)
        #expect(lowest.cents == 1_150_00)
        #expect(lowest.day == day(2026, 11, 1))

        // Same answer from chart points that also cover the past.
        let points = ledger.dailyBalances(all, from: day(2026, 9, 1), through: day(2026, 11, 30))
        #expect(ledger.lowestBalance(in: points) == lowest)
    }

    @Test func totalsIncludeHistoryButNotPending() {
        let totals = ledger.totals(all)
        #expect(totals.income == 2_000_00)
        #expect(totals.spending == 150_00)
        #expect(totals.subsidies == 0)
        #expect(totals.investments == 0)
        #expect(totals.net == 1_850_00)
    }

    @Test func totalsForThisMonth() throws {
        let october = try #require(StatsPeriod.month.range(today: ledger.today, calendar: ledger.calendar))
        #expect(october.lowerBound == day(2026, 10, 1))
        #expect(october.upperBound == day(2026, 10, 31))

        let totals = ledger.totals(all, in: october)
        #expect(totals.spending == 100_00)
        #expect(totals.income == 2_000_00)

        let stillScheduled = ledger.pendingTotals(all, in: ledger.today...october.upperBound)
        #expect(stillScheduled.spending == 450_00)
        #expect(stillScheduled.subsidies == 200_00)
    }

    @Test func spendingByCategoryLargestFirst() {
        #expect(ledger.spendingByCategory(all) == [
            CategoryTotal(name: "Groceries", cents: 100_00),
            CategoryTotal(name: "Uncategorized", cents: 50_00),
        ])
    }

    @Test func categoriesIgnoreCapitalization() {
        let snacks = TestItem(kind: .spend, amountCents: 5_00, date: day(2026, 10, 3), category: "groceries ")
        #expect(ledger.spendingByCategory(all + [snacks]).first == CategoryTotal(name: "Groceries", cents: 105_00))
    }

    /// In Havana, daylight saving time starts at midnight, so Mar 8, 2026 begins at 1:00.
    @Test func dayStepsSurviveMidnightDaylightSaving() throws {
        var havana = Calendar(identifier: .gregorian)
        havana.timeZone = try #require(TimeZone(identifier: "America/Havana"))
        func havanaDay(_ month: Int, _ day: Int) -> Date {
            havana.startOfDay(for: havana.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!)
        }
        let ledger = Ledger(checkpoints: [BalanceCheckpoint(day: havanaDay(3, 1), baseCents: 100_00)], today: havanaDay(3, 20), calendar: havana)
        #expect(ledger.addingDays(1, to: havanaDay(3, 7)) == havanaDay(3, 8))
        #expect(ledger.addingDays(1, to: havanaDay(3, 8)) == havanaDay(3, 9))

        let coffee = TestItem(kind: .spend, amountCents: 5_00, date: havanaDay(3, 9))
        let points = ledger.dailyBalances([coffee], from: havanaDay(3, 1), through: havanaDay(3, 12)).filter { !$0.isProjected }
        #expect(points.count == 12)
        #expect(points.first { $0.day == havanaDay(3, 9) }?.cents == 95_00)
    }

    @Test func monthlyTotalsOldestFirst() {
        let months = ledger.monthlyTotals(all, months: 2)
        #expect(months.map(\.month) == [day(2026, 9, 1), day(2026, 10, 1)])
        #expect(months.map(\.totals.spending) == [50_00, 100_00])
        #expect(months.map(\.totals.income) == [0, 2_000_00])
    }
}
