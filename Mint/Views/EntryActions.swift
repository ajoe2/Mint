//
//  EntryActions.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftData
import SwiftUI

/// Entry actions shared by right-click menus and quick buttons. Each change saves right away.
struct EntryActions {
    let context: ModelContext
    let app: AppModel
    let ledger: Ledger

    func edit(_ entry: Entry) {
        app.editor = .edit(entry)
    }

    func duplicate(_ entry: Entry) {
        app.editor = .duplicate(entry)
    }

    /// Marks it paid (or received, or invested) as of today.
    func complete(_ entry: Entry) {
        withAnimation { entry.date = ledger.today }
        context.undoManager?.setActionName(Self.completeTitle(for: entry.kind))
        context.saveNow()
    }

    /// Clears the date, making it unpaid again.
    func uncomplete(_ entry: Entry) {
        withAnimation { entry.date = nil }
        context.undoManager?.setActionName(Self.uncompleteTitle(for: entry.kind))
        context.saveNow()
    }

    func delete(_ entry: Entry) {
        withAnimation { context.delete(entry) }
        context.undoManager?.setActionName("Delete Entry")
        context.saveNow()
    }

    func deleteThisAndFuture(_ entry: Entry) {
        withAnimation { Scheduler.deleteThisAndFuture(entry, in: context, today: ledger.today, calendar: ledger.calendar) }
        context.undoManager?.setActionName("Delete Repeats")
        context.saveNow()
    }

    static func completeTitle(for kind: EntryKind) -> String {
        "Mark as \(kind.completedLabel) Today"
    }

    static func uncompleteTitle(for kind: EntryKind) -> String {
        switch kind {
        case .spend: "Mark as Unpaid"
        case .income, .subsidy: "Mark as Not Received"
        case .investment: "Mark as Not Invested"
        }
    }

    /// Right-click menu items for an entry.
    @ViewBuilder
    func menu(for entry: Entry) -> some View {
        Button("Edit…", systemImage: "pencil") { edit(entry) }
        Button("Duplicate…", systemImage: "plus.square.on.square") { duplicate(entry) }
        Divider()
        if ledger.status(of: entry) == .paid {
            Button(Self.uncompleteTitle(for: entry.kind), systemImage: "arrow.uturn.backward") { uncomplete(entry) }
        } else {
            Button(Self.completeTitle(for: entry.kind), systemImage: "checkmark.circle") { complete(entry) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
        if entry.isRepeating {
            Button("Delete This and Future Repeats", systemImage: "trash", role: .destructive) {
                deleteThisAndFuture(entry)
            }
        }
    }
}
