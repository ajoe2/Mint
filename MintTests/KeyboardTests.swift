//
//  KeyboardTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Mint

@MainActor
struct KeyboardTests {
    private func ids(_ count: Int) throws -> [PersistentIdentifier] {
        let context = try makeContext()
        let entries = (0..<count).map { Entry(kind: .spend, title: "\($0)", amountCents: 100, date: nil) }
        entries.forEach(context.insert)
        try context.save()
        return entries.map(\.persistentModelID)
    }

    @Test func arrowKeysMoveThroughTheRows() throws {
        let rows = try ids(3)
        #expect(RowSelection.target(of: .downArrow, from: nil, in: rows) == rows[0])
        #expect(RowSelection.target(of: .upArrow, from: nil, in: rows) == rows[2])
        #expect(RowSelection.target(of: .downArrow, from: rows[0], in: rows) == rows[1])
        #expect(RowSelection.target(of: .downArrow, from: rows[2], in: rows) == rows[2])
        #expect(RowSelection.target(of: .upArrow, from: rows[0], in: rows) == rows[0])
        #expect(RowSelection.target(of: .end, from: rows[0], in: rows) == rows[2])
        #expect(RowSelection.target(of: .home, from: rows[2], in: rows) == rows[0])
        #expect(RowSelection.target(of: .downArrow, from: nil, in: []) == nil)
    }

    @Test func finishingARowSelectsTheNextOne() throws {
        let rows = try ids(3)
        #expect(RowSelection.neighbor(of: rows[1], in: rows) == rows[2])
        #expect(RowSelection.neighbor(of: rows[2], in: rows) == rows[1])
        #expect(RowSelection.neighbor(of: rows[0], in: Array(rows.prefix(1))) == nil)
    }

    @Test func menusShowTheShortcuts() throws {
        var shortcuts: [String: String] = [:]
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    shortcuts[item.title] = (item.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")
                        + (item.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "")
                        + (item.keyEquivalentModifierMask.contains(.command) ? "⌘" : "")
                        + item.keyEquivalent
                }
                item.submenu.map(walk)
            }
        }
        walk(try #require(NSApp.mainMenu))
        #expect(shortcuts["Edit…"] == "⌘o")
        #expect(shortcuts["Change Status…"] == "⌘i")
        #expect(shortcuts["Mark as Paid Today"] == "⇧⌘c")
        #expect(shortcuts["Duplicate…"] == "⌘d")
        #expect(shortcuts["Delete"] == "⌘\u{8}")
        #expect(shortcuts["Delete This and Future Repeats"] == "⌥⌘\u{8}")
        #expect(shortcuts["Find…"] == "⌘f")
        #expect(shortcuts["Keyboard Shortcuts"] == "⌘?")
    }

    /// A window showing the app with sample data, plus a function that presses keys in it.
    private func appWindow(showing screen: Screen, defaults: UserDefaults? = nil) throws -> (AppModel, ModelContext, NSWindow, (String, UInt16) -> Void) {
        let context = try makeContext()
        SampleData.insert(into: context, today: .now)
        try context.save()
        let app = AppModel()
        app.selection = screen
        let root = ContentView().environment(app).modelContainer(context.container).defaultAppStorage(defaults ?? AppEnvironment.defaults)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.setContentSize(NSSize(width: 1100, height: 780))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: .now + 1)

        let press = { (characters: String, keyCode: UInt16) in
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
                )!)
            }
            RunLoop.main.run(until: .now + 0.3)
        }
        return (app, context, window, press)
    }

    private let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    private let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    /// Sends real key presses to a window showing the app.
    @Test func listsWorkFromTheKeyboard() throws {
        let (app, context, window, press) = try appWindow(showing: .overview)
        defer { window.close() }

        // ↓ ↓ ↩ edits the second row: the overdue electric bill comes first.
        press(down, 125)
        press(down, 125)
        press("\r", 36)
        guard case .edit(let edited) = app.editor else {
            Issue.record("Return didn't open the editor")
            return
        }
        #expect(edited.title == "Phone bill")

        // With the editor closed, Delete removes the selected entry.
        app.editor = nil
        RunLoop.main.run(until: .now + 1)
        let before = try context.fetchCount(FetchDescriptor<Entry>())
        press("\u{7F}", 51)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == before - 1)
        #expect(try context.fetch(FetchDescriptor<Entry>()).allSatisfy { $0.title != "Phone bill" })

        // Esc clears the selection, so Return does nothing.
        press("\u{1B}", 53)
        press("\r", 36)
        #expect(app.editor == nil)
    }

    @Test func tabShortcutsSwitchScreens() throws {
        let (app, _, window, _) = try appWindow(showing: .overview)
        defer { window.close() }
        func press(_ characters: String, _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) {
            NSApp.sendEvent(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            )!)
            RunLoop.main.run(until: .now + 0.3)
        }
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        // Shift-Tab types a back-tab character instead of a tab.
        let backTab = String(UnicodeScalar(NSBackTabCharacter)!)

        // Real arrow key presses also carry the function and keypad flags.
        let arrow: NSEvent.ModifierFlags = [.command, .option, .function, .numericPad]
        press(right, 124, arrow)
        #expect(app.selection == .transactions)
        press("\t", 48, .control)
        #expect(app.selection == .statistics)
        // Both wrap around, like tabs in Safari.
        press("\t", 48, .control)
        #expect(app.selection == .overview)
        press(left, 123, arrow)
        #expect(app.selection == .statistics)
        press(backTab, 48, [.control, .shift])
        #expect(app.selection == .transactions)
    }

    @Test func arrowsFlipThroughFiltersAndPeriods() throws {
        let (app, _, transactions, pressInTransactions) = try appWindow(showing: .transactions)
        pressInTransactions(right, 124)
        pressInTransactions(right, 124)
        #expect(app.transactionFilter == .kind(.income))
        transactions.close()

        let suite = "com.ajoe.Mint.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (_, _, statistics, pressInStatistics) = try appWindow(showing: .statistics, defaults: defaults)
        defer { statistics.close() }
        pressInStatistics(right, 124)
        #expect(defaults.string(forKey: SettingsKey.statsPeriod) == StatsPeriod.year.rawValue)
    }
}
