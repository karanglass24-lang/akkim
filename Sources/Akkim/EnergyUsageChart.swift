import SwiftUI
import Charts

/// Daily AC energy bars for the last two weeks.
struct EnergyUsageChart: View {
    let days: [DailyEnergy]

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Energy", day.wallWh)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.teal.opacity(0.85), Color.teal.opacity(0.30)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

/// Today's AC energy per hour (0–23).
struct HourlyEnergyChart: View {
    let values: [Double]

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Hour", item.offset),
                    y: .value("Energy", item.element)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.teal.opacity(0.85), Color.teal.opacity(0.30)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(1.5)
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
