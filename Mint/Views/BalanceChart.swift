//
//  BalanceChart.swift
//  Mint
//
//  Created by Andy Joe on 10/2/26.
//

import Charts
import SwiftUI

/// A slim balance chart: solid for the past, dashed for the projection, with today and the lowest
/// point ahead marked. Hover to see any day's balance.
struct BalanceChart: View {
    let points: [BalancePoint]
    let today: Date
    /// The lowest point ahead, when it's worth pointing out.
    var lowest: BalancePoint?

    @State private var selectedDay: Date?

    private var actual: [BalancePoint] { points.filter { !$0.isProjected } }
    private var projected: [BalancePoint] { points.filter(\.isProjected) }

    private var selectedPoint: BalancePoint? {
        guard let selectedDay else { return nil }
        let day = Calendar.current.startOfDay(for: selectedDay)
        return points.last { $0.day <= day }
    }

    /// Fits the balances with 15% padding (at least $1) instead of starting at zero.
    private var domain: ClosedRange<Double> {
        let values = points.map { Money.chartValue(fromCents: $0.cents) }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let pad = max((high - low) * 0.15, 1)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        let domain = self.domain
        Chart {
            ForEach(actual, id: \.day) { point in
                AreaMark(
                    x: .value("Date", point.day, unit: .day),
                    yStart: .value("Base", domain.lowerBound),
                    yEnd: .value("Balance", Money.chartValue(fromCents: point.cents))
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                LineMark(
                    x: .value("Date", point.day, unit: .day),
                    y: .value("Balance", Money.chartValue(fromCents: point.cents)),
                    series: .value("Series", "Actual")
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(projected, id: \.day) { point in
                LineMark(
                    x: .value("Date", point.day, unit: .day),
                    y: .value("Balance", Money.chartValue(fromCents: point.cents)),
                    series: .value("Series", "Projected")
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color.accentColor.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
            }

            RuleMark(x: .value("Today", today, unit: .day))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    if selectedPoint == nil {
                        Text("Today")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

            if let lowest {
                PointMark(
                    x: .value("Date", lowest.day, unit: .day),
                    y: .value("Balance", Money.chartValue(fromCents: lowest.cents))
                )
                .foregroundStyle(lowest.cents < 0 ? Theme.unpaidText : Color.accentColor)
                .symbolSize(36)
                .annotation(position: .bottom, spacing: 3, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    if selectedPoint == nil {
                        Text("Low \(Money.format(lowest.cents))")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(lowest.cents < 0 ? Theme.unpaidText : Color.secondary)
                    }
                }
            }

            if points.contains(where: { $0.cents < 0 }) {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.day, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(DayText.full(selectedPoint.day))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(Money.format(selectedPoint.cents))
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                            if selectedPoint.isProjected {
                                Text("Projected")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXSelection(value: $selectedDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    .foregroundStyle(Color.secondary)
            }
        }
        // Space for the "Today" label above the plot.
        .padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance chart")
        .accessibilityValue(summary)
    }

    /// A one-sentence summary for VoiceOver.
    private var summary: String {
        var parts: [String] = []
        if let now = actual.last {
            parts.append("Today \(Money.format(now.cents))")
        }
        if let lowest {
            parts.append("lowest ahead \(Money.format(lowest.cents)) on \(DayText.full(lowest.day))")
        }
        if let end = projected.last {
            parts.append("\(Money.format(end.cents)) by \(DayText.full(end.day))")
        }
        return parts.joined(separator: ", ")
    }
}
