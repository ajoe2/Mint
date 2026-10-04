//
//  DayText.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Foundation

/// Short, friendly date labels.
enum DayText {
    /// "Today", "Tomorrow", "Yesterday", "Oct 10", or "Oct 10, 2025" outside the current year.
    static func short(_ date: Date, today: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let base = calendar.startOfDay(for: today)
        let offset = calendar.dateComponents([.day], from: base, to: day).day ?? 0
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            if calendar.isDate(day, equalTo: base, toGranularity: .year) {
                return date.formatted(.dateTime.month(.abbreviated).day())
            }
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    /// Like `short`, but adds the weekday for other days this year: "Thu, Oct 9".
    static func relative(_ date: Date, today: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let base = calendar.startOfDay(for: today)
        let offset = calendar.dateComponents([.day], from: base, to: day).day ?? 0
        guard abs(offset) > 1, calendar.isDate(day, equalTo: base, toGranularity: .year) else {
            return short(date, today: today, calendar: calendar)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Oct 10, 2026"
    static func full(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "October 2026"
    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
