import Foundation
import Combine

/// Energy accumulated for one calendar day.
struct DailyEnergy: Codable, Identifiable, Equatable {
    /// Local day key, `yyyy-MM-dd`.
    let day: String
    var wallWh: Double = 0
    var systemWh: Double = 0
    var chargedWh: Double = 0
    var dischargedWh: Double = 0

    var id: String { day }

    var date: Date {
        DailyEnergy.formatter.date(from: day) ?? Date()
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

/// Integrates the live power samples into per-day energy buckets and persists
/// them, so the panel can show today / 7-day / 30-day consumption.
///
/// Totals only cover time while the app is running. Gaps (sleep, app quit) are
/// ignored, and a single interval is capped so a wake-up cannot inflate a day.
@MainActor
final class EnergyUsageStore: ObservableObject {
    @Published private(set) var buckets: [DailyEnergy] = []

    private let fileURL: URL
    private var lastSampleTime: Date?
    private var isPreview = false
    private var lastSavedAt = Date.distantPast
    private let retentionDays = 400
    private let maximumInterval: TimeInterval = 5

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Akkim", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("energy-usage.json")
        load()
    }

    // MARK: Recording

    func record(_ sample: PowerSample?) {
        guard let sample else { return }
        let now = sample.timestamp
        defer { lastSampleTime = now }
        guard let previous = lastSampleTime else { return }

        let interval = min(max(now.timeIntervalSince(previous), 0), maximumInterval)
        guard interval > 0 else { return }
        let hours = interval / 3600

        let day = DailyEnergy.formatter.string(from: now)
        if buckets.last?.day != day {
            buckets.append(DailyEnergy(day: day))
        }

        var bucket = buckets.removeLast()
        if let wall = sample.wallOutputWatts, wall > 0 {
            bucket.wallWh += wall * hours
        }
        if let system = sample.systemLoadWatts, system > 0 {
            bucket.systemWh += system * hours
        }
        if sample.batteryWatts >= 0 {
            bucket.chargedWh += sample.batteryWatts * hours
        } else {
            bucket.dischargedWh += -sample.batteryWatts * hours
        }
        buckets.append(bucket)

        prune()
        saveIfNeeded()
    }

    /// Writes pending changes immediately (called on app termination).
    func flush() {
        save()
    }

    // MARK: Queries

    /// Sum of a metric over the last `days` days, including today.
    func total(days: Int, _ metric: KeyPath<DailyEnergy, Double>) -> Double {
        let cutoff = cutoffKey(days: days)
        return buckets
            .filter { $0.day >= cutoff }
            .reduce(0) { $0 + $1[keyPath: metric] }
    }

    func today(_ metric: KeyPath<DailyEnergy, Double>) -> Double {
        let today = DailyEnergy.formatter.string(from: Date())
        return buckets.last(where: { $0.day == today })?[keyPath: metric] ?? 0
    }

    /// The last `days` days, oldest first, including days without samples.
    func series(days: Int) -> [DailyEnergy] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var byDay: [String: DailyEnergy] = [:]
        for bucket in buckets { byDay[bucket.day] = bucket }
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DailyEnergy.formatter.string(from: date)
            return byDay[key] ?? DailyEnergy(day: key)
        }
    }

    // MARK: Persistence

    private func cutoffKey(days: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .day, value: -(days - 1), to: start) ?? start
        return DailyEnergy.formatter.string(from: date)
    }

    private func prune() {
        let cutoff = cutoffKey(days: retentionDays)
        buckets.removeAll { $0.day < cutoff }
    }

    private func saveIfNeeded() {
        guard Date().timeIntervalSince(lastSavedAt) >= 30 else { return }
        save()
    }

    private func save() {
        // Documentation screenshots use synthetic buckets; never persist those.
        guard !isPreview else { return }
        lastSavedAt = Date()
        guard let data = try? JSONEncoder().encode(buckets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DailyEnergy].self, from: data) else {
            return
        }
        buckets = decoded.sorted { $0.day < $1.day }
    }

    #if DEBUG
    /// In-memory data so documentation screenshots show a full chart.
    func seedPreviewData() {
        isPreview = true
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        buckets = (0..<14).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let day = DailyEnergy.formatter.string(from: date)
            let base = 28.0 + Double((offset * 7) % 9) + Double(offset % 3) * 2.4
            return DailyEnergy(
                day: day,
                wallWh: base,
                systemWh: base * 0.92,
                chargedWh: base * 0.45,
                dischargedWh: base * 0.38
            )
        }
    }
    #endif
}
