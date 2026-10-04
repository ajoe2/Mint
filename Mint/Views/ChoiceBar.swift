//
//  ChoiceBar.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import SwiftUI

/// A segmented-style picker that works from the keyboard even without Full Keyboard Access: it's
/// one Tab stop, ← and → change the choice, and each choice can have its own shortcut.
struct ChoiceBar<Value: Hashable>: View {
    struct Choice: Identifiable {
        let value: Value
        let title: String
        var shortcut: KeyboardShortcut?

        var id: Value { value }
    }

    /// Custom fill and text color for a selected choice that should stand out.
    struct Highlight {
        let fill: Color
        let text: Color
    }

    let label: String
    let choices: [Choice]
    @Binding var selection: Value
    var highlight: (Value) -> Highlight? = { _ in nil }
    /// Turn off when every choice has a shortcut, to drop the bar from the Tab order.
    var isFocusable = true
    var focusOnAppear = false

    @FocusState private var isFocused: Bool
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices) { choice in
                let isSelected = choice.value == selection
                let style = isSelected ? highlight(choice.value) : nil
                Button {
                    select(choice.value)
                } label: {
                    Text(choice.title)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(style?.text ?? (isSelected ? Color.primary : Color.secondary))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(style?.fill ?? Theme.thumb)
                                    .shadow(color: .black.opacity(style == nil ? 0.12 : 0), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "thumb", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .keyboardShortcut(choice.shortcut)
                .help(choice.shortcut.map { "\(choice.title) (\($0.symbols))" } ?? "")
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: .capsule)
        // Keeps the focus ring inside the control's bounds so a parent can't clip it.
        .padding(3)
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2.5)
                .opacity(isFocused ? 1 : 0)
        }
        .fixedSize()
        .focusable(isFocusable, interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            step(by: press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onAppear {
            if focusOnAppear { isFocused = true }
        }
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func select(_ value: Value) {
        withAnimation(.snappy(duration: 0.25)) { selection = value }
    }

    private func step(by offset: Int) {
        guard let index = choices.firstIndex(where: { $0.value == selection }) else { return }
        let next = min(max(index + offset, 0), choices.count - 1)
        select(choices[next].value)
    }
}

extension KeyboardShortcut {
    /// The shortcut as menus show it, like "⌘1" or "⇧⌘D".
    var symbols: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + String(key.character).uppercased()
    }
}
