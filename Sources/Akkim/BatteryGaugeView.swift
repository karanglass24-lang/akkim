import SwiftUI

/// 원형 배터리 잔량 게이지 (최신 macOS 스타일)
struct BatteryGaugeView: View {
    let percentage: Int?
    let isCharging: Bool
    let size: CGFloat

    private var gaugeColor: Color {
        guard let p = percentage else { return .gray }
        if p >= 80 { return .green }
        if p >= 50 { return .yellow }
        if p >= 20 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            // 배경 트랙
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 8)

            // 충전 중 애니메이션 링
            if isCharging, percentage != nil {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isCharging)
            }

            // 배터리 게이지
            if let p = percentage {
                Circle()
                    .trim(from: 0, to: CGFloat(p) / 100.0)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: p)
            }

            // 중앙 퍼센트 텍스트
            VStack {
                Text(percentage.map { "\($0)" } ?? "--")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("%")
                    .font(.system(size: size * 0.10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
