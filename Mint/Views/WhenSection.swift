//
//  WhenSection.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftUI

/// Status (unpaid, scheduled, paid), its date, and the due date. Used by the entry editor and the
/// popover on a row's status label.
struct WhenSection: View {
    @Binding var draft: EntryDraft
    let ledger: Ledger
    /// Focuses the status choices on appear, so ← and → change it.
    var focusesStatus = false

    private var status: Binding<EntryStatus> {
        Binding {
            draft.status(today: ledger.today, calendar: ledger.calendar)
        } set: { newValue in
            withAnimation { draft.setStatus(newValue, today: ledger.today, calendar: ledger.calendar) }
        }
    }

    private var endOfToday: Date {
        ledger.addingDays(1, to: ledger.today).addingTimeInterval(-1)
    }

    var body: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                ChoiceBar(
                    label: "Status",
                    choices: EntryStatus.allCases.map { .init(value: $0, title: $0.label(for: draft.kind)) },
                    selection: status,
                    highlight: { .init(fill: $0.color.opacity(0.2), text: $0.textColor) },
                    focusOnAppear: focusesStatus
                )
            }

            switch status.wrappedValue {
            case .unpaid:
                EmptyView()
            case .scheduled:
                DatePicker("Scheduled for", selection: $draft.date, in: ledger.addingDays(1, to: ledger.today)..., displayedComponents: .date)
            case .paid:
                DatePicker("\(draft.kind.completedLabel) on", selection: $draft.date, in: ...endOfToday, displayedComponents: .date)
            }

            LabeledContent("Due date") {
                if draft.hasDueDate {
                    HStack(spacing: 6) {
                        DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                            .labelsHidden()
                        Button("Remove Due Date", systemImage: "xmark.circle.fill") {
                            withAnimation { draft.hasDueDate = false }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(Self.dueDateShortcut)
                        .help("Remove due date (\(Self.dueDateShortcut.symbols))")
                    }
                } else {
                    Button("Add") {
                        withAnimation { draft.hasDueDate = true }
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(Self.dueDateShortcut)
                    .help("Add a due date (\(Self.dueDateShortcut.symbols))")
                }
            }
        } footer: {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Adds or removes the due date.
    static let dueDateShortcut = KeyboardShortcut("d", modifiers: [.command, .shift])

    /// A sentence on how the status affects the balance.
    private var statusMessage: String {
        let kind = draft.kind
        switch draft.status(today: ledger.today, calendar: ledger.calendar) {
        case .paid:
            if ledger.day(draft.date) < ledger.balanceStartDay {
                return "This is before your balance was last set, so it won't change your balance."
            }
            return "Counts toward your balance."
        case .scheduled:
            return "Counts as \(kind.completedLabel.lowercased()) automatically on \(DayText.full(draft.date))."
        case .unpaid:
            return "Won't change your balance until it's scheduled or marked \(kind.completedLabel.lowercased())."
        }
    }
}
