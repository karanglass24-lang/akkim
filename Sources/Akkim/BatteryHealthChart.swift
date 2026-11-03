import SwiftUI
import Charts

/// Small area chart of reported battery health over time.
///
/// Deliberately minimal: no axes, a mint gradient, and a dashed line at the
/// service threshold, so it reads as a trend rather than a dashboard.
struct BatteryHealthChart: View {
    let samples: [BatteryHealthSample]
    var serviceThreshold: Int = 80

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Date", sample.timestamp),
                    y: .value("Health", sample.healthPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.mint.opacity(0.38), Color.mint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", sample.timestamp),
                    y: .value("Health", sample.healthPercent)
                )
                .foregroundStyle(Color.mint)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            RuleMark(y: .value("Service threshold", Double(serviceThreshold)))
                .foregroundStyle(Color.orange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            // Make the very first measurements visible before a line can be drawn.
            if samples.count <= 3 {
                ForEach(samples) { sample in
                    PointMark(
                        x: .value("Date", sample.timestamp),
                        y: .value("Health", sample.healthPercent)
                    )
                    .foregroundStyle(Color.mint)
                    .symbolSize(16)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    /// Pads the visible range so small health changes stay readable.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map { Double($0.healthPercent) }
        let lowest = max(0, (values.min() ?? Double(serviceThreshold)) - 3)
        let highest = min(100, (values.max() ?? 100) + 3)
        return Double(lowest)...Double(max(lowest + 2, highest))
    }
}
