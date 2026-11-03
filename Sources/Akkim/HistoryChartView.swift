import SwiftUI
import Charts

/// 최근 배터리 전력(충전은 +, 방전은 −)과 충전 잔량(SoC) 흐름을 보여주는 미니 차트.
///
/// SoC 차트에는 현재 제한선(실선)과 세일링 하한선(점선)을 겹쳐 그려
/// 히스테리시스가 눈으로 이해되도록 합니다.
struct HistoryChartView: View {
    let samples: [PowerSample]
    var limit: Int? = nil
    var deadband: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            powerChart
            if socSamples.count >= 2 {
                Text(L10n.t(.stateOfCharge))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                socChart
            }
        }
    }

    // MARK: Power (W)

    private var powerChart: some View {
        Group {
            if samples.count < 2 {
                placeholder
            } else {
                Chart {
                    ForEach(samples, id: \.timestamp) { sample in
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Watts", sample.batteryWatts)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Watts", sample.batteryWatts)
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    RuleMark(y: .value("Zero", 0.0))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: powerDomain)
            }
        }
        .frame(height: 64)
        .clipped()
    }

    // MARK: State of charge (%)

    private var socChart: some View {
        Group {
            if socSamples.count < 2 {
                EmptyView()
            } else {
                Chart {
                    ForEach(socSamples, id: \.timestamp) { sample in
                        if let soc = sample.stateOfChargePercent {
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("SoC", Double(soc))
                            )
                            .foregroundStyle(Color.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                        }
                    }

                    if let limit = limit {
                        RuleMark(y: .value("Limit", Double(limit)))
                            .foregroundStyle(Color.orange.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    if let lower = lowerLimit {
                        RuleMark(y: .value("Lower", Double(lower)))
                            .foregroundStyle(Color.orange.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYScale(domain: 0.0...100.0)
                .frame(height: 44)
                .clipped()
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Text(L10n.t(.collectingData))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }

    private var socSamples: [PowerSample] {
        samples.filter { $0.stateOfChargePercent != nil }
    }

    /// Sailing lower bound (`limit - deadband`), or nil when not applicable.
    private var lowerLimit: Int? {
        guard let limit = limit, deadband > 0 else { return nil }
        let lower = max(0, limit - deadband)
        return lower > 0 ? lower : nil
    }

    private var powerDomain: ClosedRange<Double> {
        let values = samples.map { $0.batteryWatts }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let lo = Swift.min(minV, 0) - 1
        let hi = Swift.max(maxV, 0) + 1
        return lo...(hi > lo ? hi : lo + 1)
    }
}
