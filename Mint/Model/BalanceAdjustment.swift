//
//  BalanceAdjustment.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import SwiftData

/// A balance entered to match the bank: the starting balance or a later manual adjustment.
/// The balance counts from the most recent one.
@Model
final class BalanceAdjustment {
    /// The day the balance was entered for.
    var day: Date = Date.now
    /// The balance that was entered.
    var amountCents: Int = 0
    /// The balance at the start of `day`, before entries already paid that day.
    var baseCents: Int = 0
    /// What Mint showed for that day before the adjustment. `nil` for the starting balance.
    var previousCents: Int?
    var createdAt: Date = Date.now

    init(day: Date, amountCents: Int, baseCents: Int, previousCents: Int? = nil) {
        self.day = day
        self.amountCents = amountCents
        self.baseCents = baseCents
        self.previousCents = previousCents
        self.createdAt = .now
    }

    var isStartingBalance: Bool { previousCents == nil }

    /// How much the adjustment moved the balance. `nil` for the starting balance.
    var changeCents: Int? { previousCents.map { amountCents - $0 } }

    var title: String { isStartingBalance ? "Starting balance" : "Manual adjustment" }

    var checkpoint: BalanceCheckpoint {
        BalanceCheckpoint(day: day, baseCents: baseCents, createdAt: createdAt)
    }

    /// What a new balance on `date` is compared against: Mint's balance at the end of that day,
    /// counting only balances set before it (later ones get replaced). `nil` if there are none,
    /// making the new one the starting balance.
    static func previousCents(on date: Date, keeping existing: [BalanceAdjustment], entries: [Entry], ledger: Ledger) -> Int? {
        let day = ledger.day(date)
        let kept = existing.filter { ledger.day($0.day) < day }
        guard !kept.isEmpty else { return nil }
        let keptLedger = Ledger(checkpoints: kept.map(\.checkpoint), today: ledger.today, calendar: ledger.calendar)
        return keptLedger.actualBalance(atEndOf: day, entries)
    }

    /// Records that the bank showed `amountCents` at the end of `date` (any day up to today).
    /// Replaces balances set on or after that day. Entries already paid that day count as part of the amount.
    @discardableResult
    static func record(
        _ amountCents: Int,
        on date: Date,
        replacing existing: [BalanceAdjustment],
        entries: [Entry],
        ledger: Ledger,
        in context: ModelContext
    ) -> BalanceAdjustment {
        let day = ledger.day(date)
        let adjustment = BalanceAdjustment(
            day: day,
            amountCents: amountCents,
            baseCents: ledger.checkpointBase(forBalance: amountCents, on: day, entries),
            previousCents: previousCents(on: day, keeping: existing, entries: entries, ledger: ledger)
        )
        for replaced in existing where ledger.day(replaced.day) >= day {
            context.delete(replaced)
        }
        context.insert(adjustment)
        return adjustment
    }

    /// Sets the first balance, from the welcome screen. Kept out of Undo, since undoing it would
    /// leave no balance to count from.
    static func setStartingBalance(_ amountCents: Int, on date: Date, in context: ModelContext) {
        let undoManager = context.undoManager
        undoManager?.disableUndoRegistration()
        context.insert(BalanceAdjustment(day: Calendar.current.startOfDay(for: date), amountCents: amountCents, baseCents: amountCents))
        context.saveNow()
        undoManager?.enableUndoRegistration()
    }

    /// Deletes a balance. Deleting the starting balance makes the next one the starting balance.
    static func delete(_ adjustment: BalanceAdjustment, from all: [BalanceAdjustment], in context: ModelContext) {
        let actionName = adjustment.isStartingBalance ? "Delete Starting Balance" : "Delete Adjustment"
        let sorted = all.sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        if sorted.first === adjustment, sorted.count > 1 {
            sorted[1].previousCents = nil
        }
        context.delete(adjustment)
        context.undoManager?.setActionName(actionName)
        context.saveNow()
    }
}
