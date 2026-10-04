//
//  SampleData.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// Realistic example entries for demo mode (`-demo YES`).
enum SampleData {
    static func insert(into context: ModelContext, today: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: today)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }
        func monthDay(_ day: Int, monthsAgo: Int) -> Date {
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = day
            let date = calendar.date(from: components) ?? today
            return calendar.date(byAdding: .month, value: -monthsAgo, to: date) ?? date
        }
        func repeating(_ entry: Entry, _ frequency: Frequency) {
            context.insert(entry)
            Scheduler.startSeries(with: entry, frequency: frequency, endDate: nil, in: context, today: today, calendar: calendar)
        }

        repeating(Entry(kind: .income, title: "Paycheck", amountCents: 1_840_00, date: day(-86), category: "Salary"), .biweekly)
        repeating(
            Entry(kind: .spend, title: "Rent", amountCents: 1_650_00, date: monthDay(1, monthsAgo: 2), dueDate: monthDay(5, monthsAgo: 2), category: "Housing"),
            .monthly
        )
        repeating(Entry(kind: .subsidy, title: "Housing assistance", amountCents: 300_00, date: monthDay(15, monthsAgo: 2), category: "Government"), .monthly)
        repeating(Entry(kind: .investment, title: "Index fund", amountCents: 400_00, date: monthDay(20, monthsAgo: 2), category: "Retirement"), .monthly)
        repeating(Entry(kind: .spend, title: "Music streaming", amountCents: 11_99, date: monthDay(9, monthsAgo: 2), category: "Subscriptions"), .monthly)
        repeating(Entry(kind: .spend, title: "Internet", amountCents: 60_00, date: monthDay(12, monthsAgo: 2), category: "Utilities"), .monthly)

        let everyday: [(String, String, Int)] = [
            ("Groceries", "Groceries", 86_40),
            ("Coffee with Sam", "Dining", 12_75),
            ("Gas", "Transportation", 48_10),
            ("Groceries", "Groceries", 64_25),
            ("Dinner out", "Dining", 54_80),
            ("Pharmacy", "Health", 23_15),
            ("Groceries", "Groceries", 91_05),
            ("Movie tickets", "Entertainment", 31_00),
            ("New shoes", "Shopping", 89_99),
        ]
        for (index, offset) in stride(from: -84, through: -1, by: 4).enumerated() {
            let (title, category, cents) = everyday[index % everyday.count]
            context.insert(Entry(kind: .spend, title: title, amountCents: cents, date: day(offset), category: category))
        }

        context.insert(Entry(kind: .subsidy, title: "Scholarship", amountCents: 1_200_00, date: day(-60), category: "Scholarship"))
        context.insert(Entry(kind: .investment, title: "Brokerage deposit", amountCents: 750_00, date: day(-35), category: "Brokerage"))

        // Unpaid bills: one overdue, one due soon.
        context.insert(Entry(kind: .spend, title: "Electric bill", amountCents: 92_40, date: nil, dueDate: day(-2), category: "Utilities"))
        context.insert(Entry(kind: .spend, title: "Phone bill", amountCents: 65_00, date: nil, dueDate: day(3), category: "Utilities"))
        // Scheduled ahead.
        context.insert(Entry(kind: .spend, title: "Car insurance", amountCents: 640_00, date: day(12), dueDate: day(15), category: "Transportation"))
        context.insert(Entry(kind: .income, title: "Freelance invoice", amountCents: 800_00, date: nil, dueDate: day(24), category: "Freelance"))
        context.insert(Entry(kind: .spend, title: "Flight home", amountCents: 389_00, date: day(40), category: "Travel"))
        // No date and no deadline.
        context.insert(Entry(kind: .spend, title: "Pay back Alex", amountCents: 45_00, date: nil, category: "Other"))

        // A starting balance three months ago, plus a small correction 20 days ago to match the bank.
        let startDay = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        let start = BalanceAdjustment(day: startDay, amountCents: 2_450_00, baseCents: 2_450_00)
        context.insert(start)
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let ledger = Ledger(checkpoints: [start.checkpoint], today: today, calendar: calendar)
        let correctionDay = day(-20)
        if let shown = ledger.actualBalance(atEndOf: correctionDay, entries) {
            BalanceAdjustment.record(shown - 37_50, on: correctionDay, replacing: [start], entries: entries, ledger: ledger, in: context)
        }
    }
}
