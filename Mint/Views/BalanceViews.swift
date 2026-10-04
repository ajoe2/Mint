//
//  BalanceViews.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftData
import SwiftUI

/// The large amount field, with currency symbol, for typing in a balance.
private struct BigAmountField: View {
    let title: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Money.currencySymbol)
                .foregroundStyle(.secondary)
            TextField(title, text: $text, prompt: Text(Money.typingExample(0)))
                .textFieldStyle(.plain)
                .focused(isFocused)
        }
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .monospacedDigit()
    }
}

/// Sets the starting balance. Shown whenever there's no balance yet: on first launch and after a reset.
struct WelcomeView: View {
    @Environment(\.modelContext) private var context

    @State private var amountText = ""
    @State private var asOf = Date.now
    @FocusState private var isAmountFocused: Bool

    private var parsedCents: Int? {
        Money.parseSignedCents(amountText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Mint")
                    .font(.system(.title, design: .rounded).bold())
                Text("What's in your bank account right now?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            BigAmountField(title: "Current balance", text: $amountText, isFocused: $isAmountFocused)

            DatePicker("As of", selection: $asOf, in: ...Date.now, displayedComponents: .date)
                .fixedSize()

            Button("Get Started", action: finish)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(parsedCents == nil)
        }
        .padding(32)
        .frame(width: 440)
        .onAppear { isAmountFocused = true }
    }

    private func finish() {
        guard let cents = parsedCents else { return }
        BalanceAdjustment.setStartingBalance(cents, on: asOf, in: context)
    }
}

/// Sets the balance to what the bank showed on any day up to today, as a manual adjustment
/// the balance then counts from.
struct AdjustBalanceView: View {
    let ledger: Ledger
    let entries: [Entry]
    let adjustments: [BalanceAdjustment]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var day: Date
    @FocusState private var isAmountFocused: Bool

    init(ledger: Ledger, entries: [Entry], adjustments: [BalanceAdjustment]) {
        self.ledger = ledger
        self.entries = entries
        self.adjustments = adjustments
        self._amountText = State(initialValue: Money.editingText(fromCents: ledger.currentBalance(entries)))
        self._day = State(initialValue: ledger.today)
    }

    private var amountCents: Int? {
        Money.parseSignedCents(amountText)
    }

    /// Balances on or after the chosen day, which this one replaces.
    private var replaced: [BalanceAdjustment] {
        adjustments.filter { ledger.day($0.day) >= ledger.day(day) }
    }

    /// What the new balance is compared against; the adjustment records the same number.
    private var previousCents: Int? {
        BalanceAdjustment.previousCents(on: day, keeping: adjustments, entries: entries, ledger: ledger)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adjust Balance")
                    .font(.system(.title2, design: .rounded).bold())
                Text("Enter what your bank shows.")
                    .foregroundStyle(.secondary)
            }

            BigAmountField(title: "Bank balance", text: $amountText, isFocused: $isAmountFocused)

            DatePicker("As of", selection: $day, in: ...ledger.today, displayedComponents: .date)
                .fixedSize()

            VStack(spacing: 8) {
                HStack {
                    // The comparison leaves out balances being replaced.
                    Text(replaced.isEmpty ? "Mint shows" : "Mint shows without \(replaced.count == 1 ? "it" : "them")")
                    Spacer()
                    Text(previousCents.map { Money.format($0) } ?? "—")
                        .monospacedDigit()
                }
                HStack {
                    Text("Change")
                    Spacer()
                    if let amountCents, let previousCents {
                        let change = amountCents - previousCents
                        Text(Money.format(change, showPlus: true))
                            .monospacedDigit()
                            .foregroundStyle(Theme.signed(change))
                    } else if amountCents != nil {
                        Text("New starting balance")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .fontWeight(.semibold)
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                if !replaced.isEmpty {
                    Label(replacedMessage, systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.scheduledText)
                }
                Text("Anything already paid on or before this date is treated as part of this amount. Anything after it changes the balance from here.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Adjust", action: save)
                    .disabled(amountCents == nil)
            }
        }
        .onAppear { isAmountFocused = true }
    }

    private var replacedMessage: String {
        if replaced.count == 1, let only = replaced.first {
            return "Replaces your \(only.title.lowercased()) from \(DayText.full(only.day))."
        }
        return "Replaces \(replaced.count) balances set on or after this date."
    }

    private func save() {
        guard let amountCents else { return }
        BalanceAdjustment.record(amountCents, on: day, replacing: adjustments, entries: entries, ledger: ledger, in: context)
        context.undoManager?.setActionName("Adjust Balance")
        context.saveNow()
        dismiss()
    }
}

/// The Settings window: reminders, balance history, and a way to start over.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: [
        SortDescriptor(\BalanceAdjustment.day, order: .reverse),
        SortDescriptor(\BalanceAdjustment.createdAt, order: .reverse),
    ])
    private var adjustments: [BalanceAdjustment]

    @State private var pendingDeletion: BalanceAdjustment?
    @State private var isConfirmingReset = false

    /// "starting balance" or "manual adjustment", for the delete dialog. The main window can
    /// replace the balance while the dialog is open, so check it still exists.
    private var pendingTitle: String {
        guard let pendingDeletion, pendingDeletion.modelContext != nil else { return "balance" }
        return pendingDeletion.title.lowercased()
    }

    var body: some View {
        Form {
            ReminderSettingsSection()

            Section {
                if adjustments.isEmpty {
                    Text("No balance has been set yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(adjustments) { adjustment in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adjustment.title)
                            Text(DayText.full(adjustment.day))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.format(adjustment.amountCents))
                                .monospacedDigit()
                            if let change = adjustment.changeCents {
                                Text(Money.format(change, showPlus: true))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if adjustments.count > 1 {
                            Button("Delete", systemImage: "trash") {
                                pendingDeletion = adjustment
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Delete")
                        }
                    }
                }
            } header: {
                Text("Balance History")
            } footer: {
                Text("Your balance counts from the most recent one. To set it again, choose File ▸ Adjust Balance… (⇧⌘B).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Reset…", role: .destructive) { isConfirmingReset = true }
                } label: {
                    Text("Reset Mint")
                    Text("Erases every entry, balance and setting, and starts over.")
                }
            } header: {
                Text("Reset")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
        .confirmationDialog(
            "Delete this \(pendingTitle)?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion, pendingDeletion.modelContext != nil {
                    BalanceAdjustment.delete(pendingDeletion, from: adjustments, in: context)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingTitle == "starting balance"
                ? "The next balance becomes your starting balance."
                : "Your balance will count from the one before it.")
        }
        .alert("Reset Mint?", isPresented: $isConfirmingReset) {
            Button("Erase Everything", role: .destructive) {
                // Close any open editor or sheet first, so nothing shows deleted entries.
                app.reset()
                AppReset.eraseAll(in: context, defaults: AppEnvironment.defaults)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All of your entries, repeating entries, balances and settings will be permanently deleted. This can't be undone.")
        }
    }
}
