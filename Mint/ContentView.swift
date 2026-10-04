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
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var app = app
        let ledger = Ledger(checkpoints: adjustments.map(\.checkpoint), today: today)

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
                main(ledger: ledger)
            }
        }
        .sheet(item: $app.editor) { route in
            if route.isAvailable {
                EntryEditor(route: route, ledger: ledger, categories: categorySuggestions)
            }
        }
        .sheet(isPresented: $app.isAdjustingBalance) {
            AdjustBalanceView(ledger: ledger, entries: entries, adjustments: adjustments)
        }
        .onChange(of: adjustments.isEmpty, initial: true) { _, isEmpty in
            app.isSettingUp = isEmpty
        }
        .onChange(of: entries.count) {
            // Undo can delete the entry an open editor is showing.
            if app.editor?.isAvailable == false { app.editor = nil }
        }
        .onAppear {
            modelContext.undoManager = undoManager
        }
        .onChange(of: undoManager) {
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
        .schedulesReminders(for: entries, ledger: ledger)
    }

    private func main(ledger: Ledger) -> some View {
        @Bindable var app = app
        return NavigationStack {
            Group {
                switch app.selection {
                case .overview:
                    OverviewView(entries: entries, ledger: ledger)
                case .transactions:
                    TransactionsView(entries: entries, adjustments: adjustments, ledger: ledger)
                case .statistics:
                    StatisticsView(entries: entries, adjustments: adjustments, ledger: ledger)
                }
            }
            .frame(minWidth: 760, minHeight: 520)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $app.selection) {
                        ForEach(Screen.allCases) { screen in
                            Text(screen.title).tag(screen)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
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
        }
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

#Preview {
    ContentView()
        .environment(AppModel())
        .modelContainer(for: [Entry.self, RecurringSeries.self, BalanceAdjustment.self], inMemory: true)
}
