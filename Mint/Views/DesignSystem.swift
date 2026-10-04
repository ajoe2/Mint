//
//  DesignSystem.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import AppKit
import SwiftUI

/// How things move. With Reduce Motion on in System Settings, changes happen at once instead.
enum Motion {
    static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// For changes to the data: rows, amounts, bars and the chart.
    static var standard: Animation? { isReduced ? nil : .snappy(duration: 0.35) }

    /// For controls, like a selector's highlight sliding over.
    static var quick: Animation? { isReduced ? nil : .snappy(duration: 0.25) }

    /// For one screen giving way to another. A fade isn't motion, so it stays with Reduce Motion on.
    static let fade = Animation.easeInOut(duration: 0.2)
}

/// The few colors and shapes every screen shares.
enum Theme {
    /// Light gray on the white window, like grouped settings; a step lighter than the window in dark mode.
    static let cardBackground = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.17, alpha: 1))
    static let cardRadius: CGFloat = 16
    /// The selected part of a choice bar: white in light mode, a lighter gray in dark mode.
    static let thumb = dynamic(light: .white, dark: NSColor(white: 0.38, alpha: 1))
    /// Row divider inset, so dividers start after the icon.
    static let rowDividerInset: CGFloat = 60

    // Status text: red unpaid, yellow scheduled, green paid. Deeper than the system fills in light
    // mode so small type stays readable.
    static let unpaidText = dynamic(light: NSColor(srgbRed: 0.77, green: 0.09, blue: 0.11, alpha: 1), dark: NSColor(srgbRed: 1, green: 0.45, blue: 0.42, alpha: 1))
    static let scheduledText = dynamic(light: NSColor(srgbRed: 0.54, green: 0.35, blue: 0, alpha: 1), dark: .systemYellow)
    static let paidText = dynamic(light: NSColor(srgbRed: 0.12, green: 0.48, blue: 0.27, alpha: 1), dark: .systemGreen)
    /// A solid red that white text reads well on in either mode.
    static let alertFill = Color(red: 0.8, green: 0.12, blue: 0.12)

    /// Green for money in, red for money out, the usual text color for zero.
    static func signed(_ cents: Int) -> Color {
        cents > 0 ? paidText : cents < 0 ? unpaidText : .primary
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension EntryStatus {
    /// For fills and icons; text uses `textColor`.
    var color: Color {
        switch self {
        case .unpaid: .red
        case .scheduled: .yellow
        case .paid: .green
        }
    }

    var textColor: Color {
        switch self {
        case .unpaid: Theme.unpaidText
        case .scheduled: Theme.scheduledText
        case .paid: Theme.paidText
        }
    }

    /// "Unpaid", "Scheduled" or "Paid", worded for the kind (e.g. "Received" for income).
    func label(for kind: EntryKind) -> String {
        switch self {
        case .unpaid: kind.notCompletedLabel
        case .scheduled: "Scheduled"
        case .paid: kind.completedLabel
        }
    }
}

extension View {
    /// The rounded panel every section sits on.
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// A scrolling page: its content in a readable column, centered in the window.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    static var maxWidth: CGFloat { 1080 }
    static var padding: CGFloat { 24 }

    /// How wide the content column is in a page `pageWidth` across.
    static func contentWidth(in pageWidth: CGFloat) -> CGFloat {
        min(pageWidth, maxWidth) - 2 * padding
    }

    var body: some View {
        ScrollView {
            content
                // Full column width even when little is listed, so controls at the top stay put.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.padding)
                .frame(maxWidth: Self.maxWidth)
                .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A heading over its content, with room for something small on the right.
struct TitledSection<Accessory: View, Content: View>: View {
    let title: String
    var tint: Color = .primary
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String,
        tint: Color = .primary,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(tint)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                accessory
                    .font(.callout)
            }
            content
        }
    }
}

/// Rows stacked on one card, with a hairline between them.
struct RowCard<Item, ID: Hashable, Row: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items, id: id) { item in
                if item[keyPath: id] != items.first?[keyPath: id] {
                    Divider().padding(.leading, Theme.rowDividerInset)
                }
                row(item)
            }
        }
        .card(padding: 0)
        .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// A colored symbol on a softly tinted rounded square.
struct TintIcon: View {
    let symbol: String
    let color: Color
    let label: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel(label)
    }
}

/// The icon for an entry: its category's symbol (or its kind's) in its kind's color.
struct KindIcon: View {
    let kind: EntryKind
    var category = ""
    var size: CGFloat = 34

    var body: some View {
        TintIcon(symbol: kind.symbol(forCategory: category), color: kind.color, label: kind.title, size: size)
    }
}

/// A signed amount for lists: money in is green with a plus sign, money out has a minus sign.
struct AmountText: View {
    let cents: Int

    var body: some View {
        Text(Money.format(cents, showPlus: true))
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(cents > 0 ? Theme.paidText : Color.primary)
    }
}

/// A large amount with smaller cents, so it reads at a glance.
struct MoneyText: View {
    let cents: Int
    var size: CGFloat = 34
    var showPlus = false

    var body: some View {
        let parts = Money.displayParts(cents, showPlus: showPlus)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.whole)
                .font(.system(size: size, weight: .bold, design: .rounded))
            Text(parts.fraction)
                .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                .opacity(0.6)
        }
        .monospacedDigit()
        // The digits roll to a new amount.
        .contentTransition(.numericText(value: Double(cents)))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Money.format(cents, showPlus: showPlus))
    }
}

/// A row's status at a glance. Paid and scheduled entries, which need nothing from you, get a
/// symbol: a green check or an amber clock. Anything else gets a word, filled solid when it
/// needs doing.
struct StatusMark: View {
    let text: String
    let status: EntryStatus
    var symbol: String?
    var isProminent = false

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(status.textColor)
                    // The same height as a word, so rows line up either way.
                    .frame(width: 28, height: 22)
            } else {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isProminent ? (status == .scheduled ? Color.black : Color.white) : status.textColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(fill, in: .capsule)
            }
        }
        // "Unpaid" blends into a check rather than swapping.
        .contentTransition(.interpolate)
    }

    private var fill: Color {
        guard isProminent else { return status.color.opacity(0.15) }
        return status == .scheduled ? .yellow : Theme.alertFill
    }
}

/// A text link in Mint's green, for "See all" and the like. The system link style is blue.
struct AccentLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == AccentLinkStyle {
    static var accentLink: AccentLinkStyle { AccentLinkStyle() }
}

/// A label and amount over a `Bar`.
struct BarRow: View {
    let title: String
    var symbol: String?
    let detail: String
    let fraction: Double
    var pending: Double = 0
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                Spacer()
                Text(detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.callout)
            Bar(fraction: fraction, pending: pending, color: color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rounded bar filled to `fraction`, with a lighter stretch after it for `pending`.
struct Bar: View {
    let fraction: Double
    var pending: Double = 0
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let solid = proxy.size.width * min(max(fraction, 0), 1)
            let total = proxy.size.width * min(max(fraction + pending, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                if pending > 0 {
                    Capsule().fill(color.opacity(0.35)).frame(width: max(total, 6))
                }
                if fraction > 0 {
                    Capsule().fill(color.gradient).frame(width: max(solid, 6))
                }
            }
        }
        .frame(height: 7)
    }
}
