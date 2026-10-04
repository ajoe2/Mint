//
//  EntryEditor.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftData
import SwiftUI

/// The sheet for adding, editing or duplicating an entry.
struct EntryEditor: View {
    let route: EditorRoute
    let ledger: Ledger
    /// Category suggestions for each kind, most used first.
    let categories: [EntryKind: [String]]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft
    /// The draft as opened, to tell what changed.
    @State private var original: EntryDraft
    @State private var isChoosingSaveScope = false
    @State private var isChoosingDeleteScope = false
    @FocusState private var isAmountFocused: Bool

    init(route: EditorRoute, ledger: Ledger, categories: [EntryKind: [String]]) {
        self.route = route
        self.ledger = ledger
        self.categories = categories

        // A duplicate starts as an exact copy, including status, dates and repeat.
        let draft = switch route {
        case .new(let kind): EntryDraft(kind: kind, today: ledger.today, calendar: ledger.calendar)
        case .edit(let entry), .duplicate(let entry): EntryDraft(entry: entry, today: ledger.today, calendar: ledger.calendar)
        }
        self._draft = State(initialValue: draft)
        self._original = State(initialValue: draft)
    }

    private var editedEntry: Entry? {
        if case .edit(let entry) = route { entry } else { nil }
    }

    /// A repeat needs a date to count from, unless it's the rule the entry already had.
    private var canSave: Bool {
        draft.isValid && (draft.frequency == nil || draft.canRepeat || draft.hasSameRepeatRule(as: original))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                WhenSection(draft: $draft, ledger: ledger)
                detailsSection
                Section {
                    TextField("Notes", text: $draft.notes, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
            if editedEntry != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive, action: delete)
                        .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .confirmationDialog("This is a repeating entry", isPresented: $isChoosingSaveScope, titleVisibility: .visible) {
            Button("Save for This Entry Only") {
                if let entry = editedEntry { draft.apply(to: entry, calendar: ledger.calendar) }
                finish()
            }
            Button("Save for Future Entries") {
                if let entry = editedEntry {
                    Scheduler.updateThisAndFuture(entry, with: draft, in: context, today: ledger.today, calendar: ledger.calendar)
                }
                finish()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Change only this entry, or this one and the repeats after it that are still to come?")
        }
        .confirmationDialog("Delete this repeating entry?", isPresented: $isChoosingDeleteScope, titleVisibility: .visible) {
            Button("Delete This Entry Only", role: .destructive) {
                if let entry = editedEntry { context.delete(entry) }
                finish("Delete Entry")
            }
            Button("Delete This and Future Repeats", role: .destructive) {
                if let entry = editedEntry {
                    Scheduler.deleteThisAndFuture(entry, in: context, today: ledger.today, calendar: ledger.calendar)
                }
                finish("Delete Repeats")
            }
            Button("Cancel", role: .cancel) {}
        }
        // Start in the amount field, not the first control.
        .defaultFocus($isAmountFocused, true)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChoiceBar(
                label: "Type",
                choices: EntryKind.allCases.enumerated().map { index, kind in
                    .init(value: kind, title: kind.title, shortcut: KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command))
                },
                selection: $draft.kind,
                highlight: { .init(fill: $0.color.opacity(0.2), text: .primary) },
                isFocusable: false
            )

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(draft.kind.isInflow ? "+" : "−")
                    .foregroundStyle(draft.kind.isInflow ? Theme.paidText : Color.secondary)
                Text(Money.currencySymbol)
                    .foregroundStyle(.secondary)
                TextField("Amount", text: $draft.amountText, prompt: Text(Money.typingExample(0)))
                    .textFieldStyle(.plain)
                    .focused($isAmountFocused)
            }
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()

            TextField("Name", text: $draft.title, prompt: Text(draft.kind.titlePrompt))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            if !draft.amountText.isEmpty && (draft.amountCents ?? 0) <= 0 {
                Text("Enter an amount greater than zero, like \(Money.typingExample(12_50)).")
                    .font(.caption)
                    .foregroundStyle(Theme.unpaidText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var detailsSection: some View {
        Section {
            let suggestions = (categories[draft.kind] ?? draft.kind.defaultCategories).filter {
                draft.category.isEmpty || ($0.localizedStandardContains(draft.category) && $0 != draft.category)
            }
            TextField("Category", text: $draft.category, prompt: Text("None"))
                .textInputSuggestions(suggestions, id: \.self) { suggestion in
                    Text(suggestion).textInputCompletion(suggestion)
                }

            Picker("Repeat", selection: frequency) {
                Text("Never").tag(Frequency?.none)
                Divider()
                ForEach(Frequency.allCases) { frequency in
                    Text(frequency.title).tag(Optional(frequency))
                }
            }

            if draft.frequency != nil {
                Toggle("End repeat", isOn: $draft.hasEndDate.animation())
                if draft.hasEndDate {
                    DatePicker("Ends", selection: $draft.endDate, displayedComponents: .date)
                }
            }
        } footer: {
            if let frequency = draft.frequency {
                Group {
                    if let start = draft.repeatStart {
                        Text("Repeats \(frequency.title.lowercased()) from \(DayText.full(start)).")
                    } else {
                        Text("Add a date or a due date for the repeats to count from.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Picking a repeat for an entry with no dates turns on a due date (today by default) to count from.
    private var frequency: Binding<Frequency?> {
        Binding {
            draft.frequency
        } set: { newValue in
            withAnimation {
                draft.frequency = newValue
                if newValue != nil && !draft.canRepeat {
                    draft.hasDueDate = true
                }
            }
        }
    }

    // MARK: - Saving

    private func save() {
        guard canSave else { return }
        switch route {
        case .new, .duplicate:
            let entry = draft.makeEntry(calendar: ledger.calendar)
            context.insert(entry)
            startSeriesIfRepeating(entry)
            finish()

        case .edit(let entry):
            // Undo can delete the entry while its editor is open.
            guard entry.modelContext != nil, !entry.isDeleted, draft != original else {
                dismiss()
                return
            }
            if !entry.isRepeating {
                draft.apply(to: entry, calendar: ledger.calendar)
                startSeriesIfRepeating(entry)
                finish()
            } else if draft.hasSameRepeatRule(as: original) {
                isChoosingSaveScope = true
            } else {
                // A new repeat rule can only apply going forward.
                Scheduler.updateThisAndFuture(entry, with: draft, in: context, today: ledger.today, calendar: ledger.calendar)
                finish()
            }
        }
    }

    private func startSeriesIfRepeating(_ entry: Entry) {
        guard let frequency = draft.frequency, draft.canRepeat else { return }
        Scheduler.startSeries(
            with: entry,
            frequency: frequency,
            endDate: draft.repeatEndDate(calendar: ledger.calendar),
            in: context,
            today: ledger.today,
            calendar: ledger.calendar
        )
    }

    private func delete() {
        guard let entry = editedEntry, entry.modelContext != nil, !entry.isDeleted else {
            dismiss()
            return
        }
        if entry.isRepeating {
            isChoosingDeleteScope = true
        } else {
            context.delete(entry)
            finish("Delete Entry")
        }
    }

    /// Names the Undo action, saves now, and closes the sheet.
    private func finish(_ actionName: String? = nil) {
        context.undoManager?.setActionName(actionName ?? (editedEntry == nil ? "Add Entry" : "Edit Entry"))
        context.saveNow()
        dismiss()
    }
}
