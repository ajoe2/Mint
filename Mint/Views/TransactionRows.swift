//
//  TransactionRows.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import AppKit
import SwiftData
import SwiftUI

/// One entry: icon, name, detail line, status mark and amount. Click to edit, right-click for
/// quick actions, or click the status mark to change the status and dates.
struct EntryRowView<Trailing: View>: View {
    let entry: Entry
    let ledger: Ledger
    /// The projected balance right after this entry, shown in coming-up lists.
    var balanceAfter: Int?
    @ViewBuilder var trailing: Trailing

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(RowSelection.self) private var selection: RowSelection?
    @State private var isHovering = false
    @State private var isShowingStatusAlone = false

    /// Room for amounts up to six figures.
    private static var amountWidth: CGFloat { 108 }

    init(entry: Entry, ledger: Ledger, balanceAfter: Int? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.entry = entry
        self.ledger = ledger
        self.balanceAfter = balanceAfter
        self.trailing = trailing()
    }

    private var actions: EntryActions {
        EntryActions(context: context, app: app, ledger: ledger)
    }

    /// Driven by the page's selection, so Space can open it, or by the row when there's no selection.
    private var isChangingStatus: Binding<Bool> {
        Binding {
            selection.map { $0.statusPopover == entry.persistentModelID } ?? isShowingStatusAlone
        } set: { isShowing in
            if let selection {
                if isShowing {
                    selection.statusPopover = entry.persistentModelID
                } else if selection.statusPopover == entry.persistentModelID {
                    selection.statusPopover = nil
                }
            } else {
                isShowingStatusAlone = isShowing
            }
        }
    }

    private var isSelected: Bool {
        selection?.isSelected(entry) ?? false
    }

    var body: some View {
        let mark = StatusMarkContent(entry: entry, ledger: ledger)
        HStack(spacing: 12) {
            KindIcon(kind: entry.kind, category: entry.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let series = entry.series {
                        Image(systemName: "repeat")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .help("Repeats \(series.frequency.title.lowercased())")
                    }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                isChangingStatus.wrappedValue = true
            } label: {
                StatusMark(text: mark.text, status: mark.status, symbol: mark.symbol, isProminent: mark.isProminent)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("\(mark.help). Click to change.")
            .popover(isPresented: isChangingStatus, arrowEdge: .bottom) {
                StatusPopover(entry: entry, ledger: ledger)
            }
            VStack(alignment: .trailing, spacing: 1) {
                AmountText(cents: entry.signedCents)
                if let balanceAfter {
                    Text("→ \(Money.format(balanceAfter))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(balanceAfter < 0 ? Theme.unpaidText : Color.secondary)
                        .help("Your balance after this")
                }
            }
            // One width for every amount, so the status marks line up down the list.
            .frame(minWidth: Self.amountWidth, alignment: .trailing)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovering ? 0.04 : 0))
                .padding(4)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture {
            selection?.selected = entry.persistentModelID
            actions.edit(entry)
        }
        .contextMenu { actions.menu(for: entry) }
        .id(entry.persistentModelID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(mark))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.edit(entry) }
        .accessibilityAction(named: "Change Status") { isChangingStatus.wrappedValue = true }
        .accessibilityAction(named: mark.status == .paid
            ? EntryActions.uncompleteTitle(for: entry.kind)
            : EntryActions.completeTitle(for: entry.kind)
        ) {
            if mark.status == .paid { actions.uncomplete(entry) } else { actions.complete(entry) }
        }
    }

    /// "Housing · Thu, Oct 9", "Due Tomorrow", "No date".
    private var detail: String {
        let when: String
        switch ledger.status(of: entry) {
        case .paid, .scheduled:
            when = DayText.relative(entry.date ?? ledger.today, today: ledger.today, calendar: ledger.calendar)
        case .unpaid:
            when = entry.dueDate.map { "Due \(DayText.relative($0, today: ledger.today, calendar: ledger.calendar))" } ?? "No date"
        }
        return entry.category.isEmpty ? when : "\(entry.category) · \(when)"
    }

    /// The whole row as one VoiceOver sentence.
    private func accessibilityLabel(_ mark: StatusMarkContent) -> String {
        var parts = [entry.title, Money.format(entry.signedCents, showPlus: true), detail, mark.text]
        if let balanceAfter {
            parts.append("balance after, \(Money.format(balanceAfter))")
        }
        return parts.joined(separator: ", ")
    }
}

/// What a row's status mark shows. Paid is a green check and scheduled an amber clock; the
/// date beside the name says when. Unpaid says so in red, filled solid with the reason when
/// something needs doing.
private struct StatusMarkContent {
    var text: String
    var status: EntryStatus
    var symbol: String?
    var isProminent = false
    var help: String

    init(entry: Entry, ledger: Ledger) {
        status = ledger.status(of: entry)
        if ledger.isOverdue(entry) {
            text = "Overdue"
            isProminent = true
            help = "Its due date has passed and it isn't \(entry.kind.completedLabel.lowercased()) yet"
        } else if ledger.isDueSoon(entry) {
            text = "Due soon"
            isProminent = true
            help = "Due within a week and not scheduled yet"
        } else if ledger.isScheduledLate(entry) {
            text = "Late"
            isProminent = true
            help = "Scheduled for after its due date"
        } else {
            text = status.label(for: entry.kind)
            switch status {
            case .unpaid:
                help = "Nothing is scheduled yet, so it doesn't change your balance"
            case .scheduled:
                symbol = "clock"
                help = "\(text): counts as \(entry.kind.completedLabel.lowercased()) automatically on its date"
            case .paid:
                symbol = "checkmark.circle.fill"
                help = "\(text): counts toward your balance"
            }
        }
    }
}

/// The status, date and due date fields from the editor, opened from a row's status mark. Saves on
/// close, so the row stays put while you pick dates.
private struct StatusPopover: View {
    let entry: Entry
    let ledger: Ledger

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft

    init(entry: Entry, ledger: Ledger) {
        self.entry = entry
        self.ledger = ledger
        self._draft = State(initialValue: EntryDraft(entry: entry, today: ledger.today, calendar: ledger.calendar))
    }

    var body: some View {
        Form {
            WhenSection(draft: $draft, ledger: ledger, focusesStatus: true)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Return closes it like Esc; both keep the change.
        .onKeyPress(.return) {
            dismiss()
            return .handled
        }
        .onDisappear(perform: save)
        // Quitting doesn't close the popover, so save on quit too.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in save() }
    }

    private func save() {
        guard entry.modelContext != nil, !entry.isDeleted else { return }
        let dates = draft.storedDates(for: entry, calendar: ledger.calendar)
        guard dates.date != entry.date || dates.dueDate != entry.dueDate else { return }
        withAnimation(Motion.standard) {
            entry.date = dates.date
            entry.dueDate = dates.dueDate
        }
        context.undoManager?.setActionName("Change Status")
        context.saveNow()
    }
}

/// The starting balance or a manual adjustment, shown among the transactions.
struct AdjustmentRowView: View {
    let adjustment: BalanceAdjustment
    let today: Date

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(symbol: "slider.horizontal.3", color: .gray, label: adjustment.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(adjustment.title)
                    .fontWeight(.medium)
                Text("Set to \(Money.format(adjustment.amountCents)) · \(DayText.relative(adjustment.day, today: today))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let change = adjustment.changeCents {
                AmountText(cents: change)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
