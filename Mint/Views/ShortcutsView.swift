//
//  ShortcutsView.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftUI

/// Help ▸ Keyboard Shortcuts: every shortcut, grouped by where it works.
struct ShortcutsView: View {
    static let windowID = "shortcuts"

    private struct ShortcutGroup: Identifiable {
        let title: String
        /// Several keys are alternatives, listed in the order the action names them.
        let shortcuts: [(action: String, keys: [String])]
        var id: String { title }
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Anywhere", shortcuts: [
            ("New entry", ["⌘N"]),
            ("Adjust balance", ["⇧⌘B"]),
            ("Overview, Transactions, Statistics", ["⌘1", "⌘2", "⌘3"]),
            ("Next or previous tab", ["⇧⌘]", "⇧⌘["]),
            ("Search", ["⌘F"]),
            ("Go from search to the results", ["↩"]),
            ("Undo or redo", ["⌘Z", "⇧⌘Z"]),
            ("Settings", ["⌘,"]),
            ("These shortcuts", ["⌘/"]),
        ]),
        ShortcutGroup(title: "Overview and Transactions", shortcuts: [
            ("Next or previous entry", ["↓", "↑"]),
            ("First or last entry", ["Home", "End"]),
            ("Edit", ["↩"]),
            ("Change status and dates", ["Space"]),
            ("Mark as paid, or unpaid", ["⌘K"]),
            ("Duplicate", ["⌘D"]),
            ("Delete", ["⌫"]),
            ("Delete this and future repeats", ["⌥⌘⌫"]),
            ("Clear the selection", ["Esc"]),
            ("Next or previous filter, in Transactions", ["→", "←"]),
        ]),
        ShortcutGroup(title: "Statistics", shortcuts: [
            ("Next or previous period", ["→", "←"]),
        ]),
        ShortcutGroup(title: "Adding or editing an entry", shortcuts: [
            ("Spend, Income, Investment, Subsidy", ["⌘1", "⌘2", "⌘3", "⌘4"]),
            ("Next or previous field", ["⇥", "⇧⇥"]),
            ("Change the status, once it's selected", ["→", "←"]),
            ("Add or remove the due date", ["⇧⌘D"]),
            ("Save", ["↩"]),
            ("Cancel", ["Esc"]),
            ("Delete", ["⌘⌫"]),
        ]),
    ]

    var body: some View {
        // One grid for all groups, so the keys line up all the way down.
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
            ForEach(groups) { group in
                GridRow {
                    Text(group.title)
                        .font(.system(.headline, design: .rounded))
                        .padding(.top, group.id == groups.first?.id ? 0 : 16)
                        .gridCellColumns(2)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.shortcuts, id: \.action) { shortcut in
                    GridRow {
                        Text(shortcut.action)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(shortcut.keys, id: \.self) { keys in
                                Text(keys)
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .frame(minWidth: 26)
                                    .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(28)
        .fixedSize()
    }
}
