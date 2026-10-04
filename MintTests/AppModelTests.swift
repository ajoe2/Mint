//
//  AppModelTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import AppKit
import Testing
@testable import Mint

@MainActor
struct AppModelTests {
    @Test func tabsCycleAndWrap() {
        #expect(Screen.overview.moved(by: 1) == .transactions)
        #expect(Screen.statistics.moved(by: 1) == .overview)
        #expect(Screen.overview.moved(by: -1) == .statistics)
    }

    @Test func filtersListEveryKind() {
        #expect(TransactionFilter.allCases.map(\.title) == ["All", "Spending", "Income", "Investments", "Subsidies", "Adjustments"])
    }

    @Test func newEntriesFollowTheTransactionsFilter() {
        let app = AppModel()
        app.transactionFilter = .kind(.income)
        #expect(app.newEntryKind == .spend)
        app.selection = .transactions
        #expect(app.newEntryKind == .income)
        app.reset()
        #expect(app.selection == .overview && app.transactionFilter == .all)
    }

    @Test func sheetsDontStack() {
        let app = AppModel()
        #expect(app.isBrowsing)
        app.isAdjustingBalance = true
        #expect(!app.isBrowsing)
        app.isAdjustingBalance = false
        app.isSettingUp = true
        #expect(!app.isBrowsing)
    }

    @Test func everyCategorySymbolExists() {
        for symbol in Set(EntryKind.categorySymbols.values).union(EntryKind.allCases.map(\.symbol)) {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
        #expect(EntryKind.spend.symbol(forCategory: " Housing") == "house.fill")
        #expect(EntryKind.spend.symbol(forCategory: "Something else") == "cart.fill")
        #expect(EntryKind.spend.symbol(forCategory: "credit card") == "creditcard.fill")
        #expect(EntryKind.spend.defaultCategories.contains("Credit Card"))
    }
}
