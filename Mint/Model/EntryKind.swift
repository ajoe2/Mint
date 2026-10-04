//
//  EntryKind.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftUI

/// The four kinds of entry. The kind decides whether an entry adds to or takes from the balance.
enum EntryKind: String, CaseIterable, Identifiable {
    case spend
    case income
    case investment
    case subsidy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spend: "Spend"
        case .income: "Income"
        case .investment: "Investment"
        case .subsidy: "Subsidy"
        }
    }

    var pluralTitle: String {
        switch self {
        case .spend: "Spending"
        case .income: "Income"
        case .investment: "Investments"
        case .subsidy: "Subsidies"
        }
    }

    /// `+1` when money comes into the account, `-1` when it leaves.
    var sign: Int {
        switch self {
        case .income, .subsidy: 1
        case .spend, .investment: -1
        }
    }

    var isInflow: Bool { sign > 0 }

    var symbol: String {
        switch self {
        case .spend: "cart.fill"
        case .income: "banknote.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .subsidy: "gift.fill"
        }
    }

    /// The symbol for `category`, so rows are easy to tell apart. Falls back to the kind's symbol.
    func symbol(forCategory category: String) -> String {
        Self.categorySymbols[category.trimmingCharacters(in: .whitespaces).lowercased()] ?? symbol
    }

    static let categorySymbols: [String: String] = [
        "housing": "house.fill",
        "rent": "house.fill",
        "utilities": "bolt.fill",
        "groceries": "cart.fill",
        "dining": "fork.knife",
        "transportation": "car.fill",
        "shopping": "bag.fill",
        "health": "cross.case.fill",
        "entertainment": "film.fill",
        "subscriptions": "play.rectangle.fill",
        "credit card": "creditcard.fill",
        "education": "book.fill",
        "travel": "airplane",
        "gifts": "gift.fill",
        "gift": "gift.fill",
        "salary": "banknote.fill",
        "freelance": "briefcase.fill",
        "bonus": "star.fill",
        "refund": "arrow.uturn.backward",
        "interest": "percent",
        "brokerage": "chart.line.uptrend.xyaxis",
        "retirement": "sun.horizon.fill",
        "savings": "building.columns.fill",
        "crypto": "bitcoinsign.circle.fill",
        "government": "building.columns.fill",
        "employer": "briefcase.fill",
        "scholarship": "graduationcap.fill",
        "family": "person.2.fill",
    ]

    var color: Color {
        switch self {
        case .spend: .orange
        case .income: .green
        case .investment: .blue
        case .subsidy: .purple
        }
    }

    /// Status label once the money has moved.
    var completedLabel: String {
        switch self {
        case .spend: "Paid"
        case .income, .subsidy: "Received"
        case .investment: "Invested"
        }
    }

    /// Status label before the money has moved.
    var notCompletedLabel: String {
        switch self {
        case .spend: "Unpaid"
        case .income, .subsidy: "Not received"
        case .investment: "Not invested"
        }
    }

    var titlePrompt: String {
        switch self {
        case .spend: "Groceries"
        case .income: "Paycheck"
        case .investment: "Index fund"
        case .subsidy: "Housing assistance"
        }
    }

    var defaultCategories: [String] {
        switch self {
        case .spend:
            ["Housing", "Utilities", "Credit Card", "Groceries", "Dining", "Transportation", "Shopping",
             "Health", "Entertainment", "Subscriptions", "Education", "Travel", "Gifts", "Other"]
        case .income:
            ["Salary", "Freelance", "Bonus", "Refund", "Interest", "Gift", "Other"]
        case .investment:
            ["Brokerage", "Retirement", "Savings", "Crypto", "Other"]
        case .subsidy:
            ["Government", "Employer", "Scholarship", "Family", "Other"]
        }
    }
}
