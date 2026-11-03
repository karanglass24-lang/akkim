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
