//
//  Keyboard.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftData
import SwiftUI

/// Which row is selected on a page. Rows read it to highlight themselves and to open their
/// status popover; the selection only shows while the page has keyboard focus.
@Observable
final class RowSelection {
    var selected: PersistentIdentifier?
    /// The row whose status popover is open.
    var statusPopover: PersistentIdentifier?
    var isActive = false

    func isSelected(_ entry: Entry) -> Bool {
        isActive && selected == entry.persistentModelID
    }

    /// The row `key` (↑, ↓, Home or End) moves to among `ids`, in the order they're shown.
    static func target(of key: KeyEquivalent, from selected: PersistentIdentifier?, in ids: [PersistentIdentifier]) -> PersistentIdentifier? {
        guard !ids.isEmpty else { return nil }
        let current = selected.flatMap { ids.firstIndex(of: $0) }
        let index: Int
        switch key {
        case .upArrow: index = max((current ?? ids.count) - 1, 0)
        case .downArrow: index = min((current ?? -1) + 1, ids.count - 1)
        case .home: index = 0
        case .end: index = ids.count - 1
        default: return selected
        }
        return ids[index]
    }

    /// The row to select once `id` leaves the list: the one after it, or else the one before.
    static func neighbor(of id: PersistentIdentifier, in ids: [PersistentIdentifier]) -> PersistentIdentifier? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        return index + 1 < ids.count ? ids[index + 1] : (index > 0 ? ids[index - 1] : nil)
    }
}

/// The entry selected on the focused page, and what the Entry menu can do with it.
struct SelectedEntry {
    let entry: Entry
    let isPaid: Bool
    let edit: () -> Void
    let changeStatus: () -> Void
    let togglePaid: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let deleteFuture: () -> Void
}

extension FocusedValues {
    @Entry var selectedEntry: SelectedEntry?
}

extension View {
    /// Lets the keyboard move through `entries`, this page's rows in display order. The page is one
    /// Tab stop: ↑ and ↓ move the selection, ⌘↑ and ⌘↓ (or Home and End) jump to the ends, Esc clears it, and
    /// Return, Space and Delete act on the selected entry like the Entry menu.
    /// `onSideways` handles ← (-1) and → (+1) on pages with a choice to flip through.
    func keyboardRows(_ entries: [Entry], selection: RowSelection, ledger: Ledger, onSideways: ((Int) -> Void)? = nil) -> some View {
        modifier(KeyboardRows(entries: entries, selection: selection, ledger: ledger, onSideways: onSideways))
    }
}

private struct KeyboardRows: ViewModifier {
    let entries: [Entry]
    let selection: RowSelection
    let ledger: Ledger
    let onSideways: ((Int) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @FocusState private var isFocused: Bool

    private var ids: [PersistentIdentifier] {
        entries.map(\.persistentModelID)
    }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .focusable(interactions: .edit)
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.upArrow, .downArrow, .home, .end]) { press in
                    // ⌘↑ and ⌘↓ (or ⌥) jump to the first and last rows, as in Finder and Mail.
                    var key = press.key
                    if !press.modifiers.isDisjoint(with: [.command, .option]) {
                        key = key == .upArrow ? .home : key == .downArrow ? .end : key
                    }
                    guard let target = RowSelection.target(of: key, from: selection.selected, in: ids) else { return .ignored }
                    select(target, proxy: proxy)
                    return .handled
                }
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    guard let onSideways else { return .ignored }
                    onSideways(press.key == .leftArrow ? -1 : 1)
                    return .handled
                }
                .onKeyPress(.return) { perform { $0.edit() } }
                .onKeyPress(.space) { perform { $0.changeStatus() } }
                // The Delete key sends U+007F, which SwiftUI's `.delete` (U+0008) doesn't match.
                .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")]) { _ in perform { $0.delete() } }
                .onExitCommand { selection.selected = nil }
                .focusedValue(\.selectedEntry, selectedEntry)
                .onChange(of: isFocused, initial: true) { selection.isActive = isFocused }
                .onChange(of: ids) { old, new in
                    // If the selected entry leaves the list, select whatever took its place.
                    guard let id = selection.selected, !new.contains(id) else { return }
                    let index = old.firstIndex(of: id) ?? 0
                    selection.selected = new.isEmpty ? nil : new[min(index, new.count - 1)]
                }
                .onChange(of: app.listFocusRequest) {
                    if let first = ids.first { select(first, proxy: proxy) }
                }
                .onAppear {
                    // Take focus for the arrow keys, unless the user is typing a search.
                    if app.searchText.isEmpty { isFocused = true }
                }
        }
        .environment(selection)
    }

    private func select(_ id: PersistentIdentifier, proxy: ScrollViewProxy) {
        selection.selected = id
        isFocused = true
        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
    }

    private func perform(_ action: (SelectedEntry) -> Void) -> KeyPress.Result {
        guard let selectedEntry else { return .ignored }
        action(selectedEntry)
        return .handled
    }

    private var selectedEntry: SelectedEntry? {
        guard let id = selection.selected, let entry = entries.first(where: { $0.persistentModelID == id }) else { return nil }
        let actions = EntryActions(context: context, app: app, ledger: ledger)
        let isPaid = ledger.status(of: entry) == .paid
        // Like Mail, finishing with an entry moves the selection to the next row (or the previous one at the end).
        let moveOn = { selection.selected = RowSelection.neighbor(of: id, in: ids) }
        return SelectedEntry(
            entry: entry,
            isPaid: isPaid,
            edit: { actions.edit(entry) },
            changeStatus: { selection.statusPopover = id },
            togglePaid: {
                moveOn()
                if isPaid { actions.uncomplete(entry) } else { actions.complete(entry) }
            },
            duplicate: { actions.duplicate(entry) },
            delete: {
                moveOn()
                actions.delete(entry)
            },
            deleteFuture: {
                moveOn()
                actions.deleteThisAndFuture(entry)
            }
        )
    }
}

/// The Entry menu: what can be done to the entry selected on the focused page.
struct EntryCommands: Commands {
    @FocusedValue(\.selectedEntry) private var selected

    var body: some Commands {
        CommandMenu("Entry") {
            Group {
                // Return and Space also work in the list. Menus use ⌘O (Open) and ⌘I (Get Info), as in Finder and Mail.
                Button("Edit…") { selected?.edit() }
                    .keyboardShortcut("o")
                Button("Change Status…") { selected?.changeStatus() }
                    .keyboardShortcut("i")
                Divider()
                // Like Mark as Completed in Reminders.
                Button(toggleTitle) { selected?.togglePaid() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Duplicate…") { selected?.duplicate() }
                    .keyboardShortcut("d")
                Divider()
                Button("Delete") { selected?.delete() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button("Delete This and Future Repeats") { selected?.deleteFuture() }
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
                    .disabled(selected?.entry.isRepeating != true)
            }
            .disabled(selected == nil)
        }
    }

    private var toggleTitle: String {
        guard let selected else { return "Mark as Paid Today" }
        return selected.isPaid
            ? EntryActions.uncompleteTitle(for: selected.entry.kind)
            : EntryActions.completeTitle(for: selected.entry.kind)
    }
}

/// Replaces the Help menu with a Keyboard Shortcuts item that opens the shortcuts window.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            // ⌘?, the standard Help shortcut.
            Button("Keyboard Shortcuts") { openWindow(id: ShortcutsView.windowID) }
                .keyboardShortcut("?")
        }
    }
}
