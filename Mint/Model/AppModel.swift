//
//  AppModel.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import Observation
import SwiftData

/// Window-level state that the menu commands and the views share.
@Observable
final class AppModel {
    var selection: Screen = .overview
    var editor: EditorRoute?
    var isAdjustingBalance = false
    /// The toolbar search text. Results show in Transactions.
    var searchText = ""
    var transactionFilter = TransactionFilter.all
    /// True while the welcome screen asks for a starting balance.
    var isSettingUp = false
    /// Bumped to focus the toolbar search field (Edit ▸ Find…).
    var searchFocusRequest = 0
    /// Bumped to focus the visible list and select its first row, e.g. after Return in search.
    var listFocusRequest = 0

    /// True when the tabs show with no sheet over them, so menu commands can act.
    var isBrowsing: Bool {
        !isSettingUp && editor == nil && !isAdjustingBalance
    }

    /// The kind a new entry starts as: the one Transactions is filtered to, or a spend.
    var newEntryKind: EntryKind {
        selection == .transactions ? transactionFilter.entryKind ?? .spend : .spend
    }

    /// Returns to Overview with nothing open, after Settings erases everything.
    func reset() {
        selection = .overview
        editor = nil
        isAdjustingBalance = false
        searchText = ""
        transactionFilter = .all
    }
}

/// The three tabs.
enum Screen: String, CaseIterable, Identifiable {
    case overview
    case transactions
    case statistics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .transactions: "Transactions"
        case .statistics: "Statistics"
        }
    }

    /// The tab `offset` places away, wrapping around at either end.
    func moved(by offset: Int) -> Screen {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + offset + all.count) % all.count]
    }
}

/// What Transactions shows: everything (balance adjustments included), or one kind.
enum TransactionFilter: Hashable {
    case all
    case kind(EntryKind)

    static let allCases: [TransactionFilter] = [.all] + EntryKind.allCases.map(Self.kind)

    var title: String {
        switch self {
        case .all: "All"
        case .kind(let kind): kind.pluralTitle
        }
    }

    var entryKind: EntryKind? {
        if case .kind(let kind) = self { kind } else { nil }
    }
}

/// What the entry editor sheet is showing.
enum EditorRoute: Hashable, Identifiable {
    case new(EntryKind)
    case edit(Entry)
    case duplicate(Entry)

    var id: Self { self }

    /// The entry being edited or copied.
    var entry: Entry? {
        switch self {
        case .new: nil
        case .edit(let entry), .duplicate(let entry): entry
        }
    }

    /// False once the entry is deleted, e.g. by Undo while the editor is open.
    var isAvailable: Bool {
        guard let entry else { return true }
        return entry.modelContext != nil && !entry.isDeleted
    }
}

/// Keys for the settings kept in UserDefaults.
enum SettingsKey {
    static let statsPeriod = "statsPeriod"
    static let dueDateReminders = "dueDateReminders"
    static let lowBalanceReminders = "lowBalanceReminders"
    static let lowBalanceLimit = "lowBalanceLimit"
    static let reminderDaysBefore = "reminderDaysBefore"
    static let reminderTime = "reminderTime"

    /// Every setting, for erasing them all.
    static let all = [statsPeriod, dueDateReminders, lowBalanceReminders, lowBalanceLimit, reminderDaysBefore, reminderTime]
}
