//
//  MoneyTests.swift
//  MintTests
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation
import Testing
@testable import Mint

@MainActor
struct MoneyTests {
    let us = Locale(identifier: "en_US")

    @Test(arguments: [
        ("12.50", 1250), ("12.5", 1250), ("$1,234.56", 123456), ("1234", 123400),
        (".5", 50), (" 7 ", 700), ("0", 0), ("12.345", 1235), ("12.344", 1234),
    ])
    func parsesAmounts(text: String, cents: Int) {
        #expect(Money.parseCents(text, locale: us) == cents)
    }

    @Test(arguments: [
        "", "abc", "-5", "1.2.3", ".", "12a",
        // Misplaced commas: probably a mistyped decimal point.
        "12,50", "1,23", "1,2345", ",500", "1234,567",
        // More than a trillion dollars.
        "1000000000000.01",
    ])
    func rejectsInvalidAmounts(text: String) {
        #expect(Money.parseCents(text, locale: us) == nil)
    }

    @Test(arguments: [("1,234", 123400), ("12,345.67", 1234567), ("$1,000,000", 100000000)])
    func acceptsThousandsSeparators(text: String, cents: Int) {
        #expect(Money.parseCents(text, locale: us) == cents)
    }

    @Test func followsOtherLocales() {
        #expect(Money.parseCents("1,23,456.50", locale: Locale(identifier: "en_IN")) == 123_456_50)
        #expect(Money.parseCents("1.234,56", locale: Locale(identifier: "de_DE")) == 1_234_56)
        #expect(Money.parseCents("12.50", locale: Locale(identifier: "de_DE")) == nil)
        #expect(Money.parseCents("\u{0661}\u{0662}\u{0663}", locale: us) == 123_00)
    }

    @Test func allowsANegativeStartingBalance() {
        #expect(Money.parseSignedCents("-25.10", locale: us) == -2510)
        #expect(Money.parseSignedCents("\u{2212}$5", locale: us) == -500)
        #expect(Money.parseSignedCents("40", locale: us) == 4000)
    }

    @Test(arguments: [0, 1, 99, 100, 123456, 100_000_000])
    func editingTextRoundTrips(cents: Int) {
        #expect(Money.parseCents(Money.editingText(fromCents: cents)) == cents)
    }

    @Test(arguments: [0, 1250, -1250, 123456789])
    func formattedTextRoundTrips(cents: Int) {
        #expect(Money.parseSignedCents(Money.format(cents)) == cents)
    }
}

@MainActor
struct MoneyDisplayTests {
    @Test func splitsCentsForDisplay() {
        let parts = Money.displayParts(929_829)
        #expect(parts.whole + parts.fraction == Money.format(929_829))
        #expect(parts.fraction == (Locale.current.decimalSeparator ?? ".") + "29")
    }

    @Test func examplesUseTheLocalDecimalSeparator() {
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(Money.typingExample(12_50) == "12\(separator)50")
        #expect(Money.parseCents(Money.typingExample(12_50)) == 12_50)
    }
}
