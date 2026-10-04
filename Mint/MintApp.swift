//
//  MintApp.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftUI
import SwiftData

@main
struct MintApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var app: AppModel
    let sharedModelContainer: ModelContainer
    /// Sends reminders. `nil` in tests and demo mode, so made-up bills never trigger one.
    private let reminders: ReminderCenter?

    init() {
        let app = AppModel()
        let container = Self.makeModelContainer()
        _app = State(initialValue: app)
        sharedModelContainer = container
        reminders = AppEnvironment.usesTemporaryData ? nil : ReminderCenter(container: container, app: app)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(AppEnvironment.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: AppEnvironment.usesTemporaryData)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if AppEnvironment.isDemo {
                SampleData.insert(into: container.mainContext, today: .now)
                try container.mainContext.save()
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        Window("Mint", id: "main") {
            ContentView()
                .environment(app)
                .environment(reminders)
                .defaultAppStorage(AppEnvironment.defaults)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1100, height: 780)
        .commands {
            FileCommands(app: app)
            CommandGroup(replacing: .sidebar) {
                // Off during setup or while a sheet is open, so ⌘1–⌘4 can pick the kind in the entry editor.
                Group {
                    ForEach(Array(Screen.allCases.enumerated()), id: \.element) { index, screen in
                        Button(screen.title) { app.selection = screen }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    }
                    Button("Next Tab") { app.selection = app.selection.moved(by: 1) }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                    Button("Previous Tab") { app.selection = app.selection.moved(by: -1) }
                        .keyboardShortcut("[", modifiers: [.command, .shift])
                }
                .disabled(!app.isBrowsing)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") { app.searchFocusRequest += 1 }
                    .keyboardShortcut("f")
                    .disabled(!app.isBrowsing)
            }
            EntryCommands()
            HelpCommands()
        }

        Settings {
            SettingsView()
                .environment(app)
                .environment(reminders)
                .defaultAppStorage(AppEnvironment.defaults)
        }
        .modelContainer(sharedModelContainer)

        Window("Keyboard Shortcuts", id: ShortcutsView.windowID) {
            ShortcutsView()
        }
        .windowResizability(.contentSize)
    }
}

/// File ▸ New Entry, and Adjust Balance, which opens Settings to set it there.
struct FileCommands: Commands {
    let app: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                Button("New Entry…") { app.editor = .new(app.newEntryKind) }
                    .keyboardShortcut("n")
                Button("Adjust Balance…") {
                    openSettings()
                    app.isAdjustingBalance = true
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            .disabled(!app.isBrowsing)
        }
    }
}

/// Lets Quit work while a sheet or dialog is open by closing it first. An open editor's changes
/// are discarded as if cancelled; everything else is already saved.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in sender.windows {
            endSheets(of: window)
        }
        return .terminateNow
    }

    private func endSheets(of window: NSWindow) {
        while let sheet = window.attachedSheet {
            endSheets(of: sheet)
            window.endSheet(sheet)
            // Stop rather than loop forever if a sheet doesn't close.
            if window.attachedSheet === sheet { break }
        }
    }
}
