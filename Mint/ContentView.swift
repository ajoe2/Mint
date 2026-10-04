//
//  ContentView.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import AppKit
import Combine
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Query(sort: \BalanceAdjustment.day) private var adjustments: [BalanceAdjustment]

    /// Updated when the day changes, so scheduled entries become paid on their date.
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        @Bindable var app = app
        let ledger = Ledger(checkpoints: adjustments.map(\.checkpoint), today: today)
        // Copied once per change to the data. Switching tabs and searching happen in `MainView`,
        // so they don't redo this.
        let items = entries.map { LedgerEntry($0) }

        Group {
            // With no balance yet, the welcome screen fills the window. It isn't a sheet, so it
            // never blocks quitting.
            if adjustments.isEmpty {
                WelcomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minWidth: 760, minHeight: 520)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .toolbar(removing: .title)
            } else {
                MainView(entries: items, adjustments: adjustments, ledger: ledger)
            }
        }
        // Whatever changes the data, whether an edit, Undo, a new balance or a new day, the rows,
        // amounts, bars and chart move to match it.
        .animation(Motion.standard, value: items)
        .animation(Motion.standard, value: ledger)
        .sheet(item: $app.editor) { route in
            if route.isAvailable {
                EntryEditor(route: route, ledger: ledger, categories: categorySuggestions)
            }
        }
        .onChange(of: adjustments.isEmpty, initial: true) { _, isEmpty in
            app.isSettingUp = isEmpty
        }
        .onChange(of: entries.count) {
            // Undo can delete the entry an open editor is showing.
            if app.editor?.isAvailable == false { app.editor = nil }
        }
        .onChange(of: undoManager, initial: true) {
            modelContext.undoManager = undoManager
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
            modelContext.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
            modelContext.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            modelContext.saveNow()
        }
        .task(id: today) {
            Scheduler.extendAll(in: modelContext, today: today)
        }
        .schedulesReminders(for: items, ledger: ledger)
    }

    private func refreshToday() {
        let now = Calendar.current.startOfDay(for: .now)
        if now != today { today = now }
    }

    /// Category suggestions per kind: ones in use (most used first), then the unused defaults.
    private var categorySuggestions: [EntryKind: [String]] {
        var suggestions: [EntryKind: [String]] = [:]
        for kind in EntryKind.allCases {
            var counts: [String: Int] = [:]
            for entry in entries where entry.kind == kind && !entry.category.isEmpty {
                counts[entry.category, default: 0] += 1
            }
            let used = counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map(\.key)
            suggestions[kind] = used + kind.defaultCategories.filter { !used.contains($0) }
        }
        return suggestions
    }
}

/// The tabs, toolbar and search. Kept apart from `ContentView` so tab switches and keystrokes
/// update only this, not the copies of the data.
private struct MainView: View {
    let entries: [LedgerEntry]
    let adjustments: [BalanceAdjustment]
    let ledger: Ledger

    @Environment(AppModel.self) private var app
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            // A ZStack, not a Group, so the fade below covers the screen coming in, too.
            ZStack {
                switch app.selection {
                case .overview:
                    OverviewView(entries: entries, ledger: ledger)
                case .transactions:
                    TransactionsView(entries: entries, adjustments: adjustments, ledger: ledger)
                case .statistics:
                    StatisticsView(entries: entries, adjustments: adjustments, ledger: ledger)
                }
            }
            // Clicks and every shortcut fade from one tab to the next.
            .animation(Motion.fade, value: app.selection)
            .frame(minWidth: 760, minHeight: 520)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Mint's own selector, not the system one, so the highlight slides when a
                    // shortcut changes the tab, not only when it's clicked. ⌘1–⌘3 already move
                    // between tabs, so it stays out of the Tab order.
                    ChoiceBar(
                        label: "Section",
                        choices: Screen.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $app.selection,
                        isFocusable: false
                    )
                    .animation(Motion.quick, value: app.selection)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Entry", systemImage: "plus") {
                        app.editor = .new(app.newEntryKind)
                    }
                    .help("Add an entry (⌘N)")
                }
            }
            // On every tab so the toolbar stays put. Results show in Transactions.
            .searchable(text: $app.searchText, placement: .toolbar, prompt: "Search")
            .searchFocused($isSearchFocused)
            .onChange(of: app.searchText) {
                if !app.searchText.isEmpty { app.selection = .transactions }
            }
            // Return in the search field moves focus to the results for arrow-key navigation.
            .onSubmit(of: .search) {
                app.selection = .transactions
                app.listFocusRequest += 1
            }
            .onChange(of: app.searchFocusRequest) { isSearchFocused = true }
            .background { TabShortcuts() }
        }
    }
}

/// More ways to switch tabs besides ⇧⌘] and ⇧⌘[ in the View menu: ⌥⌘→ and ⌥⌘← as in Safari and
/// Chrome, and ⌃⇥ and ⌃⇧⇥ as in most tabbed apps. A menu item can show only one shortcut, and
/// SwiftUI shortcuts can't tell ⌃⇥ from ⌃⇧⇥, so this watches key presses in its window directly.
private struct TabShortcuts: NSViewRepresentable {
    @Environment(AppModel.self) private var app

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let offset = coordinator.offset(for: event) else { return event }
            coordinator.app.selection = coordinator.app.selection.moved(by: offset)
            return nil
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.app = app
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.monitor.map(NSEvent.removeMonitor)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(app: app)
    }

    final class Coordinator {
        var app: AppModel
        weak var view: NSView?
        var monitor: Any?

        init(app: AppModel) {
            self.app = app
        }

        /// +1 for the next tab, -1 for the previous one, or `nil` if `event` isn't a tab shortcut for this window.
        func offset(for event: NSEvent) -> Int? {
            guard app.isBrowsing, let window = view?.window, event.window === window else { return nil }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch (event.keyCode, modifiers) {
            case (124, [.command, .option]), (48, [.control]): return 1  // → or Tab
            case (123, [.command, .option]), (48, [.control, .shift]): return -1  // ← or ⇧Tab
            default: return nil
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .modelContainer(for: AppEnvironment.models, inMemory: true)
}
