import Foundation
import Combine

/// One battery-health measurement, kept across launches so the panel can show a
/// trend instead of a single value.
struct BatteryHealthSample: Codable, Identifiable, Equatable {
    let timestamp: Date
    let maxCapacitymAh: Int
    let designCapacitymAh: Int

    var id: Date { timestamp }

    var healthPercent: Int {
        guard designCapacitymAh > 0 else { return 0 }
        let pct = Double(maxCapacitymAh) / Double(designCapacitymAh) * 100.0
        return min(100, max(0, Int(pct.rounded())))
    }
}

/// Stores battery-health samples under Application Support.
///
/// A sample is appended at most every few hours (or immediately when the reported
/// maximum capacity changes), so the file stays small and the chart shows the
/// real trend rather than sampler noise.
@MainActor
final class BatteryHealthHistory: ObservableObject {
    @Published private(set) var samples: [BatteryHealthSample] = []

    private let fileURL: URL
    private var isPreview = false
    private let minimumInterval: TimeInterval = 6 * 60 * 60
    private let retention: TimeInterval = 180 * 24 * 60 * 60

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Akkim", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("health-history.json")
        load()
    }

    func record(_ sample: PowerSample?) {
        guard let sample,
              let maxCapacity = sample.maxCapacitymAh, maxCapacity > 0,
              let designCapacity = sample.designCapacitymAh, designCapacity > 0 else { return }

        let now = Date()
        if let last = samples.last,
           last.maxCapacitymAh == maxCapacity,
           now.timeIntervalSince(last.timestamp) < minimumInterval {
            return
        }

        samples.append(BatteryHealthSample(timestamp: now,
                                           maxCapacitymAh: maxCapacity,
                                           designCapacitymAh: designCapacity))
        prune(now)
        save()
    }

    /// Samples within the last `days` days (for the chart window).
    func window(days: Int) -> [BatteryHealthSample] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        return samples.filter { $0.timestamp >= cutoff }
    }

    #if DEBUG
    /// In-memory samples so documentation screenshots show a readable trend.
    /// Never written to disk and compiled out of release builds.
    func seedPreviewData() {
        isPreview = true
        let now = Date()
        let design = samples.last?.designCapacitymAh ?? 8694
        samples = (0..<21).map { index in
            let time = now.addingTimeInterval(-Double(20 - index) * 36 * 3600)
            let health = 78.0 - Double(index) * 0.08 + sin(Double(index) * 1.3) * 0.9
            return BatteryHealthSample(
                timestamp: time,
                maxCapacitymAh: Int(Double(design) * health / 100.0),
                designCapacitymAh: design
            )
        }
    }
    #endif

    private func prune(_ now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        samples.removeAll { $0.timestamp < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BatteryHealthSample].self, from: data) else {
            return
        }
        samples = decoded.sorted { $0.timestamp < $1.timestamp }
    }

    private func save() {
        guard !isPreview else { return }
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
