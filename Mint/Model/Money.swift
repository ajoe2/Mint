//
//  Money.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation

/// Amounts are stored as whole cents (`Int`) so sums are always exact.
enum Money {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    static var currencySymbol: String { Locale.current.currencySymbol ?? "$" }

    /// The largest allowed amount: a trillion dollars, far below where sums could overflow.
    static let maximumCents = 100_000_000_000_000

    static func decimal(fromCents cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Dollars as a `Double`, for charts only. Never use it for arithmetic.
    static func chartValue(fromCents cents: Int) -> Double {
        Double(cents) / 100
    }

    /// "$1,234.56", or "+$1,234.56" when `showPlus` is set and the amount is positive.
    static func format(_ cents: Int, showPlus: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode)
        let text = decimal(fromCents: cents).formatted(style)
        return showPlus && cents > 0 ? "+" + text : text
    }

    /// Splits "$9,298.29" into "$9,298" and ".29" so the cents can be drawn smaller.
    static func displayParts(_ cents: Int, showPlus: Bool = false) -> (whole: String, fraction: String) {
        let text = format(cents, showPlus: showPlus)
        let separator = Locale.current.decimalSeparator ?? "."
        guard let range = text.range(of: separator, options: .backwards) else { return (text, "") }
        return (String(text[..<range.lowerBound]), String(text[range.lowerBound...]))
    }

    /// "$1.2K" style labels for chart axes.
    static func compact(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: currencyCode).notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// Text to prefill an amount field, e.g. "1234.5" for 123450 cents.
    static func editingText(fromCents cents: Int) -> String {
        decimal(fromCents: cents).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    /// An amount as it'd be typed, with two decimals ("12.50", or "12,50" in some locales), for placeholders.
    static func typingExample(_ cents: Int) -> String {
        decimal(fromCents: cents).formatted(.number.grouping(.never).precision(.fractionLength(2)))
    }

    /// Parses a typed amount ("1,234.56", "$20", ".5") into cents, rounded to the nearest cent.
    /// `nil` unless it's a non-negative number no larger than `maximumCents`.
    static func parseCents(_ text: String, locale: Locale = .current) -> Int? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        // Turn digits from other scripts, such as Arabic-Indic, into 0-9.
        var cleaned = String(text.trimmingCharacters(in: .whitespacesAndNewlines).map { character in
            guard !character.isASCII, let digit = character.wholeNumberValue, (0...9).contains(digit) else { return character }
            return Character(String(digit))
        })

        // Reject badly grouped numbers: "12,50" is likely a mistyped decimal point, not 1,250.
        // Group sizes follow the locale, e.g. "1,23,456" in India.
        let wholePart = cleaned.components(separatedBy: decimalSeparator)[0]
        if wholePart.contains(groupingSeparator) {
            let groups = wholePart.components(separatedBy: groupingSeparator)
            let sizes = groupSizes(locale)
            guard (1...sizes.others).contains(groups[0].filter(\.isNumber).count),
                  groups.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                  groups.last?.count == sizes.last,
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == sizes.others })
            else { return nil }
        }

        for symbol in [locale.currencySymbol ?? "$", "$", groupingSeparator, " ", "\u{00A0}"] where !symbol.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: decimalSeparator, with: ".")

        guard !cleaned.isEmpty,
              cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              cleaned.filter({ $0 == "." }).count <= 1,
              cleaned != "."
        else { return nil }

        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var cents = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        guard rounded <= Decimal(maximumCents) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// `parseCents` that also allows a leading minus, for an overdrawn starting balance.
    static func parseSignedCents(_ text: String, locale: Locale = .current) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "-" || first == "\u{2212}" {
            return parseCents(String(trimmed.dropFirst()), locale: locale).map { -$0 }
        }
        return parseCents(trimmed, locale: locale)
    }

    /// Digits in the locale's last group and in each earlier group: (3, 3) for "1,234,567", (3, 2) for "12,34,567".
    private static func groupSizes(_ locale: Locale) -> (last: Int, others: Int) {
        let separator = locale.groupingSeparator ?? ","
        let groups = 1_234_567.formatted(.number.locale(locale)).components(separatedBy: separator)
        guard groups.count >= 3 else { return (3, 3) }
        return (groups[groups.count - 1].count, groups[groups.count - 2].count)
    }
}
