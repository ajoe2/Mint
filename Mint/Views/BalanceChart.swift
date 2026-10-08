//
//  BalanceChart.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Charts
import SwiftUI

/// The balance as one smooth line over a soft fill: solid up to today, then dotted with a fainter
/// fill for the projection. A dot marks today and a ring the lowest point ahead, and the line
/// turns red below the low-balance limit. Hovering picks a day, which the panel above shows.
struct BalanceChart: View {
    let points: [BalancePoint]
    let ledger: Ledger
    /// The lowest point ahead, marked with a ring. Its amount is on the line above the chart.
    var lowest: BalancePoint?
    /// The low-balance limit. Once the balance dips below it, a rule marks it.
    var limit = 0
    /// The day under the pointer.
    @Binding var selection: BalancePoint?

    /// How strong the fill is just under the line's highest point, up to today and after it.
    private static let historyFill = 0.3
    private static let projectionFill = 0.12

    private var history: [BalancePoint] { points.filter { !$0.isProjected } }
    private var projection: [BalancePoint] { points.filter(\.isProjected) }

    /// The projection's line starts from today's actual balance, so it carries on from the
    /// history. Its fill doesn't: a smooth area with two points on one day draws a stray sliver.
    private var projectedLine: [BalancePoint] {
        guard let now = history.last, now.day == projection.first?.day else { return projection }
        return [now] + projection
    }

    var body: some View {
        let scale = Scale(points: points, limit: limit)
        let history = self.history
        let projection = self.projection
        let projectedLine = self.projectedLine
        Chart {
            fill(history, series: "History", strength: Self.historyFill, scale: scale)
            fill(projection, series: "Projection", strength: Self.projectionFill, scale: scale)

            RuleMark(x: .value("Today", ledger.today, unit: .day))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    if selection == nil {
                        Text("Today")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

            if let limit = scale.limit {
                RuleMark(y: .value("Limit", limit))
                    .foregroundStyle(Theme.unpaidText.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(Money.compact(limit))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.unpaidText)
                    }
            }

            line(history, series: "History", dash: [])
            // Round caps turn the tiny dashes into dots.
            line(projectedLine, series: "Projection", dash: [0.1, 5])

            if let lowest {
                PointMark(x: .value("Date", lowest.day, unit: .day), y: .value("Balance", Money.chartValue(fromCents: lowest.cents)))
                    .symbol { Ring(color: color(for: lowest)) }
            }

            if let now = history.last {
                PointMark(x: .value("Date", now.day, unit: .day), y: .value("Balance", Money.chartValue(fromCents: now.cents)))
                    .symbol { Dot(color: color(for: now), hasHalo: true) }
            }

            if let selection {
                RuleMark(x: .value("Selected", selection.day, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(DayText.relative(selection.day, today: ledger.today, calendar: ledger.calendar))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                PointMark(x: .value("Date", selection.day, unit: .day), y: .value("Balance", Money.chartValue(fromCents: selection.cents)))
                    .symbol { Dot(color: color(for: selection)) }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartXSelection(value: Binding(
            get: { selection?.day },
            set: { selection = $0.flatMap(point(on:)) }
        ))
        // Space for the labels above the plot.
        .padding(.top, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance chart")
        .accessibilityValue(summary)
    }

    /// The fill under a series, fading from the accent at the top to clear at the baseline, and
    /// to red below it.
    private func fill(_ series: [BalancePoint], series name: String, strength: Double, scale: Scale) -> some ChartContent {
        let style = scale.fill(for: series.map { Money.chartValue(fromCents: $0.cents) }, strength: strength)
        return ForEach(series) { point in
            AreaMark(
                x: .value("Date", point.day, unit: .day),
                yStart: .value("Base", scale.baseline),
                yEnd: .value("Balance", Money.chartValue(fromCents: point.cents)),
                series: .value("Series", name)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(style)
        }
    }

    private func line(_ series: [BalancePoint], series name: String, dash: [CGFloat]) -> some ChartContent {
        let style = stroke(for: series)
        return ForEach(series) { point in
            LineMark(
                x: .value("Date", point.day, unit: .day),
                y: .value("Balance", Money.chartValue(fromCents: point.cents)),
                series: .value("Series", name)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(style)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: dash))
        }
    }

    /// The accent color, or red below the limit. A gradient spans just its own series, from the
    /// lowest balance to the highest, so the red stops where the limit falls in between.
    private func stroke(for series: [BalancePoint]) -> AnyShapeStyle {
        let values = series.map(\.cents)
        guard let low = values.min(), let high = values.max(), low < limit else { return AnyShapeStyle(Color.accentColor) }
        guard high > limit else { return AnyShapeStyle(Theme.unpaidText) }
        let split = Double(limit - low) / Double(high - low)
        return AnyShapeStyle(LinearGradient(
            stops: [
                .init(color: Theme.unpaidText, location: 0),
                .init(color: Theme.unpaidText, location: split),
                .init(color: .accentColor, location: split),
                .init(color: .accentColor, location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        ))
    }

    private func color(for point: BalancePoint) -> Color {
        point.cents < limit ? Theme.unpaidText : .accentColor
    }

    /// The point for the day containing `date`. For today, that's the actual balance rather than
    /// the projection.
    private func point(on date: Date) -> BalancePoint? {
        let day = ledger.day(date)
        return points.first { $0.day == day } ?? points.last { $0.day <= day }
    }

    /// A one-sentence summary for VoiceOver.
    private var summary: String {
        var parts: [String] = []
        if let now = history.last {
            parts.append("Today \(Money.format(now.cents))")
        }
        if let lowest {
            parts.append("lowest ahead \(Money.format(lowest.cents)) on \(DayText.full(lowest.day))")
        }
        if let end = points.last, end.isProjected {
            parts.append("\(Money.format(end.cents)) by \(DayText.full(end.day))")
        }
        return parts.joined(separator: ", ")
    }
}

extension BalancePoint: Identifiable {
    struct ID: Hashable {
        let day: Date
        let isProjected: Bool
    }

    /// The day alone isn't enough: today has both its actual and its projected balance.
    var id: ID { ID(day: day, isProjected: isProjected) }
}

/// The chart's vertical range, and where the fill under the line fades out.
private struct Scale {
    /// The limit in dollars, if the balance dips below it.
    let limit: Double?
    let domain: ClosedRange<Double>

    init(points: [BalancePoint], limit: Int) {
        self.limit = points.contains { $0.cents < limit } ? Money.chartValue(fromCents: limit) : nil
        // The balances, and the limit when it's crossed, with 15% room (at least $1) above and below.
        var values = points.map { Money.chartValue(fromCents: $0.cents) }
        if let crossed = self.limit {
            values.append(crossed)
        }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let pad = max((high - low) * 0.15, 1)
        domain = (low - pad)...(high + pad)
    }

    /// Where the fill fades out: at the limit when it's crossed, so the fill below it can turn red,
    /// else at the bottom of the chart.
    var baseline: Double { limit ?? domain.lowerBound }

    /// The fill for a series with these balances: the accent fading out toward the baseline, and
    /// red below it fading out toward it. A gradient spans just its own series, from its highest
    /// point to its lowest (or the baseline), so the colors change where the baseline falls.
    func fill(for values: [Double], strength: Double) -> LinearGradient {
        let top = max(values.max() ?? baseline, baseline)
        let bottom = min(values.min() ?? baseline, baseline)
        guard bottom < baseline else {
            return LinearGradient(colors: [.accentColor.opacity(strength), .accentColor.opacity(0)], startPoint: .top, endPoint: .bottom)
        }
        let split = (top - baseline) / (top - bottom)
        return LinearGradient(
            stops: [
                .init(color: .accentColor.opacity(top > baseline ? strength : 0), location: 0),
                .init(color: .accentColor.opacity(0), location: split),
                .init(color: Theme.unpaidText.opacity(0), location: split),
                .init(color: Theme.unpaidText.opacity(strength), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A dot on the line, ringed in the card's color so it stands apart from the line. Today's has a
/// soft halo.
private struct Dot: View {
    let color: Color
    var hasHalo = false

    var body: some View {
        Circle()
            .fill(color)
            .padding(2)
            .background(Circle().fill(Theme.cardBackground))
            .frame(width: 12, height: 12)
            .background {
                if hasHalo {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 26, height: 26)
                }
            }
    }
}

/// An open ring on the line, for the lowest point ahead.
private struct Ring: View {
    let color: Color

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .background(Circle().fill(Theme.cardBackground))
            .frame(width: 10, height: 10)
    }
}
